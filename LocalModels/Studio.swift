import SwiftUI
import LocalInference
import AVFoundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    var text: String
}

@MainActor @Observable final class Studio {
    var models: [LocalModel] = []
    var active: LocalModel?
    var messages: [ChatMessage] = []
    var draft = ""
    var status = "No model loaded"
    var busy = false
    var generating = false
    var error: String?
    var metrics = ""
    var downloadID: String?
    var downloadProgress: Double = 0
    var importing = false
    var tab = 0
    var outputLimit = 256
    private let engine = LlamaEngine()
    private var work: Task<Void, Never>?
    private var download: Task<Void, Never>?
    private var runID: UUID?
    private var releasing = false
    private let speaker = AVSpeechSynthesizer()

    init() { refresh() }
    func refresh() {
        do { models = try Storage.scan() } catch { self.error = error.localizedDescription }
    }
    func load(_ model: LocalModel) {
        guard !busy else { return }
        busy = true
        active = nil
        status = "Loading \(model.name)…"
        work = Task {
            do {
                try await engine.load(model.url)
                try Task.checkCancellation()
                active = model
                status = "Ready on this iPhone"
                messages = []
                metrics = ""
                tab = 0
            } catch is CancellationError { status = "Model unloaded" }
            catch { self.error = error.localizedDescription; status = "Could not load model" }
            if !releasing { busy = false }
        }
    }
    func unload(reason: String = "Model unloaded") {
        guard !releasing else { return }
        releasing = true
        busy = true
        let pending = work
        work?.cancel()
        runID = nil
        active = nil
        speaker.stopSpeaking(at: .immediate)
        // The engine serializes this behind any decode already in flight.
        work = Task {
            await pending?.value
            await engine.unload()
            status = reason
            releasing = false
            busy = false
        }
    }
    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active != nil, !busy, !prompt.isEmpty else { return }
        guard prompt.utf8.count <= 24_000 else { error = InferenceError.contextFull.localizedDescription; return }
        draft = ""
        messages.append(ChatMessage(role: "user", text: prompt))
        let turns = messages.filter { !$0.text.isEmpty }.map { Turn(role: $0.role, content: $0.text) }
        messages.append(ChatMessage(role: "assistant", text: ""))
        let messageID = messages.last!.id
        let id = UUID()
        runID = id
        busy = true
        generating = true
        status = "Thinking locally…"
        metrics = ""
        work = Task {
            do {
                let result = try await engine.generate(turns: turns, limit: outputLimit) { [weak self] update in
                    Task { @MainActor in
                        guard let self, self.runID == id else { return }
                        self.update(messageID, with: update)
                    }
                }
                if runID == id { update(messageID, with: result) }
                status = active == nil ? "Model unloaded" : "Ready on this iPhone"
            } catch is CancellationError { status = "Stopped" }
            catch { self.error = error.localizedDescription; status = "Ready to try again" }
            if messages.last?.id == messageID, messages.last?.text.isEmpty == true {
                messages.removeLast()
                if messages.last?.role == "user" { messages.removeLast() }
                if draft.isEmpty { draft = prompt }
            }
            runID = nil
            if !releasing { busy = false }
            generating = false
        }
    }
    private func update(_ id: UUID, with result: Generation) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text = result.text.replacingOccurrences(of: "<think>\\s*</think>\\s*", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        metrics = "\(result.tokens) tokens · \(String(format: "%.1f", result.seconds))s · \(String(format: "%.1f", Double(result.tokens) / max(result.seconds, 0.01))) tok/s overall"
    }
    func stop() { work?.cancel() }
    func clear() { guard !busy else { return }; messages = []; metrics = "" }
    func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { self.error = error.localizedDescription; return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        speaker.speak(utterance)
    }
    func stopSpeaking() { speaker.stopSpeaking(at: .immediate) }
    func remove(_ model: LocalModel) {
        guard !busy, active?.id != model.id else { return }
        do { try FileManager.default.removeItem(at: model.url); refresh() }
        catch { self.error = error.localizedDescription }
    }
    func importModel(_ url: URL) {
        guard !importing else { return }
        importing = true
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() }; importing = false }
            do {
                try await Task.detached(priority: .utility) { try Storage.install(url, filename: url.lastPathComponent) }.value
                refresh()
            } catch { self.error = error.localizedDescription }
        }
    }
    func fetch(_ model: CatalogModel) {
        guard downloadID == nil else { return }
        downloadID = model.id
        downloadProgress = 0
        download = Task {
            defer { downloadID = nil; download = nil }
            let delegate = DownloadProgress { [self] fraction in
                Task { @MainActor in if self.downloadID == model.id { self.downloadProgress = fraction } }
            }
            do {
                let (temp, response) = try await URLSession.shared.download(from: model.url, delegate: delegate)
                defer { try? FileManager.default.removeItem(at: temp) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StoreError.network }
                let install = Task.detached(priority: .utility) { try Storage.install(temp, filename: model.filename, checksum: model.sha256) }
                try await withTaskCancellationHandler { try await install.value } onCancel: { install.cancel() }
                refresh()
            } catch is CancellationError { }
            catch let e as URLError where e.code == .cancelled { }
            catch { self.error = error.localizedDescription }
        }
    }
    func cancelDownload() { download?.cancel() }
}
