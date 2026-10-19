// A port of CharacterIndex.swift's search: tokenised fuzzy word matching over names and block
// names, fzf-style initials, literal characters and code points, and related-term ranking.
import { Category, maskOf, type Entry } from "./data.ts"

/** What a search or browse is allowed to return. */
export interface SearchFilter {
	category: Category
	/** Restricts results to these scalars (Recently Copied, Favourites). */
	allowed?: Set<number>
	/** Category mask bits hidden everywhere except when that category is being browsed. */
	hidden: number
	includeUnrenderable: boolean
}

export const defaultFilter = (): SearchFilter => ({ category: Category.all, hidden: 0, includeUnrenderable: false })

/** Whether the browser can draw a scalar; `undefined` while it hasn't been checked yet. */
export type Renderability = (id: number) => boolean | undefined

const ideographMask = maskOf(Category.ideographs)
const emojiMask = maskOf(Category.emoji)
const splitWords = /[ -]/
const nonWord = /[^\p{L}\p{N}]+/u

export class CharacterIndex {
	readonly entries: Entry[]
	readonly byScalar = new Map<number, number>()
	/** Lowercased name word -> entry indices containing it. */
	private postings = new Map<string, number[]>()
	private vocab: string[]
	/** Same, for Unicode block names ("Geometric Shapes", "Arrows", ...). */
	private blockPostings = new Map<string, number[]>()
	private blockVocab: string[]
	private wordCounts: Uint8Array
	/** Lowercased ASCII names for fzf-style subsequence matching. */
	private lowerNames: string[]
	renderable: Renderability = () => undefined

	constructor(entries: Entry[]) {
		this.entries = entries
		this.wordCounts = new Uint8Array(entries.length)
		this.lowerNames = new Array(entries.length)
		const blockWords = new Map<string, string[]>()
		entries.forEach((e, idx) => {
			this.byScalar.set(e.id, idx)
			const lower = e.name.toLowerCase()
			this.lowerNames[idx] = lower
			const words = lower.split(splitWords).filter(Boolean)
			for (const w of new Set(words)) {
				if (isHexCode(w)) continue
				push(this.postings, w, idx)
			}
			let bw = blockWords.get(e.block)
			if (!bw) blockWords.set(e.block, (bw = e.block.toLowerCase().split(" ").filter(Boolean)))
			for (const w of bw) push(this.blockPostings, w, idx)
			this.wordCounts[idx] = Math.min(words.length, 255)
		})
		this.vocab = [...this.postings.keys()]
		this.blockVocab = [...this.blockPostings.keys()]
	}

	accepts(e: Entry, f: SearchFilter): boolean {
		if (f.allowed) return f.allowed.has(e.id)
		if (!f.includeUnrenderable && this.renderable(e.id) === false) return false
		const cat = maskOf(f.category)
		if ((e.mask & cat) !== cat) return false
		return (e.mask & (f.hidden & ~cat)) === 0
	}

	indices(f: SearchFilter): number[] {
		const out: number[] = []
		for (let i = 0; i < this.entries.length; i++) if (this.accepts(this.entries[i], f)) out.push(i)
		return out
	}

	// MARK: Direct (fuzzy) search

	/** Entry indices ordered by relevance. Every query token must match some word of the name or
	 * of the character's Unicode block name. */
	search(query: string, filter: SearchFilter = defaultFilter()): number[] {
		const trimmed = trimSpaces(query)
		if (!trimmed) return []
		const pinned: number[] = []

		// The literal character itself, e.g. pasting "→".
		const scalars = [...trimmed]
		if (scalars.length <= 2) {
			const i = this.byScalar.get(scalars[0].codePointAt(0)!)
			if (i !== undefined) pinned.push(i)
		}
		// Code point lookups: "U+2192", "0x2192", "2192".
		const cp = this.codepointMatch(trimmed)
		if (cp !== undefined && !pinned.includes(cp)) pinned.push(cp)

		const tokens = trimmed.toLowerCase().split(nonWord).filter(Boolean)
		let scored = tokens.length ? this.rank(tokens) : []
		const compact = tokens.join("")
		if (compact.length >= 3) {
			const seen = new Set(scored.map((s) => s[0]))
			scored = scored.concat(this.initialsMatches(compact, filter).filter((s) => !seen.has(s[0])))
			scored.sort(byScore)
		}
		const pinnedSet = new Set(pinned)
		// Pinned (literal / code point) matches bypass the renderability filter.
		const exact = { ...filter, includeUnrenderable: true }
		return pinned
			.filter((i) => this.accepts(this.entries[i], exact))
			.concat(scored.map((s) => s[0]).filter((i) => !pinnedSet.has(i) && this.accepts(this.entries[i], filter)))
	}

