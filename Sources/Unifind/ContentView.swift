import SwiftUI

@main
struct UnifindApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
	@State private var model = AppModel.shared

	var body: some Scene {
		WindowGroup("Unifind") {
			ContentView()
				.environment(model)
				.task { await model.load() }
		}
		.defaultSize(width: 980, height: 660)
		.commands {
			CommandGroup(after: .pasteboard) {
				Button("Inspect Clipboard Text") {
					if let text = NSPasteboard.general.string(forType: .string) {
						model.query = text
					}
				}
				.keyboardShortcut("v", modifiers: [.command, .shift])
			}
		}

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
		.onSubmit(of: .search) { model.pasteReturnTarget() }
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
					row(.favorites)
					Rectangle().fill(Theme.bg2).frame(height: 1).padding(.vertical, 8).padding(
						.horizontal, 8)
					ForEach(CharCategory.unicodeCategories) { row($0) }
				}
				.padding(.horizontal, 10)
				.padding(.top, 8)
				.padding(.bottom, 12)
			}
			.scrollIndicators(.never)
			AppBadge()
				.padding(10)
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

/// App icon, name and version at the very foot of the sidebar; opens Settings › About.
private struct AppBadge: View {
	@Environment(\.openSettings) private var openSettings
	@AppStorage(SettingsTab.key) private var tab = SettingsTab.general.rawValue
	@State private var hovering = false

	var body: some View {
		Button {
			tab = SettingsTab.about.rawValue
			openSettings()
		} label: {
			HStack(spacing: 10) {
				Image(nsImage: AppInfo.icon)
					.resizable()
					.frame(width: 34, height: 34)
				VStack(alignment: .leading, spacing: 1) {
					Text(AppInfo.name)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(hovering ? Theme.fg : Theme.fg.opacity(0.9))
					Text("Version \(AppInfo.version)")
						.font(.system(size: 10.5, design: .monospaced))
						.foregroundStyle(Theme.gray)
				}
				Spacer(minLength: 0)
			}
			.padding(.horizontal, 8)
			.padding(.vertical, 6)
			.background(
				RoundedRectangle(cornerRadius: 9, style: .continuous)
					.fill(hovering ? Theme.bg2 : .clear)
			)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.onHover { hovering = $0 }
		.help("About \(AppInfo.name) \(AppInfo.fullVersion)")
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
				&& !model.isThinking && model.inspectedText.isEmpty
			{
				emptyState
			} else {
				ScrollView {
					LazyVStack(alignment: .leading, spacing: spacing, pinnedViews: .sectionHeaders)
					{
						if model.isSearching {
							let inspected = model.inspectedText
							if !inspected.isEmpty {
								Section {
									textRows(inspected)
								} header: {
									header("In your text", count: inspected.count, tint: Theme.smart)
								}
							}
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

	/// Pasted text in order, repeats and all, so ids are positions rather than characters.
	@ViewBuilder
	private func textRows(_ entries: [CharEntry]) -> some View {
		let cols = columns
		let rowCount = (entries.count + cols - 1) / cols
		ForEach(0..<rowCount, id: \.self) { r in
			HStack(spacing: spacing) {
				ForEach((r * cols)..<min(entries.count, (r + 1) * cols), id: \.self) { i in
					GlyphTile(entry: entries[i], size: tile)
				}
			}
			.id("t\(r)-\(cols)")
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
		let browsing = !model.isSearching
		let (symbol, title, hint): (String, String, String?) =
			switch (model.currentCategory, browsing) {
			case (.recents, true): ("clock", "Nothing copied yet", "Double-click a character to copy it.")
			case (.favorites, true):
				("star", "No favourites yet", "Right-click a character, or press ☆ in the bottom bar.")
			default: ("magnifyingglass", "No characters", nil)
			}
		return VStack(spacing: 10) {
			Image(systemName: symbol)
				.font(.system(size: 28))
				.foregroundStyle(Theme.bg3)
			Text(title)
				.foregroundStyle(Theme.fg4)
			if let hint {
				Text(hint)
					.font(.system(size: 11))
					.foregroundStyle(Theme.gray)
			}
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
				Button(model.isFavorite(entry.id) ? "Remove from Favourites" : "Add to Favourites") {
					model.toggleFavorite(entry)
				}
				Divider()
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
