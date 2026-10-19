import SwiftUI

@main
struct UnifindApp: App {
	@State private var model = AppModel()

	var body: some Scene {
		WindowGroup("Unifind") {
			ContentView()
				.environment(model)
				.task { await model.load() }
		}
		.defaultSize(width: 980, height: 660)

		Settings {
			SettingsView()
				.environment(model)
		}
	}
}

struct ContentView: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		@Bindable var model = model
		HStack(spacing: 0) {
			Sidebar()
				.frame(width: 196)
			VStack(spacing: 0) {
				ResultsView()
				DetailBar()
			}
		}
		.background(Theme.bg0)
		.foregroundStyle(Theme.fg)
		.tint(Theme.accent)
		.preferredColorScheme(Theme.palette.colorScheme)
		.searchable(text: $model.query, placement: .toolbar, prompt: "Search characters")
		.onSubmit(of: .search) { model.copyFirstResult() }
		.toolbar(removing: .title)
		.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
		.containerBackground(Theme.bg0, for: .window)
		.toolbar {
			ToolbarItem { FilterMenu() }
			ToolbarItem {
				Toggle(isOn: $model.smartEnabled) {
					Label("Smart Search", systemImage: "sparkles")
				}
				.tint(Theme.smart)
				.help(smartHelp)
				.disabled(model.smart.engine == .none)
			}
		}
		.overlay(alignment: .bottom) {
			if let toast = model.toast {
				Text(toast)
					.font(.system(size: 12, weight: .semibold))
					.foregroundStyle(Theme.bg0)
					.padding(.horizontal, 14)
					.padding(.vertical, 7)
					.background(Theme.accent, in: Capsule())
					.padding(.bottom, 80)
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.animation(.snappy, value: model.toast)
	}

	private var smartHelp: String {
		switch model.smart.engine {
		case .appleIntelligence:
			"Smart Search uses Apple Intelligence on-device to find related characters"
		case .wordEmbedding:
			"Smart Search uses on-device word similarity (\(model.smart.unavailableReason ?? ""))"
		case .none: "Smart Search is unavailable"
		}
	}
}

// MARK: - Sidebar

struct Sidebar: View {
	@Environment(AppModel.self) private var model

	var body: some View {
		VStack(spacing: 0) {
			ScrollView {
				VStack(alignment: .leading, spacing: 2) {
					row(.all)
					row(.recents)
					Rectangle().fill(Theme.bg2).frame(height: 1).padding(.vertical, 8).padding(
						.horizontal, 8)
					ForEach(CharCategory.allCases.dropFirst(2)) { row($0) }
				}
				.padding(.horizontal, 10)
				.padding(.top, 8)
				.padding(.bottom, 12)
			}
			.scrollIndicators(.never)
			ThemeBadge()
		}
		.background(Theme.bg1)
	}

	private func row(_ c: CharCategory) -> some View {
		SidebarRow(category: c, selected: model.currentCategory == c) { model.category = c }
	}
}

private struct SidebarRow: View {
	let category: CharCategory
	let selected: Bool
	let action: () -> Void
	@State private var hovering = false

