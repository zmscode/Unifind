import SwiftUI

/// The active colour palette. Views read `Theme.bg0` etc.; because `ThemeStore` is observable,
/// they redraw when the theme changes in Settings.
enum Theme {
	@MainActor static var palette: Palette { ThemeStore.shared.palette }

	@MainActor static var bg0: Color { palette.bg0 }
	@MainActor static var bg1: Color { palette.bg1 }
	@MainActor static var bg2: Color { palette.bg2 }
	@MainActor static var bg3: Color { palette.bg3 }
	@MainActor static var fg: Color { palette.fg }
	@MainActor static var fg4: Color { palette.fg4 }
	@MainActor static var gray: Color { palette.gray }
	/// The one pop of colour: selection, focus, toasts.
	@MainActor static var accent: Color { palette.accentColor }
	/// Smart Search (Apple Intelligence) highlights.
	@MainActor static var smart: Color { palette.smartColor }

	/// Each category gets one of the theme's highlight colours, like syntax in an editor.
	@MainActor static func tint(for category: CharCategory) -> Color {
		guard category != .all else { return accent }
		let spectrum = palette.spectrum
		let i = CharCategory.allCases.firstIndex(of: category)!
		return spectrum[i % spectrum.count]
	}

	/// The font characters are drawn in: the family picked in Settings, or the system font.
	@MainActor static func glyphFont(size: CGFloat) -> Font {
		let family = ThemeStore.shared.fontFamily
		return family.isEmpty ? .system(size: size) : .custom(family, size: size)
	}
}

@MainActor @Observable
final class ThemeStore {
	static let shared = ThemeStore()
	static let key = "theme"
	static let defaultName = "Gruvbox Dark Soft"

	var name: String {
		didSet { UserDefaults.standard.set(name, forKey: Self.key) }
	}

	/// Font family for glyphs; empty means the system font.
	var fontFamily: String {
		didSet { UserDefaults.standard.set(fontFamily, forKey: Self.fontKey) }
	}
	static let fontKey = "glyphFont"

	var palette: Palette { Palette.named(name) ?? Palette.named(Self.defaultName)! }

	private init() {
		name = UserDefaults.standard.string(forKey: Self.key) ?? Self.defaultName
		fontFamily = UserDefaults.standard.string(forKey: Self.fontKey) ?? ""
	}
}

/// A theme, ported from the editor themes in Lines (which come from each theme's Zed extension).
/// Eight source colours; the panel shades in between are mixed from background and text.
struct Palette: Identifiable, Hashable, Sendable {
	var name: String
	var family: String
	var isDark: Bool
	var background: UInt32
	var text: UInt32
	var muted: UInt32
	var accent: UInt32
	var smart: UInt32
	var attribute: UInt32
	var character: UInt32
	var preprocessor: UInt32

	var id: String { name }

	/// The theme's highlight colours, for giving each category its own tint.
	var spectrum: [Color] {
		[accent, attribute, smart, preprocessor, character].map(Color.init(hex:))
	}

	var bg0: Color { Color(hex: background) }
	var bg1: Color { mix(0.05) }
	var bg2: Color { mix(0.12) }
	var bg3: Color { mix(0.24) }
	var fg: Color { Color(hex: text) }
	var fg4: Color { mix(0.68) }
	var gray: Color { Color(hex: muted) }
	var accentColor: Color { Color(hex: accent) }
	var smartColor: Color { Color(hex: smart) }
	var colorScheme: ColorScheme { isDark ? .dark : .light }

