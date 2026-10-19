import AppKit
import Observation

@MainActor @Observable
final class AppModel {
	/// One model for the window, the Quick Insert panel and Settings.
	static let shared = AppModel()

	private(set) var index: CharacterIndex?

	var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
	var category: CharCategory? = .all { didSet { if category != oldValue { scheduleSearch() } } }
	var selection: UInt32?
	var smartEnabled: Bool {
		didSet {
			UserDefaults.standard.set(smartEnabled, forKey: "smartEnabled")
			scheduleSearch()
		}
	}

	/// Categories hidden from results (e.g. emoji), except when browsing that category directly.
	var hidden: CharCategory.Mask {
		didSet {
			UserDefaults.standard.set(Int(hidden.rawValue), forKey: "hiddenCategories")
			filtersChanged()
		}
	}
	/// Show characters no installed font can draw (they appear as "?" boxes).
	var includeUnrenderable: Bool {
		didSet {
			UserDefaults.standard.set(includeUnrenderable, forKey: "includeUnrenderable")
			filtersChanged()
		}
	}

	private(set) var directResults: [Int] = []
	private(set) var relatedResults: [Int] = []
	private(set) var relatedTerms: [String] = []
	private(set) var isThinking = false
	private(set) var recents: [UInt32]
	private(set) var favorites: [UInt32]
	private(set) var toast: String?

	let smart = SmartSearch()
	private var searchTask: Task<Void, Never>?
	private var toastTask: Task<Void, Never>?
	private var browseCache: [CharCategory: [Int]] = [:]

	private init() {
		recents = (UserDefaults.standard.array(forKey: "recents") as? [Int])?.map(UInt32.init) ?? []
		favorites = (UserDefaults.standard.array(forKey: "favorites") as? [Int])?.map(UInt32.init) ?? []
		smartEnabled = UserDefaults.standard.object(forKey: "smartEnabled") as? Bool ?? true
		hidden = CharCategory.Mask(
			rawValue: UInt32(UserDefaults.standard.integer(forKey: "hiddenCategories")))
		includeUnrenderable = UserDefaults.standard.bool(forKey: "includeUnrenderable")
		// `open -a Unifind --args -query arrow` opens with a search already typed.
		query = UserDefaults.standard.string(forKey: "query") ?? ""
	}

	var filtersActive: Bool { !hidden.isEmpty || includeUnrenderable }

	func isHidden(_ c: CharCategory) -> Bool { hidden.contains(c.mask) }
	func setHidden(_ c: CharCategory, _ hide: Bool) {
		if hide { hidden.insert(c.mask) } else { hidden.remove(c.mask) }
	}

	private func filter(for category: CharCategory) -> SearchFilter {
		SearchFilter(
			category: category, allowed: personalList(category).map(Set.init),
			hidden: hidden, includeUnrenderable: includeUnrenderable)
	}

	/// Recently Copied and Favourites are lists the person built, not Unicode categories.
	private func personalList(_ category: CharCategory) -> [UInt32]? {
		switch category {
		case .recents: recents
		case .favorites: favorites
		default: nil
		}
	}

	private func filtersChanged() {
		browseCache = [:]
		scheduleSearch()
	}

	private var loading: Task<Void, Never>?

	/// Builds the index once, however many callers (app delegate, window) ask at launch.
	func load() async {
		if let loading { return await loading.value }
		let task = Task {
			let built = await Task.detached(priority: .userInitiated) { CharacterIndex() }.value
			index = built
			scheduleSearch()
			await smart.prewarm()
		}
		loading = task
		await task.value
	}

	var currentCategory: CharCategory { category ?? .all }
	var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

	/// Pasted text broken into its characters, invisible ones included ("é" written as e + ◌́,
	/// zero-width joiners in emoji, variation selectors). Empty for ordinary name searches:
	/// only text with two or more characters, at least one of them beyond printable ASCII.
	var inspectedText: [CharEntry] {
		guard let index else { return [] }
		let scalars = Array(query.unicodeScalars)
		guard scalars.count >= 2, scalars.contains(where: { $0.value > 0x7E || $0.value < 0x20 })
		else { return [] }
		return scalars.compactMap { s in index.byScalar[s.value].map { index.entries[$0] } }
	}

