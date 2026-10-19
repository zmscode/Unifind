import Foundation
import FoundationModels
import NaturalLanguage

@Generable
struct QueryExpansion {
	@Guide(
		description:
			"Words that literally appear in official Unicode character names and match what the user is looking for, most relevant first. Use singular uppercase-style English words like TRIANGLE, ARROW, HEART.",
		.count(10...20))
	var terms: [String]
}

/// Turns a loose query ("shape", "happy", "weather") into concrete words found in Unicode names.
actor SmartSearch {
	enum Engine: Sendable, Equatable { case appleIntelligence, wordEmbedding, none }

	nonisolated let engine: Engine
	private var cache: [String: [String]] = [:]

	private static let instructions = """
		You help people find Unicode characters. The user types a loose description; you reply with \
		words that appear in official Unicode character names (as in the Unicode Character Database) \
		for characters that fit the description. Think about synonyms, examples and members of the \
		category. For example, "shape" -> TRIANGLE, SQUARE, CIRCLE, DIAMOND, LOZENGE, PENTAGON, \
		HEXAGON, RECTANGLE, ELLIPSE, STAR, PARALLELOGRAM. "happy" -> SMILING, GRINNING, LAUGHING, JOY, \
		BEAMING. "weather" -> SUN, CLOUD, RAIN, SNOWFLAKE, UMBRELLA, LIGHTNING, TORNADO. \
		Give at least ten different words. Only output single words or two-word phrases that really occur in Unicode names.
		"""

	init() {
		if case .available = SystemLanguageModel.default.availability {
			engine = .appleIntelligence
		} else if NLEmbedding.wordEmbedding(for: .english) != nil {
			engine = .wordEmbedding
		} else {
			engine = .none
		}
	}

	nonisolated var unavailableReason: String? {
		switch SystemLanguageModel.default.availability {
		case .available: nil
		case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is turned off"
		case .unavailable(.deviceNotEligible): "This Mac doesn't support Apple Intelligence"
		case .unavailable(.modelNotReady): "The on-device model is still downloading"
		case .unavailable: "Apple Intelligence is unavailable"
		}
	}

	func prewarm() {
		guard engine == .appleIntelligence else { return }
		LanguageModelSession(instructions: Self.instructions).prewarm()
	}

	func expand(_ query: String) async -> [String] {
		let key = query.lowercased().trimmingCharacters(in: .whitespaces)
		guard key.count >= 2, key.contains(where: \.isLetter) else { return [] }
		if let hit = cache[key] { return hit }

		var terms: [String] = []
		if engine == .appleIntelligence {
			do {
				let session = LanguageModelSession(instructions: Self.instructions)
				let response = try await session.respond(
					to: "Find Unicode characters for: \(key)",
					generating: QueryExpansion.self,
					options: GenerationOptions(temperature: 0.2))
				terms = response.content.terms
			} catch {
				// Guardrail or model errors: fall back to the embedding below.
			}
		}
		if terms.isEmpty { terms = Self.embeddingNeighbors(key) }

		var seen = Set<String>()
		terms = terms.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter {
				!$0.isEmpty && $0 != key && !Self.tooGeneric.contains($0)
					&& seen.insert($0).inserted
			}
		cache[key] = terms
		return terms
	}

	/// Words in so many names that they'd swamp the results ("face" matches every animal face).
	private static let tooGeneric: Set<String> = [
		"face", "sign", "symbol", "letter", "mark", "small", "capital", "with", "black", "white",
		"emotion", "character", "glyph", "icon", "shape", "form", "type",
	]

	private static func embeddingNeighbors(_ query: String) -> [String] {
		guard let emb = NLEmbedding.wordEmbedding(for: .english) else { return [] }
		let words = query.split(separator: " ").map(String.init)
		return words.flatMap { w in
			emb.neighbors(for: w, maximumCount: 15).map(\.0)
		}
	}
}
