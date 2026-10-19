import Foundation
import Testing

@testable import Unifind

@Suite struct SearchTests {
	static let index = CharacterIndex()

	private func top(_ q: String, _ n: Int = 5, in c: CharCategory = .all) -> [String] {
		let filter = SearchFilter(category: c, includeUnrenderable: true)
		return Self.index.search(q, filter: filter).prefix(n).map { Self.index.entries[$0].name }
	}

	@Test func exactWordRanksFirst() {
		#expect(top("snowman", 1) == ["SNOWMAN"])
		#expect(top("right arrow", 5).contains("RIGHTWARDS ARROW"))
		#expect(Self.index.search("heart").count < 500)
	}

	@Test func typosAndPrefixes() {
		#expect(top("snowmen", 3).contains("SNOWMAN"))
		#expect(top("triangel", 10).contains { $0.contains("TRIANGLE") })
		#expect(top("lozen", 3).contains { $0.contains("LOZENGE") })
	}

	@Test func initials() {
		#expect(top("bupt", 3).contains("BLACK UP-POINTING TRIANGLE"))
		#expect(top("rarr", 5).contains("RIGHTWARDS ARROW"))
		#expect(
			CharacterIndex.boundaryRuns(
				Array("bupt".utf8), Array("black up-pointing triangle".utf8)) == 3)
		#expect(CharacterIndex.boundaryRuns(Array("lack".utf8), Array("black".utf8)) == nil)
	}

	@Test func literalAndCodepoint() {
		#expect(top("→", 1) == ["RIGHTWARDS ARROW"])
		#expect(top("U+2603", 1) == ["SNOWMAN"])
	}

	@Test func categories() {
		let shapes = Self.index.indices(matching: SearchFilter(category: .shapes))
			.map { Self.index.entries[$0].name }
		#expect(shapes.contains("BLACK UP-POINTING TRIANGLE"))
		#expect(top("euro", 3, in: .currency).contains("EURO SIGN"))
	}

	@Test func relatedTerms() {
		let r = Self.index.related(terms: ["triangle", "squares"])
		#expect(r.count > 50)
		#expect(!r.prefix(20).map { Self.index.entries[$0].name }.contains("SQUARE ROOT"))
	}

	@Test func blocksAndFonts() {
		#expect(top("shape", 200).contains("BLACK UP-POINTING TRIANGLE"))
		let e = Self.index.entries[Self.index.byScalar[0x25B2]!]
		#expect(e.block == "Geometric Shapes" && e.renderable)
		let noEmoji = SearchFilter(hidden: CharCategory.emoji.mask)
		#expect(
			!Self.index.search("heart", filter: noEmoji).contains {
				Self.index.entries[$0].id == 0x1F496
			})
	}

	@MainActor @Test func fontWeightsAndCompatibility() {
		let a = Fonts.weights(for: 0x41, family: "", size: 30)
		#expect(a?.family == "SF Pro" && a?.samples.count == 9)
		let emoji = Fonts.weights(for: 0x1F600, family: "", size: 30)
		#expect(emoji?.samples.count == 1)
		let helvetica = Fonts.weights(for: 0x41, family: "Helvetica Neue", size: 30)
		#expect((helvetica?.samples.count ?? 0) > 3)
		print(
			"WEIGHTS", a!.family, emoji!.family, helvetica!.family, helvetica!.samples.map(\.label))
		let c = Fonts.compatibility(of: "Helvetica", in: Self.index)!
		#expect(!c.remapsLetters && c.covered > 100)
		let wd = Fonts.compatibility(of: "Webdings", in: Self.index)
		print(
			"COMPAT helvetica", c.covered, "webdings",
			wd.map { "\($0.covered) remaps=\($0.remapsLetters)" } ?? "n/a")
	}

	@Test func printSamples() async {
		let ix = Self.index
		print("renderable:", ix.entries.filter(\.renderable).count, "of", ix.entries.count)
		for q in ["shape", "heart", "arow", "right arrow", "bupt", "wsq"] {
			let t0 = Date()
			let r = ix.search(q)
			print("TIME", q, Date().timeIntervalSince(t0))
			print(
				"DIRECT", q, r.count,
				r.prefix(40).map { ix.entries[$0].glyph }.joined(separator: " "))
		}
		let smart = SmartSearch()
		for q in ["shape", "happy", "weather", "music", "animal"] {
			let terms = await smart.expand(q)
			let rel = ix.related(terms: terms, excluding: Set(ix.search(q)))
			print(
				"RELATED", q, terms,
				rel.prefix(40).map { ix.entries[$0].glyph }.joined(separator: " "))
		}
	}
}
