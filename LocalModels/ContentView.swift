import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var studio: Studio
    @Bindable var native: NativeTools
    @State private var showImport = false
    @State private var photo: PhotosPickerItem?
    @State private var deleteModel: LocalModel?
    @FocusState private var promptFocused: Bool
    var body: some View {
        TabView(selection: $studio.tab) {
            NavigationStack { chat }.tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(0)
            NavigationStack { library }.tabItem { Label("Models", systemImage: "square.stack.3d.up") }.tag(1)
            NavigationStack { tools }.tabItem { Label("Tools", systemImage: "waveform.and.magnifyingglass") }.tag(2)
        }
        .alert("Something needs attention", isPresented: Binding(get: { studio.error != nil || native.error != nil }, set: { if !$0 { studio.error = nil; native.error = nil } })) {
            Button("OK") { studio.error = nil; native.error = nil }
        } message: { Text(studio.error ?? native.error ?? "") }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data]) { result in
            switch result { case .success(let url): studio.importModel(url); case .failure(let error): studio.error = error.localizedDescription }
        }
        .confirmationDialog("Delete this model from your iPhone?", isPresented: Binding(get: { deleteModel != nil }, set: { if !$0 { deleteModel = nil } }), titleVisibility: .visible) {
            if let model = deleteModel { Button("Delete \(model.name)", role: .destructive) { studio.remove(model); deleteModel = nil } }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(studio.active == nil ? Color.secondary : .teal).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 3) {
                    Text(studio.active?.name ?? "Local inference").font(.subheadline.weight(.semibold))
                    Text(studio.status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if studio.busy { ProgressView().controlSize(.small) }
                Image(systemName: "iphone").foregroundStyle(.secondary)
            }.padding().background(.bar)
            ScrollViewReader { proxy in
                ScrollView {
                    if studio.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            Image(systemName: "cpu").font(.system(size: 38, weight: .light)).foregroundStyle(.teal)
                            Text("Small models.\nRight here.").font(.largeTitle.bold())
                            Text("Run AI on your iPhone. Your prompts stay on this device.")
                                .font(.body).foregroundStyle(.secondary)
                            if studio.active == nil {
                                Button { studio.tab = 1 } label: { Label("Choose a model", systemImage: "arrow.down.circle") }
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Button("Try a short summary") { studio.draft = "Summarize this in one sentence: "; }
                                    .buttonStyle(.bordered)
                            }
                            Text("2,048-token context · One model at a time").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(28).padding(.top, 24)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(studio.messages) { message in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(message.role == "user" ? "YOU" : "ON DEVICE")
                                        .font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(message.role == "user" ? Color.secondary : .teal)
                                    Text(message.text.isEmpty ? "Thinking…" : message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    if message.role == "assistant", !message.text.isEmpty, !studio.generating {
                                        HStack {
                                            Button { UIPasteboard.general.string = message.text } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copy response")
                                            Button { native.stopRecording(); studio.speak(message.text) } label: { Image(systemName: "speaker.wave.2") }.accessibilityLabel("Read response aloud")
                                            ShareLink(item: message.text) { Image(systemName: "square.and.arrow.up") }
                                        }.font(.caption).foregroundStyle(.secondary).buttonStyle(.borderless)
                                    }
                                }.id(message.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(20)
                    }
                }
                .onChange(of: studio.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            if !studio.metrics.isEmpty { Text(studio.metrics).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8) }
            HStack(alignment: .bottom, spacing: 12) {
                TextField(studio.active == nil ? "Load a model to begin" : "Message your local model", text: $studio.draft, axis: .vertical)
                    .lineLimit(1...5).padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .disabled(studio.active == nil)
                    .accessibilityIdentifier("prompt")
                    .focused($promptFocused)
                if studio.generating {
                    Button { studio.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 34)) }.accessibilityLabel("Stop generation")
                } else {
                    Button { promptFocused = false; native.stopRecording(); studio.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                        .disabled(studio.active == nil || studio.busy || studio.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send message")
                }
            }.padding(.horizontal).padding(.vertical, 10).background(.bar)
        }
        .navigationTitle("Local Models").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Menu {
                Button("New conversation", systemImage: "square.and.pencil") { studio.clear() }.disabled(studio.busy)
                Button("Unload model", systemImage: "eject") { studio.unload() }.disabled(studio.active == nil)
                Button("Stop reading", systemImage: "speaker.slash") { studio.stopSpeaking() }
                Picker("Response limit", selection: $studio.outputLimit) { Text("128 tokens").tag(128); Text("256 tokens").tag(256); Text("512 tokens").tag(512) }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Conversation options") }
        }
    }

    private var library: some View {
        List {
            Section {
                Label("Built for a smaller memory footprint", systemImage: "leaf")
                Text("Download a model once, then use it offline. Downloads use your internet connection; weights are stored separately from the app.").font(.subheadline).foregroundStyle(.secondary)
            }
            if !studio.models.isEmpty {
                Section("On this iPhone") {
                    ForEach(studio.models) { model in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(model.name).font(.headline); Spacer(); if studio.active == model { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal) } }
                            Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                if studio.active == model { Button("Unload") { studio.unload() } }
                                else { Button("Load model") { native.stopRecording(); studio.load(model) }.disabled(studio.busy) }
                                Spacer()
                                Button(role: .destructive) { deleteModel = model } label: { Image(systemName: "trash") }.disabled(studio.busy || studio.active == model).accessibilityLabel("Delete \(model.name)")
                            }.buttonStyle(.borderless)
                        }.padding(.vertical, 6)
                    }
                }
            }
            Section("Available models") {
                ForEach(CatalogModel.all) { model in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.name).font(.headline)
                        Text(model.detail).font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)).font(.caption.monospacedDigit())
                            Spacer()
                            Link(model.license, destination: model.page).font(.caption)
                        }
                        if studio.models.contains(where: { $0.id == model.filename }) {
                            Label("Downloaded", systemImage: "checkmark").font(.subheadline).foregroundStyle(.teal)
                        } else if studio.downloadID == model.id {
                            ProgressView(value: studio.downloadProgress)
                            HStack {
                                Text(studio.downloadProgress >= 1 ? "Verifying file…" : "\(Int(studio.downloadProgress * 100))% downloaded").font(.caption)
                                Spacer()
                                Button("Cancel", role: .cancel) { studio.cancelDownload() }
                            }
                        } else {
                            Button { studio.fetch(model) } label: { Label("Download", systemImage: "arrow.down.circle") }.disabled(studio.downloadID != nil)
                        }
                    }.padding(.vertical, 8).buttonStyle(.borderless)
                }
            }
            Section {
                Button { showImport = true } label: { Label(studio.importing ? "Importing…" : "Import GGUF from Files", systemImage: "folder") }.disabled(studio.importing)
            } footer: { Text("Use instruction-tuned text models under 1.1 GB. Larger models and image projectors are not enabled. File size is not a guarantee of runtime memory use.") }
        }.navigationTitle("Models")
    }

    private var tools: some View {
        List {
            Section {
                Text("Use the iPhone’s built-in tools without downloading extra AI models.").foregroundStyle(.secondary)
            }
            Section("Read text from an image") {
                PhotosPicker(selection: $photo, matching: .images) { Label("Choose an image", systemImage: "text.viewfinder") }.disabled(native.recognizing)
                if native.recognizing { ProgressView("Reading text…") }
                if !native.scannedText.isEmpty {
                    Text(native.scannedText).textSelection(.enabled)
                    Button("Use text in chat") { studio.draft = "Summarize this text:\n\n" + native.scannedText; studio.tab = 0 }
                    ShareLink("Share extracted text", item: native.scannedText)
                }
            }
            Section {
                Button {
                    if native.recording { native.stopRecording() }
                    else { studio.stopSpeaking(); Task { await native.startRecording() } }
                } label: { Label(native.recording ? "Stop recording" : "Start dictation", systemImage: native.recording ? "stop.circle" : "mic") }
                    .disabled(studio.busy)
                if !native.transcript.isEmpty {
                    Text(native.transcript).textSelection(.enabled)
                    Button("Use transcript in chat") { native.stopRecording(); studio.draft = native.transcript; studio.tab = 0 }
                }
            } header: { Text("Offline dictation") } footer: { Text("Uses on-device speech recognition only. Availability depends on your language and installed speech resources.") }
            Section("Runtime") {
                LabeledContent("Text inference", value: "llama.cpp · Metal")
                LabeledContent("OCR", value: "Apple Vision")
                LabeledContent("Voice output", value: "Apple Speech")
                LabeledContent("Context", value: "2,048 tokens")
                Text("Vision-language models, Whisper, and custom TTS weights require additional runtimes and are not included in this build.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Tools")
        .onChange(of: photo) { _, value in
            guard let value else { return }
            Task {
                do { if let data = try await value.loadTransferable(type: Data.self) { await native.recognize(data) } }
                catch { native.error = error.localizedDescription }
                photo = nil
            }
        }
    }
}
