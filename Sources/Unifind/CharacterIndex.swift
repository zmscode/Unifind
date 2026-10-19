import CoreText
import Foundation

struct CharEntry: Sendable, Identifiable {
	let id: UInt32
	let name: String
	let block: String
	let generalCategory: Unicode.GeneralCategory
	let categories: CharCategory.Mask
	let glyph: String
	/// Whether some installed font has a glyph for this scalar.
	let renderable: Bool

	var codepoint: String { String(format: "U+%04X", id) }
	var displayName: String { name.capitalized }

	/// Spaces and format characters draw nothing, so tiles show an abbreviation instead.
	var isInvisible: Bool {
		switch generalCategory {
		case .spaceSeparator, .lineSeparator, .paragraphSeparator, .format, .control: true
		default: false
		}
	}

	/// "ZERO WIDTH JOINER" -> "ZWJ", "SPACE" -> "SPA".
	var abbreviation: String {
		let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
		if words.count == 1 { return String(words[0].prefix(3)) }
		return String(words.compactMap(\.first).prefix(4))
	}
}

/// What a search or browse is allowed to return.
struct SearchFilter: Sendable {
	var category: CharCategory = .all
	/// Restricts results to these scalars (used for Recently Copied).
	var allowed: Set<UInt32>?
	/// Categories to hide everywhere except when that category is the one being browsed.
	var hidden: CharCategory.Mask = []
	var includeUnrenderable = false

	func accepts(_ e: CharEntry) -> Bool {
		if let allowed { return allowed.contains(e.id) }
		guard includeUnrenderable || e.renderable else { return false }
		guard e.categories.contains(category.mask) else { return false }
		return e.categories.intersection(hidden.subtracting(category.mask)).isEmpty
	}
}

enum CharCategory: String, CaseIterable, Identifiable, Sendable {
	case all = "All Characters"
	case recents = "Recently Copied"
	case emoji = "Emoji"
	case arrows = "Arrows"
	case shapes = "Shapes"
	case math = "Math"
	case currency = "Currency"
	case punctuation = "Punctuation"
	case letters = "Letters"
	case numbers = "Numbers"
	case symbols = "Symbols"
	case boxDrawing = "Box & Blocks"
	case marks = "Combining Marks"
	case spaces = "Spaces & Invisible"
	case ideographs = "Ideographs & Syllables"
	// Last, so the bit masks of the cases above (saved as hidden filters) don't shift.
	case favorites = "Favourites"

	var id: String { rawValue }

	/// The Unicode categories, without All, Recently Copied and Favourites.
	static var unicodeCategories: [CharCategory] {
		allCases.filter { ![.all, .recents, .favorites].contains($0) }
	}

	var systemImage: String {
		switch self {
		case .all: "square.grid.3x3"
		case .recents: "clock"
		case .emoji: "face.smiling"
		case .arrows: "arrow.up.right"
		case .shapes: "triangle"
		case .math: "function"
		case .currency: "dollarsign"
		case .punctuation: "quote.opening"
		case .letters: "textformat"
		case .numbers: "number"
		case .symbols: "star"
		case .boxDrawing: "square.split.2x2"
		case .marks: "character.cursor.ibeam"
		case .spaces: "space"
		case .ideographs: "character.ja"
		case .favorites: "star"
		}
	}

	struct Mask: OptionSet, Sendable {
		let rawValue: UInt32
	}

	var mask: Mask { Mask(rawValue: 1 << UInt32(Self.allCases.firstIndex(of: self)!)) }

	static let shapeWords: Set<Substring> = [
		"TRIANGLE", "SQUARE", "CIRCLE", "DIAMOND", "LOZENGE", "RECTANGLE", "PENTAGON",
		"HEXAGON", "OCTAGON", "ELLIPSE", "STAR", "PARALLELOGRAM", "TRAPEZIUM", "CROSS",
		"HEART", "SPADE", "CLUB", "SEGMENT", "SECTOR", "ARC", "QUADRANT", "OVAL", "RING",
	]

