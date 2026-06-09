# Majordomo

A local, menu-bar–driven macOS app. First module: local speech-to-text via selectable Whisper profiles.

**Website:** [majordomo.pomr.uk](https://majordomo.pomr.uk)

## Goal of the first module: Whisper STT

Target flow:

1. The user presses a configured key / shortcut.
2. Majordomo starts recording the microphone locally.
3. A second press stops the recording.
4. The audio is transcribed locally with the Whisper `large-v3-turbo` model.
5. The result is pasted into the currently focused text field — Terminal, an editor, a browser, etc.

## Product principles

- Local-first: audio and transcription stay on the Mac.
- No telemetry.
- No transcript history and no logging of transcript contents.
- The menu bar is the main point of control.
- The hotkey is the primary mode of operation.
- Small, testable modules instead of one large app.

## Initial MVP scope

- macOS app with a menu-bar icon.
- Configurable global hotkey.
- Start/stop recording with a single shortcut.
- A quick double `Escape` during active dictation cancels recording/transcription, hides the overlay, and discards the temporary WAV without inserting text.
- Local transcription with a selected Whisper profile: Large v3 Turbo 8-bit, Large v3 Turbo, or Large v3.
- Transcription of an existing audio file from a separate panel: selection limited to audio types natively supported by macOS (WAV/MP3/M4A and others), independent model and language choice, manual transcription start after picking a file, local normalization to mono PCM WAV 16 kHz via the native macOS audio converter, and the result in an editable text field with copy and save-to-`.txt`.
- Inserting text into the current focus.
- Minimal status: idle / recording / transcribing / error.
- During dictation, a black overlay near the notch/island with a live mic-amplitude wave; during transcription the same overlay shows an animated progress wave. The overlay has selectable, purely graphical styles plus separate color palettes — no text inside the effect itself.
- A short, gentle product sound confirms dictation start/stop; the sound is chosen independently from the Dictation Sound menu as a classically inspired tone profile.

## Initial decisions

- App runtime: Swift/AppKit menu-bar app.
- STT engine: `whisper.cpp` with Metal.
- Models: Whisper Large v3 Turbo 8-bit, Large v3 Turbo, and Large v3.
- Models are downloaded by the app into `~/.models` when missing.
- The final app must not depend on a user-managed Homebrew CLI; the runtime is bundled / app-managed. Homebrew remains only a developer/spike fallback.
- The hotkey acts as a toggle: start recording, stop recording, transcribe, auto-insert text.
- A quick double `Escape` is the cancel path for active dictation: it stops recording, discards the temporary WAV, hides the overlay, and does not run/insert the transcription.
- Insertion is VoiceInk-like: the user does not press Cmd+V manually; Majordomo inserts the text into the current focus once recording ends.
- The app icon comes from `majordomo.png`.

## Local build

```bash
swift build
swift run MajordomoCoreTestRunner
swift run Majordomo -- --export-sound-previews build/sound-previews
scripts/build-app.sh stable
scripts/build-app.sh test
open build/Majordomo.app
open "build/Majordomo Test.app"
```

> Fresh clone: run `scripts/package-whisper-helper.sh` first to build the bundled helpers (`Helpers/whisper-cli`, `whisper-dictate`) before `scripts/build-app.sh`.

The app runs as a menu-bar app and uses `majordomo.png` as its icon with a **colored state dot** (red = recording, orange = downloading, blue = transcribing, yellow = error). **The menu is thin** — a launcher: `Start/Stop Dictation` with the current hotkey in its title, `Cancel Dictation` (enabled only while dictating), a status row, `Copy Last Transcript to Clipboard` (disabled until there is an ephemeral transcript), `Transcribe Audio File…`, `Settings…`, `About Majordomo…` (with bundled-helper licenses), and `Quit`. While dictating, if the indicator is enabled, it shows the black waveform overlay plus — for the first few dictations — a transient "Esc Esc to cancel" hint below the notch.

**All configuration lives in the `Settings` window** (General / Dictation / Appearance sections), not in the menu: the Whisper model (with size · speed · accuracy and a download-progress bar), App Language, Spoken Language, hotkey (`Custom Hotkey…` captures a combination — a modifier or function key is required, Escape cancels), Launch at Login, Dictation Sound, and Show Indicator + style + palette + placement **with a live preview**. On first launch an **onboarding window** appears (the hotkey name, the press-to-start/stop loop, the double-Escape gesture, Microphone and Accessibility priming); if the detected hotkey is the bare `Fn` key, onboarding suggests switching to `⌥Space`.

The indicator has twelve purely graphical variants: Signal Glass, Liquid Neon, Aurora Plasma, Nebula Engine, Temporal Rift, Crystal Lens, Cosmic Storm, Neural Network, Plasma Vortex, UFO Reactor, Xeno Lattice, and the candy-themed Unicorn Sparklepop; a separate color palette has twelve variants: Oceanic, Ultraviolet, Solar Flare, Rose Gold, Arctic Ghost, Acid Matrix, Void Gold, Deep Space, Toxic Mist, Blood Moon, Neon Pulse, and Cotton Candy Kisses. Placement allows Notch Capsule, Dock Wings, or Auto. Dictation Sound selects an independent start/stop profile: Majordomo Chime, Starship Console, Rotary Exchange, Classic Desktop, Aqua Glass, Terminal Tick, Cassette Relay, Arcade Blip, UFO Scanner, or Crystal Bell. A quick double `Escape` cancels active dictation via a **passive `NSEvent` monitor** (Escape still passes through to the target app, and the gesture remains global): it closes the overlay, stops the recorder, and invalidates the session. The stable channel's default global hotkey is `⌥ Space` (a chord registered via Carbon, with no Accessibility dependency; `Fn` is available as an explicit choice). The indicator state, style, selected STT backend, and hotkey are persisted in UserDefaults (via the central `SettingsStore`). `Launch at Login` toggles a per-app LaunchAgent for the current bundle ID.

The `Whisper Model` picker selects one of three profiles: Large v3 Turbo 8-bit (`~/.models/ggml-large-v3-turbo-q8_0.bin`), Large v3 Turbo (`~/.models/ggml-large-v3-turbo.bin`), and Large v3 (`~/.models/ggml-large-v3.bin`). Each item shows an approximate MB/GB size, a semantic speed, and a percentage accuracy. Selecting a profile triggers an on-demand model download if it's missing from `~/.models`; the Settings model row also offers an in-place cancel during download and a Delete Model action once present. The `Transcribe Audio File…` panel has its own selection of the same profiles and a language from the same list as the Settings `Spoken Language`; the supported-format claim is trimmed to actually-supported formats, mainly WAV, MP3, M4A, AIFF, CAF, and MP4 audio, and it also downloads a missing model on demand. The app bundle contains the app-owned helpers `whisper-cli` and `whisper-dictate` (a static/custom whisper.cpp build with Metal embedded), so no menu runtime is needed. Live dictation streams 16 kHz mono Float32 PCM directly to Whisper over stdin, with no temporary WAV in the normal flow; imported audio is still normalized locally via the native macOS audio converter.

Platform target:

- practical minimum: macOS 15;
- public target: Apple Silicon only.

App channels:

- stable: `build/Majordomo.app`, bundle ID `pl.wild-matrix.majordomo`, default hotkey `⌥ Space`;
- test: `build/Majordomo Test.app`, bundle ID `pl.wild-matrix.majordomo.test`, default hotkey `⌃⌥ Space`.

Installing the stable build for daily dictation:

```bash
scripts/install-stable.sh
```

By default it installs to `~/Applications/Majordomo.app` and sets up a login LaunchAgent. `INSTALL_DIR=/Applications scripts/install-stable.sh` installs to `/Applications` if you want and have permission. After that, the behavior can be changed from the menu via `Launch at Login`.

### Install via Homebrew

Public distribution goes through a Homebrew cask (the binary is hosted on Cloudflare, the tap lives in the `sylweriusz/homebrew-majordomo` repo on GitHub). The cask strips the quarantine attribute, so the ad-hoc–signed app launches without the Gatekeeper "damaged" screen — no paid Apple Developer account needed.

The three-part cask name **auto-taps**, so one command is enough — no separate `brew tap` step:

```bash
brew install --cask sylweriusz/majordomo/majordomo
```

Equivalently, the explicit two-step form:

```bash
brew tap sylweriusz/majordomo
brew install --cask majordomo
```

Uninstall with `brew uninstall --cask majordomo` (add `--zap` to also remove Application Support and preferences). Releasing and the one-time tap setup are described in [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md); in short: `scripts/release-cask.sh` builds the zip, computes the `sha256`, and updates `Casks/majordomo.rb`.

A manual test of the hotkey + Microphone permission + model download + real transcription still requires going through it at the user's screen.

## License

MIT — see [`LICENSE`](LICENSE). Bundled third-party components (whisper.cpp / ggml) are licensed separately; see `Sources/Majordomo/Resources/ThirdPartyNotices.txt`.
