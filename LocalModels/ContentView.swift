import SwiftUI

struct ContentView: View {
    @Bindable var studio: Studio
    @Bindable var native: NativeTools
    @Bindable var speech: SpeechOutput
    @State private var sheet: ModelSheet?

    enum ModelSheet: String, Identifiable {
        case library, picker
        var id: String { rawValue }
    }

    var body: some View {
        TabView(selection: $studio.tab) {
            NavigationStack {
                ChatWorkspace(studio: studio, speech: speech, chooseModel: { sheet = .picker })
                    .toolbar { libraryButton }
            }
            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(TaskTab.chat)
            NavigationStack {
                OCRWorkspace(native: native) { text in sendToChat("Summarize this text:\n\n" + text) }
                    .toolbar { libraryButton }
            }
            .tabItem { Label("OCR", systemImage: "text.viewfinder") }.tag(TaskTab.ocr)
            NavigationStack {
                TranscribeWorkspace(native: native) { text in sendToChat(text) }
                    .toolbar { libraryButton }
            }
            .tabItem { Label("Transcribe", systemImage: "waveform") }.tag(TaskTab.transcribe)
            NavigationStack {
                SpeakWorkspace(speech: speech)
                    .toolbar { libraryButton }
            }
            .tabItem { Label("Speak", systemImage: "speaker.wave.2") }.tag(TaskTab.speak)
        }
        .sheet(item: $sheet) { destination in
            ModelLibrary(studio: studio, pickerOnly: destination == .picker) { model in
                sheet = nil
                studio.tab = .chat
                studio.load(model)
            }
        }
        .onChange(of: studio.tab) { old, new in
            if old == .transcribe { native.stopRecording() }
            if old == .speak { speech.stop() }
            if new != .chat, studio.active != nil || studio.busy {
                studio.unload(reason: "Load a model when you return to Chat")
            }
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { sheet == nil && (studio.error != nil || native.error != nil || speech.error != nil) },
            set: { if !$0 { studio.error = nil; native.error = nil; speech.error = nil } }
        )) {
            Button("OK") { studio.error = nil; native.error = nil; speech.error = nil }
        } message: { Text(studio.error ?? native.error ?? speech.error ?? "") }
    }

    @ToolbarContentBuilder private var libraryButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { sheet = .library } label: { Image(systemName: "square.stack.3d.up") }
                .accessibilityLabel("Model library")
        }
    }

    private func sendToChat(_ text: String) {
        native.stopRecording()
        studio.chatInput = .text
        studio.draft = text
        studio.tab = .chat
    }
}

enum TaskTab: Hashable { case chat, ocr, transcribe, speak }
enum ChatInput: String, CaseIterable { case text = "Text", image = "Image" }

struct EngineLabel: View {
    let name: String
    let detail: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.teal).frame(width: 6, height: 6)
            Text(name).font(.subheadline.weight(.medium))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct WorkspaceEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.teal).accessibilityHidden(true)
            Text(title).font(.title2.weight(.semibold))
            Text(detail).font(.body).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
    }
}

struct WorkspacePrimaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
        }.buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 18))
    }
}

struct ChatWorkspace: View {
    @Bindable var studio: Studio
    @Bindable var speech: SpeechOutput
    let chooseModel: () -> Void
    @FocusState private var promptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if studio.chatInput == .text {
                    Button(action: chooseModel) {
                        HStack(spacing: 8) {
                            Circle().fill(studio.active == nil ? Color.secondary : .teal).frame(width: 6, height: 6)
                            Text(studio.active?.name ?? "Choose a text model").font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.down").font(.caption2)
                            Spacer()
                            if studio.busy { ProgressView().controlSize(.small) }
                        }.foregroundStyle(.teal).padding(.vertical, 5)
                    }.accessibilityLabel("Choose chat model")
                    Text(studio.status).font(.caption).foregroundStyle(.secondary)
                } else {
                    EngineLabel(name: "Vision models", detail: "Not available yet")
                }
                Picker("Chat input", selection: $studio.chatInput) {
                    Label("Text", systemImage: "textformat").tag(ChatInput.text)
                    Label("Image", systemImage: "photo").tag(ChatInput.image)
                }.pickerStyle(.segmented)
            }.padding(.horizontal, 24).padding(.bottom, 12)

            if studio.chatInput == .image {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        WorkspaceEmptyState(symbol: "photo", title: "Ask about a photo", detail: "Image conversations will live here. A vision model is not available in this build yet.")
                        Button { studio.tab = .ocr } label: { Label("Read text from an image in OCR", systemImage: "text.viewfinder") }
                            .buttonStyle(.bordered)
                    }.padding(24)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        if studio.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 20) {
                                WorkspaceEmptyState(symbol: "bubble.left.and.bubble.right", title: "A conversation, on your iPhone.", detail: "Write, summarize, and explore with a local model. Your prompts stay on this device.")
                                if studio.active == nil {
                                    Button("Choose a model", action: chooseModel).buttonStyle(.borderedProminent)
                                } else {
                                    Button("Try a short summary") { studio.draft = "Summarize this in one sentence: "; promptFocused = true }.buttonStyle(.bordered)
                                }
                            }.padding(24)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(studio.messages) { message in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(message.role == "user" ? "YOU" : "ON DEVICE")
                                            .font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(message.role == "user" ? Color.secondary : .teal)
                                        Text(message.text.isEmpty ? "Thinking…" : message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                        if message.role == "assistant", !message.text.isEmpty, !studio.generating {
                                            HStack(spacing: 4) {
                                                Button { UIPasteboard.general.string = message.text } label: { Image(systemName: "doc.on.doc").frame(width: 40, height: 40) }.accessibilityLabel("Copy response")
                                                Button { speech.text = message.text; studio.tab = .speak } label: { Image(systemName: "speaker.wave.2").frame(width: 40, height: 40) }.accessibilityLabel("Open response in Speak")
                                                ShareLink(item: message.text) { Image(systemName: "square.and.arrow.up").frame(width: 40, height: 40) }
                                            }.font(.subheadline).foregroundStyle(.secondary).buttonStyle(.borderless)
                                        }
                                    }.id(message.id)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }.padding(24)
                        }
                    }.scrollDismissesKeyboard(.interactively)
                        .onChange(of: studio.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
                if !studio.metrics.isEmpty { Text(studio.metrics).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8) }
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Message your local model", text: $studio.draft, axis: .vertical)
                        .lineLimit(1...5).padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityIdentifier("prompt").focused($promptFocused)
                    if studio.generating {
                        Button { studio.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 34)) }.accessibilityLabel("Stop generation")
                    } else {
                        Button { promptFocused = false; studio.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                            .disabled(studio.active == nil || studio.busy || studio.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send message")
                    }
                }.padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .navigationTitle("Chat").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New conversation", systemImage: "square.and.pencil") { studio.clear() }.disabled(studio.busy)
                    Button("Unload model", systemImage: "eject") { studio.unload() }.disabled(studio.active == nil)
                    Picker("Response limit", selection: $studio.outputLimit) { Text("128 tokens").tag(128); Text("256 tokens").tag(256); Text("512 tokens").tag(512) }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Conversation options")
            }
        }
        .onChange(of: studio.chatInput) { _, input in
            promptFocused = false
            if input == .image, studio.active != nil || studio.busy { studio.unload(reason: "Load a text model to continue") }
        }
    }
}
