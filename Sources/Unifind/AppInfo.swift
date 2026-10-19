import AppKit

/// The app's name, version and links, read from the bundle (with fallbacks for `swift run`).
enum AppInfo {
	static let name = "Unifind"
	static let tagline = "Find any Unicode character by name, shape or idea."

	static var version: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
	}

	static var build: String? {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
	}

	/// "1.0.1 (3)", or just "dev" outside a bundle.
	static var fullVersion: String {
		guard let build, version != "dev" else { return version }
		return "\(version) (\(build))"
	}

	static var copyright: String {
		Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 zms"
	}

	static let repository = URL(string: "https://github.com/zmscode/Unifind")!
	static let releases = repository.appending(path: "releases")
	static let newIssue = repository.appending(path: "issues/new")
	static let brewCommand = "brew install --cask zmscode/unifind/unifind"

	@MainActor static var icon: NSImage { NSApp.applicationIconImage }
}

/// Which Settings tab is showing, so the sidebar can open Settings straight to About.
enum SettingsTab: String {
	case appearance, about
	static let key = "settingsTab"
}