	var body: some View {
		Button(action: action) {
			HStack(spacing: 10) {
				Image(systemName: category.systemImage)
					.frame(width: 18)
					.foregroundStyle(
						Theme.tint(for: category).opacity(selected || hovering ? 1 : 0.75))
				Text(category.rawValue)
					.foregroundStyle(selected ? Theme.fg : Theme.fg4)
					.lineLimit(1)
				Spacer(minLength: 0)
			}
			.font(.system(size: 13, weight: selected ? .semibold : .regular))
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(
				RoundedRectangle(cornerRadius: 7, style: .continuous)
					.fill(
						selected
							? Theme.tint(for: category).opacity(0.16)
							: hovering ? Theme.bg2.opacity(0.6) : .clear)
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
	}
}

/// The current theme's name and colours at the foot of the sidebar; opens Settings.
private struct ThemeBadge: View {
	@State private var hovering = false

	var body: some View {
		SettingsLink {
			HStack(spacing: 8) {
				HStack(spacing: -4) {
					ForEach(Array(Theme.palette.spectrum.enumerated()), id: \.offset) { _, color in
						Circle()
							.fill(color)
							.frame(width: 12, height: 12)
							.overlay(Circle().strokeBorder(Theme.bg1, lineWidth: 1.5))
					}
				}
				Text(Theme.palette.name)
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(hovering ? Theme.fg : Theme.fg4)
					.lineLimit(1)
				Spacer(minLength: 0)
				Image(systemName: "paintpalette")
					.font(.system(size: 11))
					.foregroundStyle(hovering ? Theme.accent : Theme.gray)
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 8)
			.background(
				RoundedRectangle(cornerRadius: 8, style: .continuous)
					.fill(hovering ? Theme.bg2 : Theme.bg2.opacity(0.5))
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.help("Change theme (⌘,)")
		.padding(10)
	}
}

// MARK: - Results

struct ResultsView: View {
	@Environment(AppModel.self) private var model
	@State private var size = CGSize(width: 700, height: 500)
	private var width: CGFloat { size.width }

	private let tile: CGFloat = 54
	private let spacing: CGFloat = 4
	private let padding: CGFloat = 18

	private var columns: Int { max(1, Int((width - padding * 2 + spacing) / (tile + spacing))) }

	var body: some View {
		Group {
			if model.index == nil {
				ProgressView().controlSize(.small)
			} else if model.directResults.isEmpty && model.relatedResults.isEmpty
				&& !model.isThinking
			{
				emptyState
			} else {
				ScrollView {
					LazyVStack(alignment: .leading, spacing: spacing, pinnedViews: .sectionHeaders)
					{
						if model.isSearching {
							if !model.directResults.isEmpty {
								Section {
									rows(model.directResults, key: "d")
								} header: {
									header("Matches", count: model.directResults.count)
								}
							}
							if model.isThinking || !model.relatedResults.isEmpty {
								Section {
									rows(model.relatedResults, key: "r")
								} header: {
									relatedHeader
								}
							}
						} else {
							Section {
								rows(model.directResults, key: "b")
							} header: {
								header(
									model.currentCategory.rawValue,
									count: model.directResults.count,
									tint: Theme.tint(for: model.currentCategory))
							}
						}
					}
					.padding(.horizontal, padding)
					.padding(.bottom, padding)
				}
				.onContinuousHover(coordinateSpace: .named("results")) { phase in
					switch phase {
					case .active(let p): HoverState.shared.point = p
					case .ended: HoverState.shared.entry = nil
					}
				}
				.overlay { HoverCard(bounds: size) }
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.coordinateSpace(.named("results"))
		.onGeometryChange(for: CGSize.self) {
			$0.size
		} action: {
			size = $0
		}
	}

	@ViewBuilder
	private func rows(_ items: [Int], key: String) -> some View {
		let cols = columns
		let rowCount = (items.count + cols - 1) / cols
		ForEach(0..<rowCount, id: \.self) { r in
			HStack(spacing: spacing) {
				ForEach(items[(r * cols)..<min(items.count, (r + 1) * cols)], id: \.self) { i in
					if let e = model.entry(i) { GlyphTile(entry: e, size: tile) }
				}
			}
			.id("\(key)\(r)-\(cols)")
		}
	}

	private func header(_ title: String, count: Int, tint: Color = Theme.accent) -> some View {
		HStack(spacing: 8) {
			Circle().fill(tint).frame(width: 7, height: 7)
			Text(title.uppercased())
				.font(.system(size: 11, weight: .bold))
				.kerning(0.8)
				.foregroundStyle(tint)
			Text(count.formatted())
				.font(.system(size: 11, design: .monospaced))
				.foregroundStyle(Theme.gray)
			Spacer()
		}
		.padding(.top, 12)
		.padding(.bottom, 8)
		.background(Theme.bg0)
	}

	private var relatedHeader: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 6) {
				Image(systemName: "sparkles").foregroundStyle(Theme.smart)
				Text("RELATED")
					.font(.system(size: 11, weight: .bold))
					.kerning(0.8)
					.foregroundStyle(Theme.smart)
				if model.isThinking {
					Text("thinking…")
						.font(.system(size: 11, design: .monospaced))
						.foregroundStyle(Theme.smart.opacity(0.8))
				} else {
					Text(model.relatedResults.count.formatted())
						.font(.system(size: 11, design: .monospaced))
						.foregroundStyle(Theme.gray)
				}
				Spacer()
			}
			if !model.relatedTerms.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 6) {
						ForEach(model.relatedTerms, id: \.self) { term in
							TermChip(term: term) { model.query = term }
						}
					}
				}
			}
		}
		.padding(.top, 16)
		.padding(.bottom, 8)
		.background(Theme.bg0)
	}

