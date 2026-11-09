# Device validation — November 8, 2026

Validated with Xcode 27.2 on a physical iPhone 13 running iOS 27.2.

- Signed Debug and optimized Release builds succeeded.
- Gemma 3 270M Q8_0 and Qwen 3.5 0.8B Q4_K_M passed the shared engine tests on macOS: real inference, prompt overflow, cancellation, unload, and reload. File-validation and unloaded-engine tests also passed.
- The physical-device UI test passed: load Gemma, type and send a prompt, verify the answer includes Paris, and explicitly unload the model. Result bundle: `TestResults/DeviceLowMemory.xcresult` (local, Git-ignored).
- A separate physical-device Qwen smoke test generated “Paris is the capital of France.” The raw output included an empty `<think>` block; chat presentation removes empty blocks.
- Qwen's short smoke prompt used 20 input tokens and produced 11 raw output tokens in 1.016 seconds. An earlier Gemma smoke prompt used 21 input tokens and produced 2 tokens in 0.749 seconds. These are functional checks, **not sustained throughput benchmarks**; loading time is excluded and the prompts differ.
- The optimized app bundle was approximately 7.8 MB excluding the separately stored 291.5 MB and 541.9 MB model files.
- After reducing prompt batches from 128 to 32, native runtime logs reported compute buffers of approximately 32.08 MiB for Gemma and 30.56 MiB for Qwen. These are compute buffers only, **not total resident memory**.

Earlier device UI runs encountered an overlapping picture-in-picture video and memory/background interruptions. The app released its model in response. The final full UI run passed after the overlay was closed and the lower-memory configuration was applied.

OCR, microphone permissions, offline dictation availability, text-to-speech, and downloads/imports through the UI have compiled successfully but have not received end-to-end device tests. The catalog download URLs, pinned file sizes, and SHA-256 hashes were verified on the Mac. Both model files were transferred to the iPhone and used for real inference.

No claim is made about all-day stability, maximum safe context across arbitrary imported models, or compatibility with every GGUF architecture. VLMs and additional speech-model runtimes are outside this build's scope.

## Task island update

The app now uses four native destinations: Chat, OCR, Transcribe, and Speak, with a shared model library available from every screen. No inference dependencies or model weights were added for the navigation update. The signed Release build is approximately 8.4 MB excluding model files.

Both physical-iPhone UI tests passed in the final run (`TestResults/TaskIslandVerified.xcresult`, Git-ignored):

- All four destinations, Text/Image mode selection, the explicit unavailable state for image chat, the Image-to-OCR shortcut, opening/dismissing the shared library from OCR, and installed voice selection.
- Loading a downloaded GGUF model, real inference returning Paris, transferring that response into Speak, releasing the model when leaving Chat, and preserving the conversation when reloading the same model.

Screenshots: [Chat](task-island-chat.png) · [OCR](task-island-ocr.png).

The microphone recording, OCR photo selection/recognition, and audible speech playback paths were not exercised by these UI tests. Recording permissions and speech-language availability remain device-dependent. The earlier core inference tests still apply; the native inference engine was not changed in this update.
