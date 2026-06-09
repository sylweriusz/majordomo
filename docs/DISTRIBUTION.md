# Distributing Majordomo (Homebrew cask + Cloudflare)

Majordomo is intentionally not notarized by Apple. Distribution goes through a
**Homebrew cask**, which on install **strips the quarantine attribute**, so the
ad-hoc–signed app launches without the Gatekeeper screen — no paid Apple
Developer account needed.

## Architecture

Two pieces with different requirements:

| Piece | What it is | Where |
|---|---|---|
| **Binary** | `Majordomo-macOS.zip` (the zipped `.app`) | **Cloudflare Pages** — `https://majordomo.pomr.uk/Majordomo-macOS.zip` |
| **Tap** | a repo holding the cask file (`Casks/majordomo.rb`) | **public GitHub repo** `homebrew-majordomo` (needs a git host) |

The cask in the tap points its `url` at the binary on Cloudflare. GitHub holds
only a ~40-line recipe; the heavy file is served from the site.

> Note: the binary URL is **unversioned** (`Majordomo-macOS.zip`). Each release
> overwrites the same file, and the cask gets a new `version` + `sha256`. This is
> a deliberate simplification to match the existing download button on the site.
> If you ever want to keep multiple versions side by side, switch to
> `Majordomo-#{version}.zip`.

## How to cut a release

```bash
scripts/release-cask.sh
```

The script:
1. builds the stable `.app` (`build-app.sh stable`, ad-hoc signing with the correct bundle id),
2. zips it with `ditto` into `web_page/Majordomo-macOS.zip`,
3. computes the `sha256`,
4. writes the fresh `version` + `sha256` into `Casks/majordomo.rb`.

Then, manually:
1. **Deploy `web_page/` to Cloudflare Pages** — publishes the new zip (and updates
   the site's "Download" button, which serves the same file).
2. **Push `Casks/majordomo.rb` to the tap** (the script prints the command).

## One-time tap setup (GitHub)

The tap is a separate, public repo named **exactly** `homebrew-majordomo`:

```bash
# on GitHub: create an empty public repo  sylweriusz/homebrew-majordomo
git clone https://github.com/sylweriusz/homebrew-majordomo
mkdir -p homebrew-majordomo/Casks
cp Casks/majordomo.rb homebrew-majordomo/Casks/
cd homebrew-majordomo
git add . && git commit -m "majordomo cask" && git push
```

`Casks/majordomo.rb` in that repo is the only required file (a short `README.md`
is nice to have).

## Installing as an end user

```bash
brew tap sylweriusz/majordomo
brew install --cask majordomo
```

or as a one-liner:

```bash
brew install --cask sylweriusz/majordomo/majordomo
```

After installation the app asks for **Microphone** and **Accessibility**
(System Settings → Privacy & Security).

Uninstalling:

```bash
brew uninstall --cask majordomo        # removes the app + LaunchAgent
brew uninstall --zap --cask majordomo  # also: Application Support, preferences
```

The Whisper models in `~/.models` (~0.8–3 GB) are **not** removed automatically —
delete that folder manually if you want to reclaim the space (or use the in-app
Delete Model button in Settings).

## Why no installer / no notarization

- Notarization requires an Apple Developer account ($99/yr) — not worth it for a
  free app. The Developer ID signing infrastructure is ready in `build-app.sh`
  (`MAJORDOMO_SIGN_IDENTITY`) should that ever change.
- The Homebrew cask strips quarantine, so an app not notarized by Apple still
  launches cleanly. Apple Silicon requires at least an ad-hoc signature — which
  we already produce.
