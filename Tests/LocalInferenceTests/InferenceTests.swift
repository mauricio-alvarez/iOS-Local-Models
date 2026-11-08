import Foundation
import Testing
@testable import LocalInference

@Test func rejectsInvalidAndOversizedFiles() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(repeating: 0, count: 2048).write(to: url)
    #expect(throws: InferenceError.self) { try ModelFile.validate(url) }
    let handle = try FileHandle(forWritingTo: url)
    try handle.write(contentsOf: Data("GGUF".utf8))
    try handle.truncate(atOffset: UInt64(ModelFile.maximumBytes + 1))
    try handle.close()
    #expect(throws: InferenceError.self) { try ModelFile.validate(url) }
}

@Test func refusesGenerationWithoutModel() async {
    let engine = LlamaEngine()
    await #expect(throws: InferenceError.self) {
        try await engine.generate(turns: [Turn(role: "user", content: "Hello")]) { _ in }
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LOCAL_MODEL_TEST_PATH"] != nil))
func realInferenceLifecycle() async throws {
    let path = ProcessInfo.processInfo.environment["LOCAL_MODEL_TEST_PATH"]!
    let engine = LlamaEngine()
    try await engine.load(URL(fileURLWithPath: path))
    let result = try await engine.generate(turns: [Turn(role: "user", content: "What is the capital of France? Answer in one sentence.")], limit: 64) { _ in }
    #expect(result.text.localizedCaseInsensitiveContains("Paris"))
    #expect(result.tokens > 0 && result.tokens <= 64)
    #expect(result.promptTokens > 0)
    await #expect(throws: InferenceError.self) {
        try await engine.generate(turns: [Turn(role: "user", content: String(repeating: "hello ", count: 3000))]) { _ in }
    }
    let generation = Task { try await engine.generate(turns: [Turn(role: "user", content: "Count from one to a thousand.")], limit: 512) { _ in } }
    generation.cancel()
    do { _ = try await generation.value; Issue.record("Cancelled inference should stop") }
    catch is CancellationError { }
    await engine.unload()
    await #expect(throws: InferenceError.self) {
        try await engine.generate(turns: [Turn(role: "user", content: "Hello")]) { _ in }
    }
    // Loading again after release catches lifetime errors in native handle cleanup.
    try await engine.load(URL(fileURLWithPath: path))
    await engine.unload()
}