	/// Every category (other than `.all`/`.recents`) that a scalar belongs to.
	static func mask(for scalar: Unicode.Scalar, name: String, block: String, isEmoji: Bool) -> Mask
	{
		var m: Mask = CharCategory.all.mask
		let gc = scalar.properties.generalCategory
		let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
		let isIdeograph =
			name.hasPrefix("CJK ") || name.hasPrefix("HANGUL SYLLABLE")
			|| name.contains("IDEOGRAPH") || name.hasPrefix("TANGUT")
			|| name.hasPrefix("YI SYLLABLE")
			|| name.hasPrefix("KHITAN") || name.hasPrefix("NUSHU")

		if isEmoji { m.insert(CharCategory.emoji.mask) }
		if words.contains(where: { $0.hasPrefix("ARROW") }) { m.insert(CharCategory.arrows.mask) }
		if gc == .mathSymbol || name.hasPrefix("MATHEMATICAL") { m.insert(CharCategory.math.mask) }
		if gc == .currencySymbol { m.insert(CharCategory.currency.mask) }
		if name.hasPrefix("BOX DRAWINGS") || name.hasPrefix("BRAILLE PATTERN")
			|| words.contains("BLOCK") || words.contains("SHADE") || words.contains("SEXTANT")
			|| words.contains("OCTANT")
		{
			m.insert(CharCategory.boxDrawing.mask)
		}
		if block.hasPrefix("Geometric Shapes")
			|| ([.mathSymbol, .otherSymbol, .modifierSymbol].contains(gc)
				&& words.contains(where: {
					shapeWords.contains($0) || shapeWords.contains($0.dropLast())
				}))
		{
			m.insert(CharCategory.shapes.mask)
		}

		switch gc {
		case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
			m.insert(isIdeograph ? CharCategory.ideographs.mask : CharCategory.letters.mask)
		case .decimalNumber, .letterNumber, .otherNumber:
			m.insert(CharCategory.numbers.mask)
		case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
			.initialPunctuation, .finalPunctuation, .otherPunctuation:
			m.insert(CharCategory.punctuation.mask)
		case .otherSymbol, .modifierSymbol:
			if !isEmoji { m.insert(CharCategory.symbols.mask) }
		case .nonspacingMark, .spacingMark, .enclosingMark:
			m.insert(CharCategory.marks.mask)
		case .spaceSeparator, .lineSeparator, .paragraphSeparator, .format, .control:
			m.insert(CharCategory.spaces.mask)
		default: break
		}
		return m
	}
}

/// Immutable, thread-safe index over every named Unicode scalar.
final class CharacterIndex: Sendable {
	let entries: [CharEntry]
	let byScalar: [UInt32: Int]
	/// Lowercased name word -> entry indices containing it.
	private let postings: [String: [Int32]]
	/// Vocabulary as UTF-8 byte arrays for fast fuzzy matching.
	private let vocab: [(word: String, bytes: [UInt8])]
	/// Same, for Unicode block names ("Geometric Shapes", "Arrows", ...).
	private let blockPostings: [String: [Int32]]
	private let blockVocab: [(word: String, bytes: [UInt8])]
	private let wordCounts: [UInt8]
	/// Lowercased ASCII names for fzf-style subsequence matching.
	private let nameBytes: [[UInt8]]

	init() {
		var entries: [CharEntry] = []
		entries.reserveCapacity(160_000)
		var postings: [String: [Int32]] = [:]
		var blockPostings: [String: [Int32]] = [:]
		var wordCounts: [UInt8] = []
		let fontCoverage = Self.installedFontCoverage()
		var blockNames: [Int32: (name: String, words: [String])] = [:]

		for value in UInt32(0x20)...0x10FFFF {
			guard let scalar = Unicode.Scalar(value) else { continue }
			let props = scalar.properties
			switch props.generalCategory {
			case .unassigned, .surrogate, .privateUse: continue
			default: break
			}
			let name =
				props.name ?? props.nameAlias
				?? (props.generalCategory == .control ? nil : String(format: "UNNAMED %04X", value))
			guard let name else { continue }

			let isEmoji = props.isEmojiPresentation
			let glyph: String
			switch props.generalCategory {
			case .nonspacingMark, .enclosingMark, .spacingMark: glyph = "\u{25CC}" + String(scalar)
			default:
				glyph = isEmoji || !props.isEmoji ? String(scalar) : String(scalar) + "\u{FE0E}"
			}

			let blockCode = ICU.blockCode(value)
			if blockNames[blockCode] == nil {
				let n = ICU.blockName(blockCode)
				blockNames[blockCode] = (n, n.lowercased().split(separator: " ").map(String.init))
			}
			let block = blockNames[blockCode]!

			let idx = Int32(entries.count)
			let words = name.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" })
			for w in Set(words) where !Self.isHexCode(w) {
				postings[String(w), default: []].append(idx)
			}
			for w in block.words { blockPostings[w, default: []].append(idx) }
			wordCounts.append(UInt8(min(words.count, 255)))
			entries.append(
				CharEntry(
					id: value, name: name, block: block.name,
					generalCategory: props.generalCategory,
					categories: CharCategory.mask(
						for: scalar, name: name, block: block.name, isEmoji: isEmoji),
					glyph: glyph,
					renderable: isEmoji || fontCoverage.contains(scalar)))
		}

		self.entries = entries
		self.postings = postings
		self.blockPostings = blockPostings
		self.wordCounts = wordCounts
		self.nameBytes = entries.map { Array($0.name.lowercased().utf8) }
		self.vocab = postings.keys.map { ($0, Array($0.utf8)) }
		self.blockVocab = blockPostings.keys.map { ($0, Array($0.utf8)) }
		var byScalar: [UInt32: Int] = [:]
		byScalar.reserveCapacity(entries.count)
		for (i, e) in entries.enumerated() { byScalar[e.id] = i }
		self.byScalar = byScalar
	}

