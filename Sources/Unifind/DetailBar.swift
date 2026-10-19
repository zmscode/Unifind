import SwiftUI

/// A slim strip along the bottom showing the selected character and one-click copy formats.
struct DetailBar: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		HStack(spacing: 14) {
			if let e = model.selectedEntry {
				Button {
					model.copyCharacter(e)
				} label: {
					GlyphView(entry: e, size: 30)
						.foregroundStyle(Theme.accent)
						.frame(width: 50, height: 50)
						.background(
							Theme.accent.opacity(0.14),
							in: RoundedRectangle(cornerRadius: 10, style: .continuous)
						)
						.overlay(
							RoundedRectangle(cornerRadius: 10, style: .continuous)
								.strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
						)
				}
				.buttonStyle(.plain)
				.help("Copy character")

				VStack(alignment: .leading, spacing: 3) {
					Text(e.displayName)
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(Theme.fg)
						.lineLimit(1)
					HStack(spacing: 6) {
						Text(e.codepoint).foregroundStyle(Theme.accent)
						Text("·")
						Text(e.block)
						Text("·")
						Text(e.generalCategory.label)
						if !e.renderable {
							Text("· no font").foregroundStyle(Theme.smart)
						}
					}
					.font(.system(size: 11, design: .monospaced))
					.foregroundStyle(Theme.fg4)
					.lineLimit(1)
				}
				.textSelection(.enabled)

				Spacer(minLength: 8)

				HStack(spacing: 6) {
					ForEach(formats(for: e), id: \.label) { f in
						CopyPill(label: f.label, value: f.value)
					}
				}
			} else {
				Text("click to inspect  ·  double-click to copy  ·  ⏎ copies the top result")
					.font(.system(size: 10.5))
					.foregroundStyle(Theme.gray.opacity(0.7))
					.frame(maxWidth: .infinity)
			}
		}
		.padding(.horizontal, 16)
		.frame(height: model.selectedEntry == nil ? 26 : 66)
		.background(model.selectedEntry == nil ? Theme.bg0 : Theme.bg1)
		.overlay(alignment: .top) {
			Rectangle().fill(Theme.bg2.opacity(model.selectedEntry == nil ? 0.5 : 1)).frame(
				height: 1)
		}
		.animation(.snappy(duration: 0.2), value: model.selection)
	}

	private func formats(for e: CharEntry) -> [(label: String, value: String)] {
		let hex = String(e.id, radix: 16, uppercase: true)
		return [
			("U+", e.codepoint),
			("HTML", "&#x\(hex);"),
			("Swift", "\\u{\(hex)}"),
			("Name", e.name),
		]
	}
}

private struct CopyPill: View {
	@Environment(AppModel.self) private var model
	let label: String
	let value: String
	@State private var hovering = false

	var body: some View {
		Button(label) { model.copy(value) }
			.buttonStyle(.plain)
			.font(.system(size: 11, weight: .medium, design: .monospaced))
			.foregroundStyle(hovering ? Theme.bg0 : Theme.fg4)
			.padding(.horizontal, 9)
			.padding(.vertical, 5)
			.background(hovering ? Theme.accent : Theme.bg2, in: Capsule())
			.onHover { hovering = $0 }
			.help(value)
	}
}

extension Unicode.GeneralCategory {
	var label: String {
		switch self {
		case .uppercaseLetter: "Uppercase Letter"
		case .lowercaseLetter: "Lowercase Letter"
		case .titlecaseLetter: "Titlecase Letter"
		case .modifierLetter: "Modifier Letter"
		case .otherLetter: "Letter"
		case .nonspacingMark: "Nonspacing Mark"
		case .spacingMark: "Spacing Mark"
		case .enclosingMark: "Enclosing Mark"
		case .decimalNumber: "Decimal Digit"
		case .letterNumber: "Letter Number"
		case .otherNumber: "Number"
		case .connectorPunctuation: "Connector Punctuation"
		case .dashPunctuation: "Dash"
		case .openPunctuation: "Opening Punctuation"
		case .closePunctuation: "Closing Punctuation"
		case .initialPunctuation: "Initial Quote"
		case .finalPunctuation: "Final Quote"
		case .otherPunctuation: "Punctuation"
		case .mathSymbol: "Math Symbol"
		case .currencySymbol: "Currency Symbol"
		case .modifierSymbol: "Modifier Symbol"
		case .otherSymbol: "Symbol"
		case .spaceSeparator: "Space"
		case .lineSeparator: "Line Separator"
		case .paragraphSeparator: "Paragraph Separator"
		case .control: "Control"
		case .format: "Format"
		case .surrogate: "Surrogate"
		case .privateUse: "Private Use"
		case .unassigned: "Unassigned"
		@unknown default: "Other"
		}
	}
}
