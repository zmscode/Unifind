import SwiftUI

/// Which tile the pointer is over, and where. Kept apart from `AppModel` so pointer moves only
/// redraw the preview card, not the whole grid.
@MainActor @Observable
final class HoverState {
	static let shared = HoverState()
	var entry: CharEntry?
	var point: CGPoint = .zero
}

/// A small floating card, shown after a short pause over a tile, with the character drawn in
/// every weight its font has.
struct HoverCard: View {
	let bounds: CGSize
	@State private var shown: CharEntry?
	@State private var cardSize: CGSize = .zero

	private let glyphSize: CGFloat = 30

	var body: some View {
		let state = HoverState.shared
		ZStack(alignment: .topLeading) {
			if let e = shown,
				let weights = Fonts.weights(
					for: e.id, family: ThemeStore.shared.fontFamily, size: glyphSize)
			{
				card(e, weights)
					.fixedSize()
					.onGeometryChange(for: CGSize.self) {
						$0.size
					} action: {
						cardSize = $0
					}
					.offset(position(for: state.point))
					.transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.allowsHitTesting(false)
		.animation(.easeOut(duration: 0.12), value: shown?.id)
		.task(id: state.entry?.id) {
			shown = nil
			guard let e = state.entry, !e.isInvisible else { return }
			try? await Task.sleep(for: .milliseconds(450))
			guard !Task.isCancelled else { return }
			shown = e
		}
	}

	/// Centred just below the pointer, flipped above it near the bottom and kept inside the results.
	private func position(for p: CGPoint) -> CGSize {
		let x = min(max(8, p.x - cardSize.width / 2), bounds.width - cardSize.width - 8)
		var y = p.y + 22
		if y + cardSize.height > bounds.height - 8 { y = p.y - cardSize.height - 14 }
		return CGSize(width: x, height: max(8, y))
	}

	private func card(_ e: CharEntry, _ weights: Fonts.Weights) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			VStack(alignment: .leading, spacing: 2) {
				Text(e.displayName)
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(Theme.fg)
					.lineLimit(1)
				Text(
					weights.samples.count == 1
						? "\(weights.family) · single weight"
						: "\(weights.family) · \(weights.samples.count) weights"
				)
				.font(.system(size: 10))
				.foregroundStyle(Theme.fg4)
			}
			HStack(alignment: .bottom, spacing: 10) {
				ForEach(weights.samples.prefix(10)) { sample in
					VStack(spacing: 3) {
						Text(e.glyph)
							.font(
								weights.samples.count == 1
									? sample.font.leading(.tight) : sample.font
							)
							.foregroundStyle(Theme.fg)
							.frame(minWidth: glyphSize, minHeight: glyphSize + 8)
						if weights.samples.count > 1 {
							Text(sample.label)
								.font(.system(size: 8.5))
								.foregroundStyle(Theme.gray)
								.lineLimit(1)
						}
					}
				}
			}
		}
		.frame(maxWidth: 520, alignment: .leading)
		.padding(12)
		.background(Theme.bg1, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
		)
		.shadow(color: .black.opacity(0.3), radius: 14, y: 6)
	}
}