	private static func isHexCode(_ w: Substring) -> Bool {
		w.count >= 4 && w.allSatisfy(\.isHexDigit) && w.contains(where: \.isNumber)
	}

	/// Union of every installed font's character set (~0.15s), so we can skip "?" boxes.
	private static func installedFontCoverage() -> CharacterSet {
		let collection = CTFontCollectionCreateFromAvailableFonts(nil)
		let descriptors =
			CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
		let union = NSMutableCharacterSet()
		for d in descriptors {
			let family =
				CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String ?? ""
			if family.contains("LastResort") { continue }
			if let cs = CTFontDescriptorCopyAttribute(d, kCTFontCharacterSetAttribute)
				as? CharacterSet
			{
				union.formUnion(with: cs)
			}
		}
		return union as CharacterSet
	}

	func indices(matching filter: SearchFilter) -> [Int] {
		entries.indices.filter { filter.accepts(entries[$0]) }
	}

	// MARK: - Direct (fuzzy) search

	/// Returns entry indices ordered by relevance. Every query token must match some word of the
	/// name or of the character's Unicode block name.
	func search(_ query: String, filter: SearchFilter = SearchFilter()) -> [Int] {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return [] }
		var pinned: [Int] = []

		// The literal character itself, e.g. pasting "→".
		if trimmed.unicodeScalars.count <= 2, let s = trimmed.unicodeScalars.first,
			let i = byScalar[s.value]
		{
			pinned.append(i)
		}
		// Codepoint lookups: "U+2192", "0x2192", "2192".
		if let i = codepointMatch(trimmed), !pinned.contains(i) { pinned.append(i) }

