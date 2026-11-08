import SwiftUI
import LocalInference

@main struct LocalModelsApp: App {
    @State private var studio = Studio()
    @State private var native = NativeTools()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView(studio: studio, native: native)
                .tint(.teal)
                .onChange(of: phase) { _, phase in
                    if phase == .background {
                        native.stopRecording()
                        studio.unload(reason: "Unloaded while in background")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    native.stopRecording()
                    studio.unload(reason: "Unloaded to free memory")
                }
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--smoke-test") { await smokeTest() }
                    #endif
                }
        }
    }
    #if DEBUG
    @MainActor private func smokeTest() async {
        let resultURL = Storage.directory.deletingLastPathComponent().appendingPathComponent("SmokeTest.json")
        let arguments = ProcessInfo.processInfo.arguments
        let requested = arguments.first(where: { $0.hasPrefix("--smoke-model=") }).map { String($0.dropFirst("--smoke-model=".count)) }
        guard let model = studio.models.first(where: { requested == nil || $0.id == requested }) else { return }
        let engine = LlamaEngine()
        do {
            try await engine.load(model.url)
            let result = try await engine.generate(turns: [Turn(role: "user", content: "What is the capital of France? Answer in one sentence.")], limit: 64) { _ in }
            let report: [String: Any] = ["model": model.id, "text": result.text, "tokens": result.tokens, "seconds": result.seconds, "promptTokens": result.promptTokens]
            try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted).write(to: resultURL)
            studio.messages = [ChatMessage(role: "user", text: "What is the capital of France?"), ChatMessage(role: "assistant", text: result.text)]
            studio.status = "Device inference verified"
            studio.metrics = "\(result.tokens) tokens · \(String(format: "%.1f", result.seconds))s"
        } catch {
            try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription]).write(to: resultURL)
            studio.error = error.localizedDescription
        }
        await engine.unload()
    }
    #endif
}
