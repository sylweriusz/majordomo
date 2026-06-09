# Majordomo helper runtimes

Final Majordomo runtime must not depend on user-managed Homebrew packages.

App-owned executable helpers packaged here:

- `Helpers/whisper-cli` — static whisper.cpp build with Metal embedded for file-based transcription; build/update via `scripts/package-whisper-helper.sh`.
- `Helpers/whisper-dictate` — custom whisper.cpp-based stdin helper for live microphone dictation; build/update via `scripts/package-whisper-helper.sh`.

Imported audio normalization is handled by the native macOS audio converter.

`scripts/build-app.sh` copies this directory to:

```text
build/Majordomo.app/Contents/Resources/Helpers/
```

At runtime Majordomo searches, in order:

1. bundled helpers in `Contents/Resources/Helpers`,
2. app-managed helpers in `~/Library/Application Support/Majordomo/Helpers`,
3. explicit environment override `MAJORDOMO_<dependency>_PATH`,
4. development-only Homebrew fallback only when `MAJORDOMO_ENABLE_DEV_RUNTIME_FALLBACK=1`.

Do not require users to install `whisper-cpp`, Rust, Python, or Homebrew for normal operation.

Current runtime split:

- audio-file transcription keeps using `whisper-cli` on normalized audio files,
- live dictation streams 16 kHz mono Float32 PCM directly into `whisper-dictate` over stdin, without a temporary WAV in the normal path.
