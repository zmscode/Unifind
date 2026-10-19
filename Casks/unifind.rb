cask "unifind" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/zmscode/Unifind/releases/download/v#{version}/Unifind-#{version}.zip"
  name "Unifind"
  desc "Unicode character finder with fuzzy and on-device AI search"
  homepage "https://github.com/zmscode/Unifind"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Unifind.app"

  zap trash: [
    "~/Library/Caches/com.zms.Unifind",
    "~/Library/Preferences/com.zms.Unifind.plist",
    "~/Library/Saved Application State/com.zms.Unifind.savedState",
  ]

  # Until releases are notarized (see RELEASING.md), macOS needs approving
  # the app once. Remove this caveat with the first notarized release.
  caveats <<~EOS
    Unifind isn't notarized yet, so macOS may refuse to open it at first.
    Approve it once in System Settings > Privacy & Security > Open Anyway,
    or run:
      xattr -dr com.apple.quarantine #{appdir}/Unifind.app
  EOS
end
