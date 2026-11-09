import SwiftUI
import PhotosUI
import ImageIO
import AVFoundation

struct OCRWorkspace: View {
    @Bindable var native: NativeTools
    let sendToChat: (String) -> Void
    @State private var photo: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var loadingPhoto = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EngineLabel(name: "Apple Vision", detail: "On device")
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 210)
                        .padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityLabel("Selected document image")
                } else {
                    WorkspaceEmptyState(symbol: "text.viewfinder", title: "From image to text.", detail: "Choose a receipt, screenshot, or document photo. Extract its text here, then copy it or send it to Chat.")
                }
                if native.recognizing || loadingPhoto { ProgressView("Reading text…") }
                if !native.scannedText.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("EXTRACTED TEXT").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
                            Spacer()
                            Button { UIPasteboard.general.string = native.scannedText } label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 44) }.accessibilityLabel("Copy extracted text")
                        }
                        Text(native.scannedText).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        ViewThatFits(in: .horizontal) {
                            HStack { handoff; export }
                            VStack(alignment: .leading) { handoff; export }
                        }.buttonStyle(.bordered)
                    }
                }
            }.padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Choose an image", systemImage: "photo.on.rectangle").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 18))
                .disabled(native.recognizing || loadingPhoto).padding(.horizontal, 24).padding(.vertical, 12).background(.background)
        }
        .navigationTitle("Read a document").navigationBarTitleDisplayMode(.large)
        .onChange(of: photo) { _, value in
            guard let value else { return }
            loadingPhoto = true
            Task {
                defer { loadingPhoto = false; photo = nil }
                do {
                    guard let data = try await value.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                    if let source = CGImageSourceCreateWithData(data as CFData, nil),
                       let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 640] as CFDictionary) {
                        preview = UIImage(cgImage: image)
                    }
                    await native.recognize(data)
                } catch { native.error = error.localizedDescription }
            }
        }
    }
    private var handoff: some View { Button { sendToChat(native.scannedText) } label: { Label("Send to Chat", systemImage: "bubble.left") } }
    private var export: some View { ShareLink(item: native.scannedText) { Label("Export", systemImage: "square.and.arrow.up") } }
}

struct TranscribeWorkspace: View {
    @Bindable var native: NativeTools
    let sendToChat: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EngineLabel(name: "Apple Speech", detail: "On device")
                VStack(spacing: 14) {
                    Image(systemName: "waveform").font(.system(size: 42, weight: .light)).foregroundStyle(.teal)
                        .symbolEffect(.variableColor, isActive: native.recording).accessibilityHidden(true)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = native.recordingStartedAt.map { context.date.timeIntervalSince($0) } ?? native.recordedDuration
                        Text(String(format: "%02d:%02d", Int(max(0, elapsed)) / 60, Int(max(0, elapsed)) % 60))
                            .font(.system(.title, design: .monospaced)).monospacedDigit().accessibilityLabel("Recording duration")
                    }
                    Text(native.recording ? "Listening…" : native.startingRecording ? "Preparing microphone…" : "Ready to listen")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "Current device language").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 24).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                if native.transcript.isEmpty {
                    Text("Capture a thought or dictate a note. Your transcript will appear here as you speak.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("TRANSCRIPT").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
                        Text(native.transcript).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        ViewThatFits(in: .horizontal) {
                            HStack { handoff; export }
                            VStack(alignment: .leading) { handoff; export }
                        }.buttonStyle(.bordered)
                    }
                }
                Text("Offline speech recognition depends on your language and installed speech resources. Audio is never sent to a transcription server.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            WorkspacePrimaryButton(title: native.recording ? "Stop recording" : "Record audio", symbol: native.recording ? "stop.fill" : "mic.fill") {
                if native.recording { native.stopRecording() }
                else { Task { await native.startRecording() } }
            }.disabled(native.startingRecording).padding(.horizontal, 24).padding(.vertical, 12).background(.background)
        }
        .navigationTitle("Transcribe").navigationBarTitleDisplayMode(.large)
    }
    private var handoff: some View { Button { sendToChat(native.transcript) } label: { Label("Send to Chat", systemImage: "bubble.left") } }
    private var export: some View { ShareLink(item: native.transcript) { Label("Export", systemImage: "square.and.arrow.up") } }
}

struct SpeakWorkspace: View {
    @Bindable var speech: SpeechOutput
    @State private var choosingVoice = false
    @State private var voiceSearch = ""
    @FocusState private var textFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EngineLabel(name: "Apple voices", detail: "On device")
                VStack(alignment: .leading, spacing: 12) {
                    Text("TEXT TO READ").font(.caption2.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $speech.text).frame(minHeight: 190).scrollContentBackground(.hidden)
                            .focused($textFocused).accessibilityIdentifier("speech-text").disabled(speech.speaking)
                        if speech.text.isEmpty {
                            Text("Type or paste text, or bring a reply here from Chat.").foregroundStyle(.secondary).padding(.horizontal, 5).padding(.top, 8).allowsHitTesting(false)
                        }
                    }.padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    HStack {
                        PasteButton(payloadType: String.self) { speech.text = $0.joined(separator: "\n") }.disabled(speech.speaking)
                        Spacer()
                        Button("Clear", role: .destructive) { speech.text = "" }.disabled(speech.text.isEmpty || speech.speaking)
                    }.buttonStyle(.borderless)
                }
                VStack(spacing: 16) {
                    Button { choosingVoice = true } label: {
                        HStack { Text("Voice").foregroundStyle(Color.primary); Spacer(); Text(speech.voiceName).lineLimit(2); Image(systemName: "chevron.down").font(.caption) }
                    }.disabled(speech.speaking).accessibilityIdentifier("choose-voice")
                    Divider()
                    HStack {
                        Text("Speed")
                        Spacer()
                        Picker("Speaking rate", selection: $speech.rate) {
                            Text("Slow").tag(Float(0.4)); Text("Normal").tag(Float(0.5)); Text("Fast").tag(Float(0.6))
                        }.pickerStyle(.menu).labelsHidden().disabled(speech.speaking)
                    }
                }
                Text(speech.speaking ? "Reading aloud…" : "Uses a voice installed on your iPhone.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            WorkspacePrimaryButton(title: speech.speaking ? "Stop reading" : "Read aloud", symbol: speech.speaking ? "stop.fill" : "play.fill") {
                textFocused = false
                if speech.speaking { speech.stop() } else { speech.read() }
            }.disabled(speech.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 24).padding(.vertical, 12).background(.background)
        }
        .navigationTitle("Read aloud").navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $choosingVoice) {
            NavigationStack {
                List(speech.voices.filter { voiceSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(voiceSearch) || $0.language.localizedCaseInsensitiveContains(voiceSearch) }, id: \.identifier) { voice in
                    Button {
                        speech.voiceIdentifier = voice.identifier
                        choosingVoice = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(voice.name).foregroundStyle(.primary)
                                Text(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if voice.identifier == speech.voiceIdentifier { Image(systemName: "checkmark").foregroundStyle(.teal) }
                        }
                    }
                }
                .searchable(text: $voiceSearch, prompt: "Name or language")
                .navigationTitle("Choose a voice").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { choosingVoice = false } } }
            }
        }
    }
}