	/// Background blended `t` of the way toward the text colour.
	private func mix(_ t: Double) -> Color {
		func channel(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) }
		let blend = [16, 8, 0].map { shift in
			(channel(background, UInt32(shift)) * (1 - t) + channel(text, UInt32(shift)) * t) / 255
		}
		return Color(.sRGB, red: blend[0], green: blend[1], blue: blend[2])
	}

	static func named(_ name: String) -> Palette? { all.first { $0.name == name } }

	/// Family names in display order.
	static var families: [String] {
		all.reduce(into: []) { if !$0.contains($1.family) { $0.append($1.family) } }
	}

	static let all: [Palette] = [
		Palette(
			name: "Gruvbox Dark Soft", family: "Gruvbox", isDark: true,
			background: 0x32302F, text: 0xEBDBB2, muted: 0xA89984,
			accent: 0x8EC07C, smart: 0xFABD2F,
			attribute: 0x83A598, character: 0xC6B697, preprocessor: 0xFB4833),
		Palette(
			name: "Gruvbox Dark", family: "Gruvbox", isDark: true,
			background: 0x282828, text: 0xEBDBB2, muted: 0xA89984,
			accent: 0x8EC07C, smart: 0xFABD2F,
			attribute: 0x83A598, character: 0xC6B697, preprocessor: 0xFB4833),
		Palette(
			name: "Gruvbox Dark Hard", family: "Gruvbox", isDark: true,
			background: 0x1D2021, text: 0xEBDBB2, muted: 0xA89984,
			accent: 0x8EC07C, smart: 0xFABD2F,
			attribute: 0x83A598, character: 0xC6B697, preprocessor: 0xFB4833),
		Palette(
			name: "Gruvbox Light Soft", family: "Gruvbox", isDark: false,
			background: 0xF2E5BC, text: 0x282828, muted: 0x7C6F64,
			accent: 0x427B58, smart: 0xB57614,
			attribute: 0x0B6678, character: 0x5D544E, preprocessor: 0x9D0006),
		Palette(
			name: "Gruvbox Light", family: "Gruvbox", isDark: false,
			background: 0xFBF1C7, text: 0x282828, muted: 0x7C6F64,
			accent: 0x427B58, smart: 0xB57614,
			attribute: 0x0B6678, character: 0x5D544E, preprocessor: 0x9D0006),
		Palette(
			name: "Gruvbox Light Hard", family: "Gruvbox", isDark: false,
			background: 0xF9F5D7, text: 0x282828, muted: 0x7C6F64,
			accent: 0x427B58, smart: 0xB57614,
			attribute: 0x0B6678, character: 0x5D544E, preprocessor: 0x9D0006),
		Palette(
			name: "0x96f", family: "0x96f", isDark: true,
			background: 0x262427, text: 0xFCFCFC, muted: 0x757075,
			accent: 0x64D2E8, smart: 0xFFD271,
			attribute: 0xFC9D6F, character: 0xFFD271, preprocessor: 0xFCFCFC),
		Palette(
			name: "0x96f Lighter", family: "0x96f", isDark: true,
			background: 0x2E2C2F, text: 0xFCFCFC, muted: 0x757075,
			accent: 0x64D2E8, smart: 0xFFD271,
			attribute: 0xFC9D6F, character: 0xFFD271, preprocessor: 0xFCFCFC),
		Palette(
			name: "0x96f Darker", family: "0x96f", isDark: true,
			background: 0x1E1C1F, text: 0xFCFCFC, muted: 0x757075,
			accent: 0x64D2E8, smart: 0xFFD271,
			attribute: 0xFC9D6F, character: 0xFFD271, preprocessor: 0xFCFCFC),
		Palette(
			name: "Catppuccin Latte", family: "Catppuccin", isDark: false,
			background: 0xEFF1F5, text: 0x4C4F69, muted: 0x7C7F93,
			accent: 0x1E66F5, smart: 0x40A02B,
			attribute: 0xDF8E1D, character: 0xEA76CB, preprocessor: 0xEA76CB),
		Palette(
			name: "Catppuccin Frappé", family: "Catppuccin", isDark: true,
			background: 0x303446, text: 0xC6D0F5, muted: 0x949CBB,
			accent: 0x8CAAEE, smart: 0xA6D189,
			attribute: 0xE5C890, character: 0xF4B8E4, preprocessor: 0xF4B8E4),
		Palette(
			name: "Catppuccin Macchiato", family: "Catppuccin", isDark: true,
			background: 0x24273A, text: 0xCAD3F5, muted: 0x939AB7,
			accent: 0x8AADF4, smart: 0xA6DA95,
			attribute: 0xEED49F, character: 0xF5BDE6, preprocessor: 0xF5BDE6),
		Palette(
			name: "Catppuccin Mocha", family: "Catppuccin", isDark: true,
			background: 0x1E1E2E, text: 0xCDD6F4, muted: 0x9399B2,
			accent: 0x89B4FA, smart: 0xA6E3A1,
			attribute: 0xF9E2AF, character: 0xF5C2E7, preprocessor: 0xF5C2E7),
		Palette(
			name: "One Dark Pro", family: "One Dark Pro", isDark: true,
			background: 0x23272E, text: 0xABB2BF, muted: 0x7F838C,
			accent: 0xE06C75, smart: 0x98C379,
			attribute: 0xD19A66, character: 0x56B6C2, preprocessor: 0xC678DD),
		Palette(
			name: "Dracula", family: "Dracula", isDark: true,
			background: 0x282A36, text: 0xF8F8F2, muted: 0x6272A4,
			accent: 0xFF79C6, smart: 0xF1FA8C,
			attribute: 0x8BE9FD, character: 0xFF79C6, preprocessor: 0x6272A4),
		Palette(
			name: "Alucard (Dracula Light)", family: "Dracula", isDark: false,
			background: 0xF5F5F5, text: 0x1F1F1F, muted: 0x635D97,
			accent: 0xA3144D, smart: 0x846E15,
			attribute: 0x036A96, character: 0xA3144D, preprocessor: 0x635D97),
		Palette(
			name: "JetBrains Dark", family: "JetBrains", isDark: true,
			background: 0x1E1F22, text: 0xBCBEC4, muted: 0x7A7E85,
			accent: 0xD5B778, smart: 0x6AAB73,
			attribute: 0xB3AE60, character: 0xCF8E6D, preprocessor: 0xCF8E6D),
		Palette(
			name: "JetBrains Light", family: "JetBrains", isDark: false,
			background: 0xFFFFFF, text: 0x080808, muted: 0x8C8C8C,
			accent: 0x0033B3, smart: 0x067D17,
			attribute: 0x9E880D, character: 0x0037A6, preprocessor: 0x0033B3),
		Palette(
			name: "Monokai", family: "Monokai", isDark: true,
			background: 0x272822, text: 0xF8F8F2, muted: 0x88846F,
			accent: 0xF92672, smart: 0xE6DB74,
			attribute: 0xA6E22E, character: 0xAE81FF, preprocessor: 0xF92672),
		Palette(
			name: "VS Code Dark Modern", family: "VS Code", isDark: true,
			background: 0x1F1F1F, text: 0xCCCCCC, muted: 0x6A9955,
			accent: 0x569CD6, smart: 0xCE9178,
			attribute: 0x9CDCFE, character: 0xD7BA7D, preprocessor: 0x569CD6),
		Palette(
			name: "Ayu Dark", family: "Ayu", isDark: true,
			background: 0x0D1016, text: 0xBFBDB6, muted: 0x5C6773,
			accent: 0x5AC1FE, smart: 0xA9D94B,
			attribute: 0x5AC1FE, character: 0x8C8B88, preprocessor: 0xFF8F3F),
		Palette(
			name: "Ayu Mirage", family: "Ayu", isDark: true,
			background: 0x242835, text: 0xCCCAC2, muted: 0x5C6773,
			accent: 0x72CFFE, smart: 0xD4FE7F,
			attribute: 0x72CFFE, character: 0x9B9B99, preprocessor: 0xFFAD65),
		Palette(
			name: "Ayu Light", family: "Ayu", isDark: false,
			background: 0xFCFCFC, text: 0x5C6166, muted: 0xABB0B6,
			accent: 0x3B9EE5, smart: 0x86B300,
			attribute: 0x3B9EE5, character: 0x898D90, preprocessor: 0xFA8D3E),
	]
}

extension Color {
	init(hex: UInt32) {
		self.init(
			.sRGB,
			red: Double((hex >> 16) & 0xFF) / 255,
			green: Double((hex >> 8) & 0xFF) / 255,
			blue: Double(hex & 0xFF) / 255)
	}
}
