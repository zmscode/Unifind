import SwiftUI

/// Settings (⌘,): pick a theme from a grid of live previews, grouped by family.
struct SettingsView: View {
	@Bindable private var store = ThemeStore.shared

	private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				FontSection()
				Divider()
				Text("Theme")
					.font(.title2.weight(.semibold))
				ForEach(Palette.families, id: \.self) { family in
					VStack(alignment: .leading, spacing: 8) {
						Text(family)
							.font(.subheadline.weight(.medium))
							.foregroundStyle(.secondary)
						LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
							ForEach(Palette.all.filter { $0.family == family }) { p in
								ThemeCard(palette: p, selected: store.name == p.name) {
									store.name = p.name
								}
							}
						}
					}
				}
				Text(
					"Themes are ported from Lines, which takes them from each theme's Zed extension."
				)
				.font(.footnote)
				.foregroundStyle(.secondary)
			}
			.padding(24)
		}
		.frame(width: 560, height: 680)
	}
}

private struct ThemeCard: View {
	let palette: Palette
	let selected: Bool
	let action: () -> Void
	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			VStack(alignment: .leading, spacing: 6) {
				preview
				HStack(spacing: 4) {
					Text(palette.name)
						.font(.system(size: 12, weight: selected ? .semibold : .regular))
						.lineLimit(1)
					if selected {
						Image(systemName: "checkmark.circle.fill")
							.foregroundStyle(Color.accentColor)
							.font(.system(size: 11))
					}
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
	}

	/// A miniature Unifind window: sidebar, glyph grid with one selected tile, smart sparkle.
	private var preview: some View {
		HStack(spacing: 0) {
			VStack(alignment: .leading, spacing: 4) {
				RoundedRectangle(cornerRadius: 2).fill(palette.bg2).frame(height: 7)
				ForEach(0..<3, id: \.self) { _ in
					RoundedRectangle(cornerRadius: 2).fill(palette.gray.opacity(0.35)).frame(
						height: 5)
				}
				Spacer(minLength: 0)
			}
			.padding(6)
			.frame(width: 38)
			.background(palette.bg1)

			VStack(alignment: .leading, spacing: 5) {
				HStack(spacing: 6) {
					Text("◆").foregroundStyle(palette.fg)
					Text("→")
						.foregroundStyle(palette.accentColor)
						.padding(.horizontal, 3)
						.background(
							palette.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 3)
						)
					Text("★").foregroundStyle(palette.fg)
				}
				HStack(spacing: 6) {
					Text("✦").foregroundStyle(palette.smartColor)
					Text("○").foregroundStyle(palette.fg)
					Text("¶").foregroundStyle(palette.fg4)
				}
			}
			.font(.system(size: 13))
			.padding(.horizontal, 8)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
			.background(palette.bg0)
		}
		.frame(height: 64)
		.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.strokeBorder(
					selected
						? Color.accentColor
						: hovering ? Color.secondary.opacity(0.6) : Color.secondary.opacity(0.25),
					lineWidth: selected ? 2 : 1)
		)
	}
}

/// Pick the font glyphs are drawn in, with a live preview and notes on how well it fits.
private struct FontSection: View {
	@Environment(AppModel.self) private var model
	@Bindable private var store = ThemeStore.shared
	@State private var families: [String] = []
	@State private var compatibility: Fonts.Compatibility?

	private let sample = "Aa → ★ ∑ ¶ ♪ ✦ ① ⌘ ▲ ☂"

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Glyph Font")
				.font(.title2.weight(.semibold))
			Picker("Font", selection: $store.fontFamily) {
				Text("System (SF Pro)").tag("")
				Divider()
				ForEach(families, id: \.self) { Text($0).tag($0) }
			}
			.labelsHidden()
			.frame(maxWidth: 280)

			Text(sample)
				.font(Theme.glyphFont(size: 26))
				.foregroundStyle(Theme.fg)
				.lineLimit(1)
				.minimumScaleFactor(0.5)
				.padding(.horizontal, 14)
				.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
				.background(Theme.bg0, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

			note
		}
		.task { families = Fonts.families() }
		.task(id: store.fontFamily) { measure() }
	}

	private func measure() {
		guard !store.fontFamily.isEmpty, let index = model.index else {
			compatibility = nil
			return
		}
		compatibility = Fonts.compatibility(of: store.fontFamily, in: index)
	}

	@ViewBuilder
	private var note: some View {
		if store.fontFamily.isEmpty {
			label(
				"checkmark.seal", .green,
				"Best coverage: SF Pro, with macOS picking the right fallback font for everything else."
			)
		} else if let c = compatibility {
			if c.remapsLetters {
				label(
					"exclamationmark.octagon", .red,
					"\(store.fontFamily) is a picture font: it draws symbols in place of ordinary letters, so many characters will show the wrong shape."
				)
			} else {
				let percent = (c.fraction * 100).formatted(
					.number.precision(.fractionLength(c.fraction < 0.1 ? 1 : 0)))
				let detail =
					"Covers \(c.covered.formatted()) of \(c.total.formatted()) characters (\(percent)%). Anything it doesn't have falls back to other installed fonts"
				// Most text fonts cover a few hundred to a few thousand characters; under ~300 means
				// barely beyond ASCII, so nearly every result falls back.
				if c.covered < 300 {
					label(
						"exclamationmark.triangle", .orange,
						detail + ", so almost every result will be in a different font.")
				} else {
					label("info.circle", .secondary, detail + ".")
				}
			}
		} else {
			label("questionmark.circle", .secondary, "Couldn't read this font's character set.")
		}
	}

	private func label(_ symbol: String, _ color: Color, _ text: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Image(systemName: symbol).foregroundStyle(color)
			Text(text).foregroundStyle(.secondary)
		}
		.font(.callout)
		.fixedSize(horizontal: false, vertical: true)
	}
}
