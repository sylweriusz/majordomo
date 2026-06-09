# Homebrew cask for Majordomo.
#
# `version` and `sha256` are managed by scripts/release-cask.sh — do not edit by
# hand. This file is the canonical copy; on release it is synced into the public
# `homebrew-majordomo` tap repo (see docs/DISTRIBUTION.md).
cask "majordomo" do
  version "0.1.3"
  sha256 "60dd1bd37ef12ca44ea2fb45267ab343f4af92d021e19ed04dc8248bb40974e8"

  url "https://majordomo.pomr.uk/Majordomo-macOS.zip"
  name "Majordomo"
  desc "Local menu-bar Whisper speech-to-text"
  homepage "https://majordomo.pomr.uk"

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Majordomo.app"

  # Majordomo is ad-hoc signed, not notarized by Apple. Homebrew quarantines
  # installed apps by default, which trips Gatekeeper's "could not verify… is
  # free of malware" block. Strip the quarantine flag so the app opens normally.
  postflight do
    system_command "/usr/bin/xattr",
                   args:         ["-dr", "com.apple.quarantine", "#{appdir}/Majordomo.app"],
                   must_succeed: false
  end

  # The cask must not touch launchd. Launch-at-login is owned entirely by the app
  # (a user LaunchAgent it loads/unloads itself, no privileges). Homebrew's
  # `launchctl:` and `delete:` uninstall directives both escalate to `sudo` —
  # `launchctl:` probes the system domain, `delete:` runs `sudo rm` — so either
  # would prompt for a password on every upgrade. Just quit the app; its login
  # plist (in ~/Library, user-owned) is the app's concern and is cleared by `--zap`.
  uninstall quit: "pl.wild-matrix.majordomo"

  zap trash: [
    "~/Library/Application Support/pl.wild-matrix.majordomo",
    "~/Library/Preferences/pl.wild-matrix.majordomo.plist",
    "~/Library/LaunchAgents/pl.wild-matrix.majordomo.plist",
  ]

  caveats <<~EOS
    Majordomo needs Microphone and Accessibility permissions
    (System Settings → Privacy & Security) to record and insert text.

    Whisper models (~0.8–3 GB) download on first use into ~/.models and are
    NOT removed by `brew uninstall --zap`. Delete that folder manually if you
    want to reclaim the space.
  EOS
end