		let tokens = trimmed.lowercased()
			.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
			.map(String.init)
		var scored = tokens.isEmpty ? [] : rank(tokens: tokens)
		let compact = Array(tokens.joined().utf8)
		if compact.count >= 3 {
			let seen = Set(scored.map(\.0))
			scored += initialsMatches(compact, filter: filter).filter { !seen.contains($0.0) }
			scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
		}
		let ranked = scored.map(\.0)
		let pinnedSet = Set(pinned)
		// Pinned (literal / code point) matches bypass the renderability filter.
		var exact = filter
		exact.includeUnrenderable = true
		return pinned.filter { exact.accepts(entries[$0]) }
			+ ranked.filter { !pinnedSet.contains($0) && filter.accepts(entries[$0]) }
	}

	// MARK: - fzf-style subsequence matching

	/// Names the query spells as a subsequence where every run of letters starts at a word
	/// boundary, e.g. "bupt" -> BLACK UP-POINTING TRIANGLE, "rarr" -> RIGHTWARDS ARROW.
	private func initialsMatches(_ query: [UInt8], filter: SearchFilter) -> [(Int, Float)] {
		var hits: [(index: Int, runs: Int)] = []
		let skip = CharCategory.ideographs.mask
		for (i, name) in nameBytes.enumerated() {
			let e = entries[i]
			guard !e.categories.contains(skip), filter.accepts(e), name.count >= query.count,
				name[0] == query[0] || name.contains(query[0]),
				let runs = Self.boundaryRuns(query, name)
			else { continue }
			hits.append((i, runs))
		}
		// A multi-word acronym beats a one-letter typo; fewer runs means a tighter match.
		let minRuns = hits.map(\.runs).min() ?? 0
		return hits.filter { $0.runs <= minRuns + 1 }.map { hit in
			let base: Float =
				hit.runs >= 3 ? 0.6 - 0.04 * Float(hit.runs - minRuns) : hit.runs == 2 ? 0.45 : 0.3
			return (hit.index, base + quality(hit.index, symbolBonus: 0.15))
		}
	}

	/// Fewest runs needed to match `q` in `name` with each run starting at a word start.
	static func boundaryRuns(_ q: [UInt8], _ name: [UInt8]) -> Int? {
		var best: Int?
		func isBoundary(_ p: Int) -> Bool { p == 0 || name[p - 1] == 32 || name[p - 1] == 45 }
		func search(_ qi: Int, _ ni: Int, _ runs: Int) {
			if let b = best, runs >= b { return }
			if qi == q.count {
				best = runs
				return
			}
			// Continue the current run.
			if qi > 0, ni < name.count, name[ni] == q[qi] { search(qi + 1, ni + 1, runs) }
			// Or start a new run at a later word.
			var p = ni
			while p < name.count {
				if name[p] == q[qi], isBoundary(p), qi == 0 || p != ni {
					search(qi + 1, p + 1, runs + 1)
				}
				p += 1
			}
		}
		search(0, 0, 0)
		return best
	}

	private func codepointMatch(_ q: String) -> Int? {
		var hex = Substring(q.uppercased())
		if hex.hasPrefix("U+") || hex.hasPrefix("0X") {
			hex = hex.dropFirst(2)
		} else if hex.count < 4 {
			return nil
		}
		guard (1...6).contains(hex.count), let v = UInt32(hex, radix: 16) else { return nil }
		return byScalar[v]
	}

	private func rank(tokens: [String]) -> [(Int, Float)] {
		var total = [Float](repeating: 0, count: entries.count)
		var hits = [UInt8](repeating: 0, count: entries.count)
		var touched: [Int32] = []

		var best = [Float](repeating: 0, count: entries.count)
		var tokenTouched: [Int32] = []
		for token in tokens {
			let tb = Array(token.utf8)
			for (source, words, weight) in [
				(postings, vocab, Float(1)), (blockPostings, blockVocab, 0.8),
			] {
				for (word, bytes) in words {
					let s = Self.wordScore(token: tb, word: bytes) * weight
					guard s > 0, let list = source[word] else { continue }
					for i in list where best[Int(i)] < s {
						if best[Int(i)] == 0 { tokenTouched.append(i) }
						best[Int(i)] = s
					}
				}
			}
			for i in tokenTouched {
				let ii = Int(i)
				if hits[ii] == 0 { touched.append(i) }
				total[ii] += best[ii]
				hits[ii] += 1
				best[ii] = 0
			}
			tokenTouched.removeAll(keepingCapacity: true)
		}

		let need = UInt8(tokens.count)
		var results: [(Int, Float)] = []
		for i in touched where hits[Int(i)] >= need {
			let ii = Int(i)
			results.append((ii, total[ii] / Float(need) + quality(ii, symbolBonus: 0.15)))
		}
		results.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
		return results
	}

	/// 0...1 similarity between a query token and one name word.
	static func wordScore(token: [UInt8], word: [UInt8]) -> Float {
		let t = token.count
		let w = word.count
		if t == w && token == word { return 1 }
		if t < w && word.starts(with: token) {
			return t == 1 ? 0 : 0.7 + 0.2 * Float(t) / Float(w)
		}
		if t >= 3 && w > t && contains(word, token) { return 0.4 }
		if t >= 4 && abs(t - w) <= 2 {
			let maxDist = t >= 7 ? 2 : 1
			switch boundedDistance(token, word, max: maxDist) {
			case 1: return 0.5
			case 2 where maxDist >= 2: return 0.3
			default: break
			}
		}
		return 0
	}

	private static func contains(_ hay: [UInt8], _ needle: [UInt8]) -> Bool {
		guard needle.count <= hay.count else { return false }
		for start in 0...(hay.count - needle.count) {
			var ok = true
			for j in 0..<needle.count where hay[start + j] != needle[j] {
				ok = false
				break
			}
			if ok { return true }
		}
		return false
	}

	/// Optimal-string-alignment distance, returning `max + 1` once it's exceeded.
	private static func boundedDistance(_ a: [UInt8], _ b: [UInt8], max: Int) -> Int {
		let n = a.count
		let m = b.count
		var prev2 = [Int](repeating: 0, count: m + 1)
		var prev = Array(0...m)
		var cur = [Int](repeating: 0, count: m + 1)
		for i in 1...n {
			cur[0] = i
			var rowMin = cur[0]
			for j in 1...m {
				let cost = a[i - 1] == b[j - 1] ? 0 : 1
				var v = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
				if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
					v = Swift.min(v, prev2[j - 2] + 1)
				}
				cur[j] = v
				rowMin = Swift.min(rowMin, v)
			}
			if rowMin > max { return max + 1 }
			(prev2, prev, cur) = (prev, cur, prev2)
		}
		return prev[m]
	}

	// MARK: - Related (concept) search

	/// Entries whose names contain any of `terms` (each term's words must all appear).
	/// Earlier terms rank higher. Plural/singular variants are tolerated.
	func related(terms: [String], filter: SearchFilter = SearchFilter(), excluding: Set<Int> = [])
		-> [Int]
	{
		var score: [Int: Float] = [:]
		for (rank, term) in terms.enumerated() {
			let words = term.lowercased()
				.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
				.map(String.init)
			guard !words.isEmpty else { continue }
			var matched: Set<Int32>?
			for w in words {
				let list = Set(variants(of: w).flatMap { postings[$0] ?? [] })
				matched = matched.map { $0.intersection(list) } ?? list
				if matched!.isEmpty { break }
			}
			let headVariants = Set(variants(of: words.last!).map { $0.uppercased() })
			let weight = 1 / (1 + Float(rank) * 0.08)
			for i in matched ?? [] {
				let ii = Int(i)
				guard !excluding.contains(ii), filter.accepts(entries[ii]) else { continue }
				// "WHITE SQUARE" is a square; "SQUARE ROOT" is not.
				let w = weight * (isHeadNoun(headVariants, in: entries[ii].name) ? 1 : 0.45)
				if let s = score[ii] {
					score[ii] = max(s, w) + 0.05  // small boost for matching several terms
				} else {
					score[ii] = w + quality(ii, symbolBonus: 0.4)
				}
			}
		}
		return
			score
			.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
			.map(\.key)
	}

	/// The word a Unicode name is "about": the last word, or the one before WITH/CONTAINING/etc.
	private func isHeadNoun(_ variants: Set<String>, in name: String) -> Bool {
		let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
		guard let at = words.firstIndex(where: { variants.contains(String($0)) }) else {
			return false
		}
		let next = words.index(after: at)
		return next == words.endIndex || Self.headTerminators.contains(words[next])
	}

	private static let headTerminators: Set<Substring> = [
		"WITH", "CONTAINING", "INSIDE", "ABOVE", "BELOW", "OVER", "UNDER", "AND", "OPERATOR",
		"SHAPE", "SYMBOL", "SIGN", "FORMAT", "ORNAMENT",
	]

	/// Favor symbols and short names over letters/ideographs that merely mention a word.
	private func quality(_ i: Int, symbolBonus: Float) -> Float {
		let e = entries[i]
		var b = 0.5 / Float(max(1, Int(wordCounts[i])))
		switch e.generalCategory {
		case .otherSymbol, .mathSymbol: b += symbolBonus
		case .modifierSymbol, .currencySymbol, .otherPunctuation: b += symbolBonus * 0.4
		default: break
		}
		if e.categories.contains(CharCategory.ideographs.mask) || e.block.contains("CJK")
			|| e.block.contains("Kangxi")
		{
			b -= 0.3
		}
		if e.id <= 0xFFFF || e.categories.contains(CharCategory.emoji.mask) { b += 0.05 }
		return b
	}

	private func variants(of w: String) -> [String] {
		var v = [w]
		if w.hasSuffix("ies") { v.append(String(w.dropLast(3)) + "y") }
		if w.hasSuffix("es") { v.append(String(w.dropLast(2))) }
		if w.hasSuffix("s") { v.append(String(w.dropLast())) } else { v.append(w + "s") }
		return v
	}
}

/// Unicode block lookup via the ICU that ships with macOS (Swift doesn't expose blocks).
enum ICU {
	private typealias BlockCodeFn = @convention(c) (UInt32) -> Int32
	private typealias PropertyValueNameFn =
		@convention(c) (Int32, Int32, Int32) -> UnsafePointer<CChar>?
	nonisolated(unsafe) private static let handle = dlopen("/usr/lib/libicucore.dylib", RTLD_NOW)
	private static let getBlock = dlsym(handle, "ublock_getCode").map {
		unsafeBitCast($0, to: BlockCodeFn.self)
	}
	private static let propertyValueName = dlsym(
		handle, "u_getPropertyValueName"
	).map {
		unsafeBitCast($0, to: PropertyValueNameFn.self)
	}
	private static let blockProperty: Int32 = 0x1001  // UCHAR_BLOCK
	private static let longName: Int32 = 1  // U_LONG_PROPERTY_NAME

	static func blockCode(_ scalar: UInt32) -> Int32 { getBlock?(scalar) ?? 0 }

	static func blockName(_ code: Int32) -> String {
		guard let p = propertyValueName?(blockProperty, code, longName) else { return "Unknown" }
		return String(cString: p).replacingOccurrences(of: "_", with: " ")
	}
}
