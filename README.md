# Local Models

A small native SwiftUI inference app for iPhone 13 and newer. Model weights live outside the app bundle. No account, backend, telemetry, WebView, or cloud inference service.

## Open and run

1. Open `LocalModels.xcodeproj` in Xcode 16 or newer (validated with Xcode 27.2).
2. Select the **LocalModels** scheme and a **physical iPhone** running iOS 17 or newer.
3. Select your development team under Signing & Capabilities. The checked-in configuration uses the original developer's personal team; change `DEVELOPMENT_TEAM` and the bundle identifier in `Config/App.xcconfig` for your account. UI test signing is in `Config/Tests.xcconfig`.
4. Build and run. Open **Model library** using the stack icon at the top of any workspace, then download Gemma or Qwen, or import a compatible instruction-tuned `.gguf` from Files. Tap **Load model**, then chat. You can also tap the model name in Chat to switch between downloaded text models.

The pinned upstream binary does **not include an iOS Simulator slice**. Use a physical iPhone for the app, and `swift test` on macOS for the shared inference engine. Xcode downloads the pinned runtime the first time packages are resolved; model weights are never bundled or checked into Git.

## Task island

The floating system tab bar has four destinations: **Chat**, **OCR**, **Transcribe**, and **Speak**. Model downloads and storage live in a shared library sheet, available from every tab.

- **Chat** has Text and Image modes. Text runs the installed GGUF models; Image is explicitly unavailable until a vision runtime is integrated and links to OCR for reading text from photos.
- **OCR** provides photo selection, document preview, extracted text, copy/export, and Send to Chat.
- **Transcribe** provides on-device dictation, recording duration, a live transcript, export, and Send to Chat.
- **Speak** provides an editable text area, installed voice selection, speaking rate, and read/stop controls. Chat responses can be opened here for reading.

Drafts and results survive tab switches. Leaving Chat or selecting Image releases the active text model to keep memory available for native tasks. Returning to text chat requires loading a model again; reloading the same model preserves the conversation, while choosing a different model starts a new one. Leaving Transcribe stops recording, including pending permission requests; leaving Speak stops playback.

## Included

| Capability | Implementation |
| --- | --- |
| Text generation | llama.cpp b10549, via `mattt/llama.swift` 2.10549.0; Metal GPU acceleration and memory-mapped weights |
| Model library | Pinned Hugging Face downloads, streaming progress, cancellation, SHA-256 verification, GGUF import, deletion |
| Chat | Token streaming, stop, new conversation, copy/share/read aloud, token and elapsed-time statistics |
| OCR | Apple Vision on a downsampled photo; extracted text can be sent to chat |
| Speech input | `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`; explicitly fails if offline recognition is unavailable |
| Speech output | `AVSpeechSynthesizer`, using installed system voices |

### Catalog

| Model | File size | Source | License |
| --- | --- | --- | --- |
| Gemma 3 270M IT, Q8_0 | 291,545,600 bytes | [ggml-org](https://huggingface.co/ggml-org/gemma-3-270m-it-GGUF) | [Gemma terms](https://ai.google.dev/gemma/terms) |
| Qwen 3.5 0.8B, Q4_K_M | 541,903,360 bytes | [axteam](https://huggingface.co/axteam/Qwen3.5-0.8B-GGUF) | Apache 2.0 |

Both downloads are pinned to repository revisions and LFS SHA-256 digests in `ModelStore.swift`. Catalog sizes are **disk sizes, not peak RAM estimates**. Imported files receive size and GGUF-header checks but have no publisher checksum. The runtime performs the remaining model-format and architecture validation. Models have their own licenses; download links expose their model cards before installation.

Other compatible small GGUF instruction models can be imported, including appropriate Gemma and Llama variants. Compatibility is limited by the pinned llama.cpp architecture and chat-template support. This is not a promise that every GGUF file works.

## Memory policy

- Exactly one model session at a time; an actor serializes loading, decoding, and freeing native handles.
- Fixed 2,048-token context, 32-token prefill batches, four CPU threads, 128–512 generated tokens.
- Whole old chat exchanges are omitted when the context fills. An oversized newest prompt produces an error.
- KV memory is cleared between requests; models are released on backgrounding, memory warnings, or explicit unload.
- GGUF files larger than 1.1 GB are rejected. File size alone cannot predict peak memory or prevent all iOS memory-pressure terminations.
- Large image input is decoded as a thumbnail with a 2,048-pixel longest side for OCR.
- Model weights are excluded from device backups. Chat stays in memory and disappears when the app terminates.

The app deliberately does not depend on `com.apple.developer.kernel.increased-memory-limit`. Apple makes extra memory available only on some devices and does not guarantee a specific iPhone 13 allowance. A personal-team build works without it. See [Apple's entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit).

## Scope

This first version supports **text GGUF inference and native OCR/speech**. It does not implement image embeddings or vision projectors, FastVLM, SmolVLM, WhisperKit, Kokoro, Piper, MLX, or Foundation Models. Qwen's catalog entry is text-only. These need separate, measured adapters; the UI does not claim they already work. Native OCR is not visual question answering. Speech support varies by language and installed resources, and OS frameworks still consume memory.

Response speed depends on model, prompt length, temperature, and device state. The displayed tok/s includes prefill and is not a decode-only benchmark. Greedy sampling is used for reproducibility. Small models can be inaccurate and are best suited to short prompts.

## Validation

```sh
swift test
LOCAL_MODEL_TEST_PATH=/absolute/path/to/model.gguf swift test
xcodebuild -project LocalModels.xcodeproj -scheme LocalModels \
  -destination 'id=YOUR_DEVICE_UDID' -allowProvisioningUpdates test
```

Unit tests cover malformed/oversized files and unloaded-engine behavior. Setting `LOCAL_MODEL_TEST_PATH` additionally runs real inference, prompt overflow, cancellation, unload, and reload. Without it, the real-model test is marked skipped; no model is downloaded by the test suite. The device UI test requires Gemma already present in `Documents/Models` and exercises loading, chat, and unloading. Close other memory-intensive apps and picture-in-picture overlays when running device UI tests.

For automated developer smoke checks, Debug builds accept `--smoke-test` and optionally `--smoke-model=FILENAME.gguf`, and write the real model response to `Documents/SmokeTest.json`. That diagnostic route is absent from Release builds.

## Code map

- `Sources/LocalInference/LlamaEngine.swift`: native runtime and resource lifetime.
- `LocalModels/Studio.swift`: UI state, inference orchestration, downloads.
- `LocalModels/ModelStore.swift`: catalog, file validation and model installation.
- `LocalModels/NativeTools.swift`: OCR and strictly on-device dictation.
- `LocalModels/ContentView.swift`: Task island navigation, shared library access, and Chat.
- `LocalModels/ModelLibrary.swift`: downloaded model picker and download/import management.
- `LocalModels/NativeWorkspaces.swift`: dedicated OCR, Transcribe, and Speak screens.
- `LocalModels/SpeechOutput.swift`: installed voices, speech playback state, and audio-session cleanup.

The app's only external Swift package is [llama.swift](https://github.com/mattt/llama.swift), an MIT-licensed wrapper for [llama.cpp](https://github.com/ggml-org/llama.cpp). Its precompiled XCFramework is verified by Swift Package Manager. `Package.resolved` pins the dependency commit.