	func entry(_ i: Int) -> CharEntry? { index?.entries[i] }
	var selectedEntry: CharEntry? {
		guard let selection, let index, let i = index.byScalar[selection] else { return nil }
		return index.entries[i]
	}

	// MARK: Search

	private func scheduleSearch() {
		searchTask?.cancel()
		isThinking = false
		guard let index else { return }
		let query = self.query
		let category = currentCategory
		let filter = filter(for: category)

		guard isSearching else {
			directResults = browse(category, index: index)
			relatedResults = []
			relatedTerms = []
			return
		}

		// Pasted text isn't a description, so it never goes to the model.
		let useSmart = smartEnabled && smart.engine != .none && inspectedText.isEmpty
		searchTask = Task {
			try? await Task.sleep(for: .milliseconds(40))
			guard !Task.isCancelled else { return }
			let direct = await Task.detached(priority: .userInitiated) {
				index.search(query, filter: filter)
			}.value
			guard !Task.isCancelled else { return }
			directResults = direct
			relatedResults = []
			relatedTerms = []
			guard useSmart else { return }

			// Let typing settle before asking the model.
			try? await Task.sleep(for: .milliseconds(350))
			guard !Task.isCancelled else { return }
			isThinking = true
			defer { if !Task.isCancelled { isThinking = false } }
			let terms = await smart.expand(query)
			guard !Task.isCancelled else { return }
			let exclude = Set(direct)
			let related = await Task.detached(priority: .userInitiated) {
				index.related(terms: terms, filter: filter, excluding: exclude)
			}.value
			guard !Task.isCancelled else { return }
			relatedTerms = terms
			relatedResults = related
		}
	}

	private func browse(_ category: CharCategory, index: CharacterIndex) -> [Int] {
		if let list = personalList(category) { return list.compactMap { index.byScalar[$0] } }
		if let cached = browseCache[category] { return cached }
		let list = index.indices(matching: filter(for: category))
		browseCache[category] = list
		return list
	}

	// MARK: Copying

	func copy(_ text: String, label: String? = nil, recording scalar: UInt32? = nil) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
		if let scalar { recordRecent(scalar) }
		showToast("Copied \(label ?? text)")
	}

	func recordRecent(_ scalar: UInt32) {
		recents.removeAll { $0 == scalar }
		recents.insert(scalar, at: 0)
		if recents.count > 60 { recents.removeLast(recents.count - 60) }
		UserDefaults.standard.set(recents.map(Int.init), forKey: "recents")
		if currentCategory == .recents && !isSearching { scheduleSearch() }
	}

	// MARK: Favourites

	func isFavorite(_ scalar: UInt32) -> Bool { favorites.contains(scalar) }

	func toggleFavorite(_ e: CharEntry) {
		if let i = favorites.firstIndex(of: e.id) {
			favorites.remove(at: i)
			showToast("Removed \(e.glyph) from Favourites")
		} else {
			favorites.append(e.id)
			showToast("Added \(e.glyph) to Favourites")
		}
		UserDefaults.standard.set(favorites.map(Int.init), forKey: "favorites")
		if currentCategory == .favorites { scheduleSearch() }
	}

	func copyCharacter(_ e: CharEntry) {
		copy(String(Unicode.Scalar(e.id)!), recording: e.id)
	}

	/// What ⏎ acts on: the hovered character, else the selected one, else the top result.
	var returnTarget: CharEntry? {
		if let hovered = HoverState.shared.entry { return hovered }
		if let selectedEntry { return selectedEntry }
		if let first = inspectedText.first { return first }
		return (directResults.first ?? relatedResults.first).flatMap(entry)
	}

	/// ⏎: paste into the last app you used when it has a text field focused, otherwise copy.
	func pasteReturnTarget() {
		guard let e = returnTarget else { return }
		selection = e.id
		recordRecent(e.id)
		let text = String(Unicode.Scalar(e.id)!)
		Task {
			switch await Paster.paste(text) {
			case .pasted(let app): showToast("Pasted \(e.glyph) into \(app)")
			case .copied(let reason):
				showToast(reason.map { "Copied \(e.glyph) · \($0)" } ?? "Copied \(e.glyph)")
			}
		}
	}

	private func showToast(_ text: String) {
		toast = text
		toastTask?.cancel()
		toastTask = Task {
			try? await Task.sleep(for: .seconds(1.4))
			if !Task.isCancelled { toast = nil }
		}
	}
}