	// MARK: fzf-style subsequence matching

	/** Names the query spells as a subsequence where every run of letters starts at a word
	 * boundary, e.g. "bupt" -> BLACK UP-POINTING TRIANGLE, "rarr" -> RIGHTWARDS ARROW. */
	private initialsMatches(query: string, filter: SearchFilter): [number, number][] {
		const hits: [number, number][] = []
		const q0 = query[0]
		for (let i = 0; i < this.lowerNames.length; i++) {
			const name = this.lowerNames[i]
			const e = this.entries[i]
			if ((e.mask & ideographMask) !== 0 || name.length < query.length) continue
			if (name[0] !== q0 && !name.includes(q0)) continue
			if (!this.accepts(e, filter)) continue
			const runs = boundaryRuns(query, name)
			if (runs !== undefined) hits.push([i, runs])
		}
		// A multi-word acronym beats a one-letter typo; fewer runs means a tighter match.
		let minRuns = Infinity
		for (const h of hits) minRuns = Math.min(minRuns, h[1])
		return hits
			.filter((h) => h[1] <= minRuns + 1)
			.map(([i, runs]) => {
				const base = runs >= 3 ? 0.6 - 0.04 * (runs - minRuns) : runs === 2 ? 0.45 : 0.3
				return [i, base + this.quality(i, 0.15)]
			})
	}

	private codepointMatch(q: string): number | undefined {
		let hex = q.toUpperCase()
		if (hex.startsWith("U+") || hex.startsWith("0X")) hex = hex.slice(2)
		else if (hex.length < 4) return undefined
		if (!/^[0-9A-F]{1,6}$/.test(hex)) return undefined
		return this.byScalar.get(parseInt(hex, 16))
	}

	private rank(tokens: string[]): [number, number][] {
		const n = this.entries.length
		const total = new Float64Array(n)
		const hits = new Uint8Array(n)
		const best = new Float64Array(n)
		const touched: number[] = []
		const tokenTouched: number[] = []
		const sources: [Map<string, number[]>, string[], number][] = [
			[this.postings, this.vocab, 1],
			[this.blockPostings, this.blockVocab, 0.8],
		]
		for (const token of tokens) {
			for (const [source, words, weight] of sources) {
				for (const word of words) {
					const s = wordScore(token, word) * weight
					if (s <= 0) continue
					for (const i of source.get(word)!) {
						if (best[i] < s) {
							if (best[i] === 0) tokenTouched.push(i)
							best[i] = s
						}
					}
				}
			}
			for (const i of tokenTouched) {
				if (hits[i] === 0) touched.push(i)
				total[i] += best[i]
				hits[i]++
				best[i] = 0
			}
			tokenTouched.length = 0
		}
		const need = tokens.length
		const results: [number, number][] = []
		for (const i of touched) {
			if (hits[i] >= need) results.push([i, total[i] / need + this.quality(i, 0.15)])
		}
		return results.sort(byScore)
	}

	// MARK: Related (concept) search

	/** Entries whose names contain any of `terms` (each term's words must all appear). Earlier
	 * terms rank higher. Plural/singular variants are tolerated. */
	related(terms: string[], filter: SearchFilter = defaultFilter(), excluding: Set<number> = new Set()): number[] {
		const score = new Map<number, number>()
		terms.forEach((term, rank) => {
			const words = term.toLowerCase().split(nonWord).filter(Boolean)
			if (!words.length) return
			let matched: Set<number> | undefined
			for (const w of words) {
				const list = new Set(variants(w).flatMap((v) => this.postings.get(v) ?? []))
				matched = matched ? new Set([...matched].filter((i) => list.has(i))) : list
				if (!matched.size) break
			}
			const head = new Set(variants(words[words.length - 1]).map((v) => v.toUpperCase()))
			const weight = 1 / (1 + rank * 0.08)
			for (const i of matched ?? []) {
				if (excluding.has(i) || !this.accepts(this.entries[i], filter)) continue
				// "WHITE SQUARE" is a square; "SQUARE ROOT" is not.
				const w = weight * (isHeadNoun(head, this.entries[i].name) ? 1 : 0.45)
				const s = score.get(i)
				if (s !== undefined) score.set(i, Math.max(s, w) + 0.05) // small boost for matching several terms
				else score.set(i, w + this.quality(i, 0.4))
			}
		})
		return [...score].sort(byScore).map((s) => s[0])
	}

