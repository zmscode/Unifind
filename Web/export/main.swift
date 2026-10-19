// Writes the data the web version searches, from the same index the app builds, so the two
// never drift. Compiled together with CharacterIndex.swift and Theme.swift (`just web-data`).
//
// characters.json holds parallel arrays, one slot per named scalar in code point order:
//   cp      code point deltas from the previous entry
//   name    the name; a trailing "#" stands for the code point in hex ("CJK UNIFIED IDEOGRAPH-#")
//   block   index into `blocks`
//   gc      index into `gcs` (two-letter Unicode general category)
//   mask    CharCategory mask bits (bit n = CharCategory.allCases[n])
//   flags   1 = emoji presentation, 2 = Emoji property (drawn with U+FE0E unless 1)
import Foundation

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Web/public/data")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func generalCategoryCode(_ gc: Unicode.GeneralCategory) -> String {
	switch gc {
	case .uppercaseLetter: "Lu"
	case .lowercaseLetter: "Ll"
	case .titlecaseLetter: "Lt"
	case .modifierLetter: "Lm"
	case .otherLetter: "Lo"
	case .nonspacingMark: "Mn"
	case .spacingMark: "Mc"
	case .enclosingMark: "Me"
	case .decimalNumber: "Nd"
	case .letterNumber: "Nl"
	case .otherNumber: "No"
	case .connectorPunctuation: "Pc"
	case .dashPunctuation: "Pd"
	case .openPunctuation: "Ps"
	case .closePunctuation: "Pe"
	case .initialPunctuation: "Pi"
	case .finalPunctuation: "Pf"
	case .otherPunctuation: "Po"
	case .mathSymbol: "Sm"
	case .currencySymbol: "Sc"
	case .modifierSymbol: "Sk"
	case .otherSymbol: "So"
	case .spaceSeparator: "Zs"
	case .lineSeparator: "Zl"
	case .paragraphSeparator: "Zp"
	case .control: "Cc"
	case .format: "Cf"
	case .surrogate: "Cs"
	case .privateUse: "Co"
	case .unassigned: "Cn"
	@unknown default: "Cn"
	}
}

let index = CharacterIndex()
var blocks: [String] = []
var blockIDs: [String: Int] = [:]
var gcs: [String] = []
var gcIDs: [String: Int] = [:]
var cp: [UInt32] = []
var names: [String] = []
var blockColumn: [Int] = []
var gcColumn: [Int] = []
var masks: [UInt32] = []
var flags: [Int] = []
var previous: UInt32 = 0

for e in index.entries {
	cp.append(e.id - previous)
	previous = e.id
	let hex = String(format: "%04X", e.id)
	names.append(e.name.hasSuffix(hex) ? String(e.name.dropLast(hex.count)) + "#" : e.name)
	if blockIDs[e.block] == nil {
		blockIDs[e.block] = blocks.count
		blocks.append(e.block)
	}
	blockColumn.append(blockIDs[e.block]!)
	let gc = generalCategoryCode(e.generalCategory)
	if gcIDs[gc] == nil {
		gcIDs[gc] = gcs.count
		gcs.append(gc)
	}
	gcColumn.append(gcIDs[gc]!)
	masks.append(e.categories.rawValue)
	let props = Unicode.Scalar(e.id)!.properties
	flags.append((props.isEmojiPresentation ? 1 : 0) | (props.isEmoji ? 2 : 0))
}

struct Characters: Encodable {
	let categories: [String]
	let blocks: [String]
	let gcs: [String]
	let cp: [UInt32]
	let name: [String]
	let block: [Int]
	let gc: [Int]
	let mask: [UInt32]
	let flags: [Int]
}

let characters = Characters(
	categories: CharCategory.allCases.map(\.rawValue), blocks: blocks, gcs: gcs, cp: cp,
	name: names, block: blockColumn, gc: gcColumn, mask: masks, flags: flags)

struct ThemeJSON: Encodable {
	let name: String
	let family: String
	let isDark: Bool
	let background, text, muted, accent, smart, attribute, character, preprocessor: String
}

func hex(_ v: UInt32) -> String { String(format: "#%06x", v) }
let themes = Palette.all.map {
	ThemeJSON(
		name: $0.name, family: $0.family, isDark: $0.isDark, background: hex($0.background),
		text: hex($0.text), muted: hex($0.muted), accent: hex($0.accent), smart: hex($0.smart),
		attribute: hex($0.attribute), character: hex($0.character),
		preprocessor: hex($0.preprocessor))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
try encoder.encode(characters).write(to: out.appendingPathComponent("characters.json"))
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(themes).write(to: out.appendingPathComponent("themes.json"))
print("Wrote \(index.entries.count) characters in \(blocks.count) blocks and \(themes.count) themes to \(out.path)")
