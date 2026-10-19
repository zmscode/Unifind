import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The app you were in before Unifind, which ⏎ pastes into (like Raycast's "Paste to …").
@MainActor @Observable
final class PasteTarget {
	static let shared = PasteTarget()

	private(set) var app: NSRunningApplication?
	private var observer: NSObjectProtocol?

	var name: String? { app?.localizedName }
	var icon: NSImage? { app?.icon }

	/// Follow app switches, remembering the latest app that isn't Unifind.
	func start() {
		guard observer == nil else { return }
		remember(NSWorkspace.shared.frontmostApplication)
		observer = NSWorkspace.shared.notificationCenter.addObserver(
			forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
		) { note in
			let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
			MainActor.assumeIsolated { PasteTarget.shared.remember(app) }
		}
	}

	private func remember(_ candidate: NSRunningApplication?) {
		guard let candidate, candidate.processIdentifier != ProcessInfo.processInfo.processIdentifier,
			candidate.activationPolicy == .regular
		else { return }
		app = candidate
	}
}

@MainActor
enum Paster {
	static let enabledKey = "pastesIntoLastApp"

	/// ⏎ pastes into the last app; off means ⏎ only copies.
	static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

	static var isTrusted: Bool { AXIsProcessTrusted() }

	static func requestTrust() {
		// kAXTrustedCheckOptionPrompt
		AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
	}

	static func openAccessibilitySettings() {
		NSWorkspace.shared.open(
			URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
	}

	/// Whether ⏎ will try to paste (rather than just copy) right now.
	static var canPaste: Bool { enabled && isTrusted && PasteTarget.shared.app.map { !$0.isTerminated } == true }

	enum Outcome {
		case pasted(into: String)
		case copied(reason: String?)
	}

	/// Copies `text`, then, if the last app has a text field focused, switches to it, sends ⌘V
	/// and puts the previous clipboard text back.
	static func paste(_ text: String) async -> Outcome {
		let board = NSPasteboard.general
		let previous = board.string(forType: .string)
		board.clearContents()
		board.setString(text, forType: .string)

		guard enabled, let app = PasteTarget.shared.app, !app.isTerminated else { return .copied(reason: nil) }
		let name = app.localizedName ?? "the last app"
		guard isTrusted else { return .copied(reason: "Allow Accessibility in Settings to paste") }
		guard hasFocusedTextInput(app.processIdentifier) else {
			return .copied(reason: "No text field in \(name)")
		}

		app.activate()
		for _ in 0..<50 where NSWorkspace.shared.frontmostApplication != app {
			try? await Task.sleep(for: .milliseconds(20))
		}
		try? await Task.sleep(for: .milliseconds(60))
		sendCommandV()

		// Give the app time to read the clipboard before restoring what was there.
		if let previous {
			try? await Task.sleep(for: .milliseconds(400))
			if board.string(forType: .string) == text {
				board.clearContents()
				board.setString(previous, forType: .string)
			}
		}
		return .pasted(into: name)
	}

	/// Asks the app (via Accessibility) whether its focused element takes typed text.
	static func hasFocusedTextInput(_ pid: pid_t) -> Bool {
		let appElement = AXUIElementCreateApplication(pid)
		// Chromium and Electron apps only build their accessibility tree when asked to.
		AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, true as CFBoolean)
		var focused: CFTypeRef?
		guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
			let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
		else { return false }
		let element = focused as! AXUIElement

		var role: CFTypeRef?
		AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
		let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]
		if let role = role as? String, textRoles.contains(role) { return true }

		// Rich text views and web content editors expose a settable selection.
		var settable: DarwinBoolean = false
		return AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success
			&& settable.boolValue
	}

	private static func sendCommandV() {
		let source = CGEventSource(stateID: .combinedSessionState)
		let v = CGKeyCode(kVK_ANSI_V)
		let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
		let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
		down?.flags = .maskCommand
		up?.flags = .maskCommand
		down?.post(tap: .cgAnnotatedSessionEventTap)
		up?.post(tap: .cgAnnotatedSessionEventTap)
	}
}

/// Loads the index and starts following app switches at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		PasteTarget.shared.start()
		Task { await AppModel.shared.load() }
	}
}