	/** Favour symbols and short names over letters/ideographs that merely mention a word. */
	private quality(i: number, symbolBonus: number): number {
		const e = this.entries[i]
		let b = 0.5 / Math.max(1, this.wordCounts[i])
		switch (e.gc) {
			case "So":
			case "Sm":
				b += symbolBonus
				break
			case "Sk":
			case "Sc":
			case "Po":
				b += symbolBonus * 0.4
				break
		}
		if ((e.mask & ideographMask) !== 0 || e.block.includes("CJK") || e.block.includes("Kangxi")) b -= 0.3
		if (e.id <= 0xffff || (e.mask & emojiMask) !== 0) b += 0.05
		return b
	}
}

function push(map: Map<string, number[]>, key: string, value: number) {
	const list = map.get(key)
	if (list) list.push(value)
	else map.set(key, [value])
}

const byScore = (a: [number, number], b: [number, number]) => (a[1] !== b[1] ? b[1] - a[1] : a[0] - b[0])

/** Trims spaces and tabs (not newlines), like Swift's `.whitespaces`. */
const trimSpaces = (s: string) => s.replace(/^[^\S\n\r\u2028\u2029]+|[^\S\n\r\u2028\u2029]+$/g, "")

const isHexCode = (w: string) => w.length >= 4 && /^[0-9a-f]+$/.test(w) && /[0-9]/.test(w)

/** Fewest runs needed to match `q` in `name` with each run starting at a word start. */
export function boundaryRuns(q: string, name: string): number | undefined {
	let best: number | undefined
	const isBoundary = (p: number) => p === 0 || name[p - 1] === " " || name[p - 1] === "-"
	const search = (qi: number, ni: number, runs: number) => {
		if (best !== undefined && runs >= best) return
		if (qi === q.length) {
			best = runs
			return
		}
		// Continue the current run.
		if (qi > 0 && ni < name.length && name[ni] === q[qi]) search(qi + 1, ni + 1, runs)
		// Or start a new run at a later word.
		for (let p = ni; p < name.length; p++) {
			if (name[p] === q[qi] && isBoundary(p) && (qi === 0 || p !== ni)) search(qi + 1, p + 1, runs + 1)
		}
	}
	search(0, 0, 0)
	return best
}

/** 0...1 similarity between a query token and one name word. */
export function wordScore(token: string, word: string): number {
	const t = token.length
	const w = word.length
	if (t === w && token === word) return 1
	if (t < w && word.startsWith(token)) return t === 1 ? 0 : 0.7 + (0.2 * t) / w
	if (t >= 3 && w > t && word.includes(token)) return 0.4
	if (t >= 4 && Math.abs(t - w) <= 2) {
		const maxDist = t >= 7 ? 2 : 1
		const d = boundedDistance(token, word, maxDist)
		if (d === 1) return 0.5
		if (d === 2 && maxDist >= 2) return 0.3
	}
	return 0
}

/** Optimal-string-alignment distance, returning `max + 1` once it's exceeded. */
function boundedDistance(a: string, b: string, max: number): number {
	const n = a.length
	const m = b.length
	let prev2 = new Array<number>(m + 1).fill(0)
	let prev = Array.from({ length: m + 1 }, (_, j) => j)
	let cur = new Array<number>(m + 1).fill(0)
	for (let i = 1; i <= n; i++) {
		cur[0] = i
		let rowMin = cur[0]
		for (let j = 1; j <= m; j++) {
			const cost = a[i - 1] === b[j - 1] ? 0 : 1
			let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
			if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) v = Math.min(v, prev2[j - 2] + 1)
			cur[j] = v
			rowMin = Math.min(rowMin, v)
		}
		if (rowMin > max) return max + 1
		;[prev2, prev, cur] = [prev, cur, prev2]
	}
	return prev[m]
}

/** The word a Unicode name is "about": the last word, or the one before WITH/CONTAINING/etc. */
function isHeadNoun(variants: Set<string>, name: string): boolean {
	const words = name.split(splitWords).filter(Boolean)
	const at = words.findIndex((w) => variants.has(w))
	if (at < 0) return false
	return at + 1 === words.length || headTerminators.has(words[at + 1])
}

const headTerminators = new Set([
	"WITH", "CONTAINING", "INSIDE", "ABOVE", "BELOW", "OVER", "UNDER", "AND", "OPERATOR",
	"SHAPE", "SYMBOL", "SIGN", "FORMAT", "ORNAMENT",
])

function variants(w: string): string[] {
	const v = [w]
	if (w.endsWith("ies")) v.push(w.slice(0, -3) + "y")
	if (w.endsWith("es")) v.push(w.slice(0, -2))
	if (w.endsWith("s")) v.push(w.slice(0, -1))
	else v.push(w + "s")
	return v
}
