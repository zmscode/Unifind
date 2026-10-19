// The character data exported from the Mac app's index (`just web-data`), decoded into entries.

export interface Entry {
	id: number
	name: string
	block: string
	/** Two-letter Unicode general category ("So", "Lu"…). */
	gc: string
	/** CharCategory mask bits (bit n = Category n). */
	mask: number
	emojiPresentation: boolean
	glyph: string
}

export interface CharacterFile {
	categories: string[]
	blocks: string[]
	gcs: string[]
	cp: number[]
	name: string[]
	block: number[]
	gc: number[]
	mask: number[]
	flags: number[]
}

export interface Palette {
	name: string
	family: string
	isDark: boolean
	background: string
	text: string
	muted: string
	accent: string
	smart: string
	attribute: string
	character: string
	preprocessor: string
}

/** The Mac app's CharCategory, in its declaration order (which fixes the mask bits). */
export const Category = {
	all: 0,
	recents: 1,
	emoji: 2,
	arrows: 3,
	shapes: 4,
	math: 5,
	currency: 6,
	punctuation: 7,
	letters: 8,
	numbers: 9,
	symbols: 10,
	boxDrawing: 11,
	marks: 12,
	spaces: 13,
	ideographs: 14,
	favorites: 15,
} as const
export type Category = (typeof Category)[keyof typeof Category]

export const categoryNames = [
	"All Characters",
	"Recently Copied",
	"Emoji",
	"Arrows",
	"Shapes",
	"Math",
	"Currency",
	"Punctuation",
	"Letters",
	"Numbers",
	"Symbols",
	"Box & Blocks",
	"Combining Marks",
	"Spaces & Invisible",
	"Ideographs & Syllables",
	"Favourites",
]

export const maskOf = (c: Category) => 1 << c

export function decode(file: CharacterFile): Entry[] {
	if (file.categories.join("|") !== categoryNames.join("|")) {
		console.warn("Category list differs from the app's; rerun `just web-data`.")
	}
	const entries: Entry[] = new Array(file.cp.length)
	let id = 0
	for (let i = 0; i < file.cp.length; i++) {
		id += file.cp[i]
		let name = file.name[i]
		if (name.endsWith("#")) name = name.slice(0, -1) + id.toString(16).toUpperCase().padStart(4, "0")
		const gc = file.gcs[file.gc[i]]
		const flags = file.flags[i]
		const emojiPresentation = (flags & 1) !== 0
		const ch = String.fromCodePoint(id)
		let glyph: string
		if (gc === "Mn" || gc === "Me" || gc === "Mc") glyph = "\u25CC" + ch
		else glyph = emojiPresentation || (flags & 2) === 0 ? ch : ch + "\uFE0E"
		entries[i] = { id, name, block: file.blocks[file.block[i]], gc, mask: file.mask[i], emojiPresentation, glyph }
	}
	return entries
}

export const codepoint = (id: number) => "U+" + id.toString(16).toUpperCase().padStart(4, "0")

/** Like Foundation's `capitalized`: "BLACK UP-POINTING TRIANGLE" -> "Black Up-Pointing Triangle". */
export function displayName(name: string): string {
	return name.toLowerCase().replace(/(^|[ -])([^a-z]*)([a-z])/g, (_, sep, lead, letter) => sep + lead + letter.toUpperCase())
}

/** Spaces and format characters draw nothing, so tiles show an abbreviation instead. */
export const isInvisible = (e: Entry) => ["Zs", "Zl", "Zp", "Cf", "Cc"].includes(e.gc)

/** "ZERO WIDTH JOINER" -> "ZWJ", "SPACE" -> "SPA". */
export function abbreviation(e: Entry): string {
	const words = e.name.split(/[ -]/).filter(Boolean)
	if (words.length === 1) return words[0].slice(0, 3)
	return words.map((w) => w[0]).slice(0, 4).join("")
}

export const generalCategoryLabel: Record<string, string> = {
	Lu: "Uppercase Letter",
	Ll: "Lowercase Letter",
	Lt: "Titlecase Letter",
	Lm: "Modifier Letter",
	Lo: "Letter",
	Mn: "Nonspacing Mark",
	Mc: "Spacing Mark",
	Me: "Enclosing Mark",
	Nd: "Decimal Digit",
	Nl: "Letter Number",
	No: "Number",
	Pc: "Connector Punctuation",
	Pd: "Dash",
	Ps: "Opening Punctuation",
	Pe: "Closing Punctuation",
	Pi: "Initial Quote",
	Pf: "Final Quote",
	Po: "Punctuation",
	Sm: "Math Symbol",
	Sc: "Currency Symbol",
	Sk: "Modifier Symbol",
	So: "Symbol",
	Zs: "Space",
	Zl: "Line Separator",
	Zp: "Paragraph Separator",
	Cc: "Control",
	Cf: "Format",
}
