import Foundation
import LlamaSwift

public struct Turn: Sendable, Codable {
    public let role: String
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct Generation: Sendable {
    public let text: String
    public let tokens: Int
    public let seconds: Double
    public let promptTokens: Int
}

public enum InferenceError: LocalizedError {
    case invalidFile, tooLarge, loadFailed, noModel, contextFull, unsupportedTemplate, decodeFailed
    public var errorDescription: String? {
        switch self {
        case .invalidFile: "Choose a complete GGUF model file."
        case .tooLarge: "This model exceeds the 1.1 GB file limit for this iPhone profile. Choose a smaller quantization."
        case .loadFailed: "The model could not be loaded. Check that its architecture is supported by llama.cpp and that enough memory is available."
        case .noModel: "Load a model from the Models tab first."
        case .contextFull: "This message is too long for the 2,048-token context. Shorten it or start a new conversation."
        case .unsupportedTemplate: "This model's chat template is not supported. Try a Gemma, Qwen, or Llama instruction model."
        case .decodeFailed: "Inference could not continue. Unload the model and try again."
        }
    }
}

public enum ModelFile {
    public static let maximumBytes: Int64 = 1_100_000_000
    public static func validate(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size > 1024 else { throw InferenceError.invalidFile }
        guard size <= maximumBytes else { throw InferenceError.tooLarge }
        try handle.seek(toOffset: 0)
        guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else { throw InferenceError.invalidFile }
    }
}

/// All C handles are confined to this actor. Loading, decoding, and freeing never overlap.
public actor LlamaEngine {
    private var session: Session?
    private static let backend: Void = { llama_backend_init() }()
    public init() { _ = Self.backend }

    public func load(_ url: URL) throws {
        session = nil
        try Task.checkCancellation()
        try ModelFile.validate(url)
        session = try Session(url: url)
        if Task.isCancelled { session = nil; throw CancellationError() }
    }
    public func unload() { session = nil }

    public func generate(turns: [Turn], limit: Int = 256,
                         onUpdate: @Sendable (Generation) -> Void) throws -> Generation {
        guard let session else { throw InferenceError.noModel }
        let maxTokens = min(max(limit, 1), 512)
        llama_memory_clear(llama_get_memory(session.context), true)
        defer { llama_memory_clear(llama_get_memory(session.context), true) }
        var history = turns
        var tokens = try session.tokenize(session.format(history))
        // Discard whole old exchanges, never arbitrary tokens or the newest user message.
        while tokens.count + maxTokens > 2048, history.count > 2 {
            history.removeFirst(2)
            tokens = try session.tokenize(session.format(history))
        }
        guard !tokens.isEmpty, tokens.count + maxTokens <= 2048 else { throw InferenceError.contextFull }
        let started = Date()
        for offset in stride(from: 0, to: tokens.count, by: 32) {
            try Task.checkCancellation()
            var chunk = Array(tokens[offset..<min(offset + 32, tokens.count)])
            let result = chunk.withUnsafeMutableBufferPointer {
                llama_decode(session.context, llama_batch_get_one($0.baseAddress, Int32($0.count)))
            }
            guard result == 0 else { throw InferenceError.decodeFailed }
        }
        guard let sampler = llama_sampler_init_greedy() else { throw InferenceError.decodeFailed }
        defer { llama_sampler_free(sampler) }
        var bytes = [UInt8]()
        var count = 0
        for _ in 0..<maxTokens {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, session.context, -1)
            if llama_vocab_is_eog(session.vocab, token) { break }
            bytes.append(contentsOf: session.piece(token))
            count += 1
            // Decode accumulated bytes so multibyte characters spanning tokens stay intact.
            if let text = String(bytes: bytes, encoding: .utf8) {
                onUpdate(Generation(text: text, tokens: count, seconds: Date().timeIntervalSince(started), promptTokens: tokens.count))
            }
            let result = withUnsafeMutablePointer(to: &token) {
                llama_decode(session.context, llama_batch_get_one($0, 1))
            }
            guard result == 0 else { throw InferenceError.decodeFailed }
        }
        return Generation(text: String(decoding: bytes, as: UTF8.self), tokens: count,
                          seconds: Date().timeIntervalSince(started), promptTokens: tokens.count)
    }
}

private final class Session {
    let model: OpaquePointer
    let context: OpaquePointer
    let vocab: OpaquePointer

    init(url: URL) throws {
        var modelParams = llama_model_default_params()
        modelParams.load_mode = LLAMA_LOAD_MODE_MMAP
        modelParams.n_gpu_layers = 99
        guard let model = llama_model_load_from_file(url.path, modelParams) else { throw InferenceError.loadFailed }
        var params = llama_context_default_params()
        params.n_ctx = 2048
        params.n_batch = 32
        params.n_ubatch = 32
        params.n_threads = 4
        params.n_threads_batch = 4
        guard let context = llama_init_from_model(model, params) else {
            llama_model_free(model)
            throw InferenceError.loadFailed
        }
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)!
    }
    deinit { llama_free(context); llama_model_free(model) }

    func format(_ turns: [Turn]) throws -> String {
        let roles = turns.map { strdup($0.role)! }
        let contents = turns.map { strdup($0.content)! }
        defer { roles.forEach { free($0) }; contents.forEach { free($0) } }
        let messages = zip(roles, contents).map { llama_chat_message(role: UnsafePointer($0), content: UnsafePointer($1)) }
        let template = llama_model_chat_template(model, nil)
        var buffer = [CChar](repeating: 0, count: max(4096, turns.reduce(0) { $0 + $1.content.utf8.count } * 2 + 4096))
        var length = llama_chat_apply_template(template, messages, messages.count, true, &buffer, Int32(buffer.count))
        if length > buffer.count {
            buffer = [CChar](repeating: 0, count: Int(length) + 1)
            length = llama_chat_apply_template(template, messages, messages.count, true, &buffer, Int32(buffer.count))
        }
        if length < 0 {
            var architecture = [CChar](repeating: 0, count: 128)
            llama_model_meta_val_str(model, "general.architecture", &architecture, architecture.count)
            let name = String(decoding: architecture.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard name.hasPrefix("qwen") else { throw InferenceError.unsupportedTemplate }
            return turns.map { "<|im_start|>\($0.role)\n\($0.content)<|im_end|>\n" }.joined() + "<|im_start|>assistant\n<think>\n</think>\n\n"
        }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    func tokenize(_ text: String) throws -> [llama_token] {
        var tokens = [llama_token](repeating: 0, count: text.utf8.count + 16)
        let length = llama_tokenize(vocab, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard length > 0 else { throw InferenceError.decodeFailed }
        return Array(tokens.prefix(Int(length)))
    }
    func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 256)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(max(0, Int(length))).map { UInt8(bitPattern: $0) }
    }
}
