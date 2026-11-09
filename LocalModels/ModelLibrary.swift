import SwiftUI
import UniformTypeIdentifiers

struct ModelLibrary: View {
    @Bindable var studio: Studio
    let pickerOnly: Bool
    let select: (LocalModel) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showImport = false
    @State private var deleteModel: LocalModel?
    @State private var showCatalog = false

    private var fullLibrary: Bool { !pickerOnly || showCatalog }
    var body: some View {
        NavigationStack {
            List {
                if studio.models.isEmpty {
                    Section { Text("Download or import a text model to start chatting.").foregroundStyle(.secondary) }
                } else {
                    Section("On this iPhone") {
                        ForEach(studio.models) { model in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(model.name).font(.headline); Spacer(); if studio.active == model { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal) } }
                                Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    if studio.active == model { Button("Unload") { studio.unload() }.disabled(studio.busy) }
                                    else { Button("Load model") { select(model) }.disabled(studio.busy) }
                                    Spacer()
                                    if fullLibrary {
                                        Button(role: .destructive) { deleteModel = model } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 36) }
                                            .disabled(studio.busy || studio.active == model).accessibilityLabel("Delete \(model.name)")
                                    }
                                }.buttonStyle(.borderless)
                            }.padding(.vertical, 6)
                        }
                    }
                }
                if fullLibrary || studio.models.isEmpty {
                    Section("Download a text model") {
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
                    } footer: { Text("Downloads use your internet connection. Model weights stay separate from the app. Import instruction-tuned text models under 1.1 GB; runtime memory use varies by model.") }
                    Section("Built into your iPhone") {
                        LabeledContent("OCR", value: "Apple Vision")
                        LabeledContent("Transcribe", value: "Apple Speech")
                        LabeledContent("Speak", value: "Apple voices")
                        Text("Offline dictation depends on your language and installed speech resources. Vision-language models and additional speech runtimes are not included yet.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section { Button("Manage downloads and storage") { showCatalog = true } }
                }
            }
            .navigationTitle(fullLibrary ? "Model library" : "Chat model").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("close-model-library") } }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data]) { result in
                switch result { case .success(let url): studio.importModel(url); case .failure(let error): studio.error = error.localizedDescription }
            }
            .confirmationDialog("Delete this model from your iPhone?", isPresented: Binding(get: { deleteModel != nil }, set: { if !$0 { deleteModel = nil } }), titleVisibility: .visible) {
                if let model = deleteModel { Button("Delete \(model.name)", role: .destructive) { studio.remove(model); deleteModel = nil } }
            }
            .alert("Model library", isPresented: Binding(get: { studio.error != nil }, set: { if !$0 { studio.error = nil } })) {
                Button("OK") { studio.error = nil }
            } message: { Text(studio.error ?? "") }
        }
    }
}
