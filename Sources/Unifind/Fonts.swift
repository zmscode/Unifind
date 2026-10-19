import AppKit
import CoreText
import SwiftUI

/// Installed-font helpers: the family list for Settings, how well a family suits Unifind,
/// and which weights a character can be drawn in.
enum Fonts {
	/// Visible font families, alphabetically.
	static func families() -> [String] {
		NSFontManager.shared.availableFontFamilies
			.filter { !$0.hasPrefix(".") && $0 != "LastResort" }
			.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
	}

	/// The family's regular member, falling back to whatever it has.
	static func font(family: String, size: CGFloat = 12) -> NSFont? {
		NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
			?? NSFontManager.shared.availableMembers(ofFontFamily: family)?.first
			.flatMap { ($0.first as? String).flatMap { NSFont(name: $0, size: size) } }
	}

	struct Compatibility: Sendable {
		var covered: Int
		var total: Int
		/// Pi/dingbat fonts (Wingdings, Webdings…) draw pictures in place of ordinary letters.
		var remapsLetters: Bool

		var fraction: Double { total == 0 ? 0 : Double(covered) / Double(total) }
	}

	private static let pictureFonts: Set<String> = [
		"Webdings", "Wingdings", "Wingdings 2", "Wingdings 3", "Bodoni Ornaments",
	]

	static func compatibility(of family: String, in index: CharacterIndex) -> Compatibility? {
		guard let font = font(family: family) else { return nil }
		let ct = font as CTFont
		let set = CTFontCopyCharacterSet(ct) as CharacterSet
		var covered = 0
		var total = 0
		for e in index.entries where e.renderable {
			total += 1
			if let s = Unicode.Scalar(e.id), set.contains(s) { covered += 1 }
		}
		let traits = CTFontGetSymbolicTraits(ct).rawValue
		let symbolic =
			traits & CTFontSymbolicTraits.traitClassMask.rawValue
			== CTFontStylisticClass.classSymbolic.rawValue
		return Compatibility(
			covered: covered, total: total, remapsLetters: symbolic || pictureFonts.contains(family)
		)
	}

	// MARK: Weights

	struct WeightSample: Identifiable {
		var id: String { label }
		var label: String
		var font: Font
	}

	struct Weights {
		var family: String
		var samples: [WeightSample]
	}

	@MainActor private static var weightCache: [String: Weights] = [:]

	/// The weights of whichever font actually draws `scalar` (after fallback) in `family`.
	@MainActor static func weights(for scalar: UInt32, family: String, size: CGFloat) -> Weights? {
		let key = "\(family)|\(scalar)|\(size)"
		if let hit = weightCache[key] { return hit }
		guard let s = Unicode.Scalar(scalar) else { return nil }
		let base =
			family.isEmpty
			? NSFont.systemFont(ofSize: size)
			: (Self.font(family: family, size: size) ?? NSFont.systemFont(ofSize: size))
		let str = String(s) as CFString
		let actual = CTFontCreateForString(
			base as CTFont, str, CFRange(location: 0, length: CFStringGetLength(str)))
		let actualFamily = CTFontCopyFamilyName(actual) as String

		let result: Weights
		let systemFamily = NSFont.systemFont(ofSize: size).familyName ?? ".AppleSystemUIFont"
		if actualFamily == systemFamily {
			// The system font (SF Pro) has nine weights.
			let weights: [(String, Font.Weight)] = [
				("Ultralight", .ultraLight), ("Thin", .thin), ("Light", .light),
				("Regular", .regular),
				("Medium", .medium), ("Semibold", .semibold), ("Bold", .bold), ("Heavy", .heavy),
				("Black", .black),
			]
			result = Weights(
				family: "SF Pro",
				samples: weights.map {
					WeightSample(label: $0.0, font: .system(size: size, weight: $0.1))
				})
		} else {
			var seen = Set<Int>()
			let members = (NSFontManager.shared.availableMembers(ofFontFamily: actualFamily) ?? [])
				.compactMap { m -> (ps: String, style: String, weight: Int)? in
					guard m.count >= 4, let ps = m[0] as? String, let style = m[1] as? String,
						let weight = m[2] as? Int, let traits = m[3] as? UInt
					else { return nil }
					if traits & NSFontTraitMask.italicFontMask.rawValue != 0 { return nil }
					if traits & NSFontTraitMask.condensedFontMask.rawValue != 0 { return nil }
					return (ps, style, weight)
				}
				.sorted { $0.weight < $1.weight }
				.filter { seen.insert($0.weight).inserted }
			let samples =
				members.isEmpty
				? [
					WeightSample(
						label: "Regular",
						font: .custom(CTFontCopyPostScriptName(actual) as String, size: size))
				]
				: members.map { WeightSample(label: $0.style, font: .custom($0.ps, size: size)) }
			let displayFamily =
				actualFamily.hasPrefix(".")
				? String((CTFontCopyDisplayName(actual) as String).drop { $0 == "." })
					.replacingOccurrences(of: " UI", with: "")
				: actualFamily
			result = Weights(family: displayFamily, samples: samples)
		}
		weightCache[key] = result
		return result
	}
}
