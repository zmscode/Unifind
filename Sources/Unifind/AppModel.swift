import AppKit
import Observation

@MainActor @Observable
final class AppModel {
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
	private(set) var toast: String?

	let smart = SmartSearch()
	private var searchTask: Task<Void, Never>?
	private var toastTask: Task<Void, Never>?
	private var browseCache: [CharCategory: [Int]] = [:]

	init() {
		recents = (UserDefaults.standard.array(forKey: "recents") as? [Int])?.map(UInt32.init) ?? []
		smartEnabled = UserDefaults.standard.object(forKey: "smartEnabled") as? Bool ?? true
		hidden = CharCategory.Mask(
			rawValue: UInt32(UserDefaults.standard.integer(forKey: "hiddenCategories")))
		includeUnrenderable = UserDefaults.standard.bool(forKey: "includeUnrenderable")
	}

	var filtersActive: Bool { !hidden.isEmpty || includeUnrenderable }

	func isHidden(_ c: CharCategory) -> Bool { hidden.contains(c.mask) }
	func setHidden(_ c: CharCategory, _ hide: Bool) {
		if hide { hidden.insert(c.mask) } else { hidden.remove(c.mask) }
	}

	private func filter(for category: CharCategory) -> SearchFilter {
		SearchFilter(
			category: category, allowed: category == .recents ? Set(recents) : nil,
			hidden: hidden, includeUnrenderable: includeUnrenderable)
	}

	private func filtersChanged() {
		browseCache = [:]
		scheduleSearch()
	}

	func load() async {
		guard index == nil else { return }
		let built = await Task.detached(priority: .userInitiated) { CharacterIndex() }.value
		index = built
		scheduleSearch()
		await smart.prewarm()
	}

	var currentCategory: CharCategory { category ?? .all }
	var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

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

		let useSmart = smartEnabled && smart.engine != .none
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
		if category == .recents { return recents.compactMap { index.byScalar[$0] } }
		if let cached = browseCache[category] { return cached }
		let list = index.indices(matching: filter(for: category))
		browseCache[category] = list
		return list
	}

	// MARK: Copying

	func copy(_ text: String, label: String? = nil, recording scalar: UInt32? = nil) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
		if let scalar {
			recents.removeAll { $0 == scalar }
			recents.insert(scalar, at: 0)
			if recents.count > 60 { recents.removeLast(recents.count - 60) }
			UserDefaults.standard.set(recents.map(Int.init), forKey: "recents")
			if currentCategory == .recents && !isSearching { scheduleSearch() }
		}
		showToast("Copied \(label ?? text)")
	}

	func copyCharacter(_ e: CharEntry) {
		copy(String(Unicode.Scalar(e.id)!), recording: e.id)
	}

	func copyFirstResult() {
		guard let i = directResults.first ?? relatedResults.first, let e = entry(i) else { return }
		selection = e.id
		copyCharacter(e)
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