	private var emptyState: some View {
		VStack(spacing: 10) {
			Image(systemName: model.currentCategory == .recents ? "clock" : "magnifyingglass")
				.font(.system(size: 28))
				.foregroundStyle(Theme.bg3)
			Text(
				model.currentCategory == .recents && !model.isSearching
					? "Nothing copied yet" : "No characters"
			)
			.foregroundStyle(Theme.fg4)
			if model.isSearching && model.currentCategory != .all {
				Button("Search all characters") { model.category = .all }
					.buttonStyle(.plain)
					.foregroundStyle(Theme.accent)
			}
		}
		.font(.system(size: 13))
	}
}

private struct TermChip: View {
	let term: String
	let action: () -> Void
	@State private var hovering = false

	var body: some View {
		Button(term, action: action)
			.buttonStyle(.plain)
			.font(.system(size: 11, weight: .medium))
			.foregroundStyle(hovering ? Theme.bg0 : Theme.fg4)
			.padding(.horizontal, 9)
			.padding(.vertical, 4)
			.background(hovering ? Theme.smart : Theme.bg1, in: Capsule())
			.onHover { hovering = $0 }
	}
}

struct GlyphTile: View {
	@Environment(AppModel.self) private var model
	let entry: CharEntry
	let size: CGFloat
	@State private var hovering = false

	var body: some View {
		let selected = model.selection == entry.id
		GlyphView(entry: entry, size: size * 0.5)
			.foregroundStyle(selected ? Theme.accent : Theme.fg)
			.frame(width: size, height: size)
			.background(
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.fill(
						selected
							? Theme.accent.opacity(0.18)
							: hovering ? Theme.accent.opacity(0.07) : .clear)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.strokeBorder(selected ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1)
			)
			.contentShape(Rectangle())
			.onHover { inside in
				hovering = inside
				let hover = HoverState.shared
				if inside {
					hover.entry = entry
				} else if hover.entry?.id == entry.id {
					hover.entry = nil
				}
			}
			.onTapGesture(count: 2) { model.copyCharacter(entry) }
			.simultaneousGesture(TapGesture().onEnded { model.selection = entry.id })
			.draggable(String(Unicode.Scalar(entry.id)!))
			.contextMenu {
				Button("Copy Character") { model.copyCharacter(entry) }
				Button("Copy Name") { model.copy(entry.name) }
				Button("Copy Code Point") { model.copy(entry.codepoint) }
			}
	}
}

/// Draws a character, or a labeled dashed box for spaces and format characters that draw nothing.
struct GlyphView: View {
	let entry: CharEntry
	let size: CGFloat

	var body: some View {
		if entry.isInvisible {
			Text(entry.abbreviation)
				.font(.system(size: size * 0.42, weight: .medium, design: .monospaced))
				.foregroundStyle(Theme.gray)
				.padding(.horizontal, size * 0.12)
				.padding(.vertical, size * 0.06)
				.overlay(
					RoundedRectangle(cornerRadius: size * 0.12)
						.strokeBorder(Theme.bg3, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
				)
		} else {
			Text(entry.glyph)
				.font(Theme.glyphFont(size: size))
				.lineLimit(1)
				.minimumScaleFactor(0.4)
		}
	}
}

struct FilterMenu: View {
	@Environment(AppModel.self) private var model

	private static let hideable: [CharCategory] = [
		.emoji, .letters, .ideographs, .marks, .spaces, .numbers, .punctuation, .math, .boxDrawing,
	]

	var body: some View {
		Menu {
			Section("Hide in Results") {
				ForEach(Self.hideable) { c in
					Toggle(
						isOn: Binding(get: { model.isHidden(c) }, set: { model.setHidden(c, $0) })
					) {
						Label(c.rawValue, systemImage: c.systemImage)
					}
				}
			}
			Section {
				Toggle(
					"Show Characters Without a Font",
					isOn: Binding(
						get: { model.includeUnrenderable }, set: { model.includeUnrenderable = $0 })
				)
			}
			if model.filtersActive {
				Button("Reset Filters") {
					model.hidden = []
					model.includeUnrenderable = false
				}
			}
		} label: {
			Label(
				"Filter",
				systemImage: model.filtersActive
					? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
			)
		}
		.tint(model.filtersActive ? Theme.accent : nil)
		.help("Filter results")
	}
}
