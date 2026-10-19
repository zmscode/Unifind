import "./style.css"
import {
	abbreviation, Category, categoryNames, codepoint, decode, displayName, generalCategoryLabel,
	isInvisible, maskOf, type CharacterFile, type Entry, type Palette,
} from "./data.ts"
import { Grid, type Section } from "./grid.ts"
import { categoryIcons, icon, icons } from "./icons.ts"
import { RenderCheck } from "./render-check.ts"
import { CharacterIndex, type SearchFilter } from "./search.ts"
import { SmartSearch } from "./smart.ts"
import { applyTheme, defaultTheme, fontStack, tint } from "./theme.ts"

const version = __APP_VERSION__
const brewCommand = "brew install --cask zmscode/unifind/unifind"
const repoURL = "https://github.com/zmscode/Unifind"

// MARK: - Small helpers

type Child = Node | string | null | undefined | false | Child[]
function h<K extends keyof HTMLElementTagNameMap>(tag: K, props: Record<string, unknown> = {}, ...children: Child[]) {
	const el = document.createElement(tag)
	for (const [k, v] of Object.entries(props)) {
		if (v === undefined || v === false) continue
		if (k.startsWith("on")) el.addEventListener(k.slice(2), v as EventListener)
		else if (k === "class") el.className = v as string
		else if (k === "style") Object.assign(el.style, v)
		else if (k in el && k !== "list") (el as unknown as Record<string, unknown>)[k] = v
		else el.setAttribute(k, v === true ? "" : String(v))
	}
	for (const c of children.flat(Infinity as 1) as Child[]) if (c) el.append(c as Node | string)
	return el
}

const store = {
	get<T>(key: string, fallback: T): T {
		try {
			const v = localStorage.getItem(key)
			return v === null ? fallback : (JSON.parse(v) as T)
		} catch {
			return fallback
		}
	},
	set(key: string, value: unknown) {
		try {
			localStorage.setItem(key, JSON.stringify(value))
		} catch {
			// Private windows: settings last for this visit only.
		}
	},
}

const isTouch = matchMedia("(hover: none)").matches

// MARK: - State

const state = {
	query: new URLSearchParams(location.search).get("q") ?? "",
	category: Category.all as Category,
	selection: undefined as number | undefined,
	hovered: undefined as number | undefined,
	smartEnabled: store.get("smartEnabled", true),
	hidden: store.get("hiddenCategories", 0),
	includeUnrenderable: store.get("includeUnrenderable", false),
	recents: store.get<number[]>("recents", []),
	favorites: store.get<number[]>("favorites", []),
	theme: store.get("theme", defaultTheme),
	glyphFont: store.get("glyphFont", ""),
	direct: [] as number[],
	related: [] as number[],
	relatedTerms: [] as string[],
	thinking: false,
}

let index: CharacterIndex
let renderCheck: RenderCheck
let themes: Palette[] = []
const smart = new SmartSearch()
let grid: Grid

const palette = () => themes.find((t) => t.name === state.theme) ?? themes.find((t) => t.name === defaultTheme)!
const entryFor = (scalar: number) => {
	const i = index.byScalar.get(scalar)
	return i === undefined ? undefined : index.entries[i]
}
const isSearching = () => state.query.replace(/^[ \t]+|[ \t]+$/g, "") !== ""

/** Recently Copied and Favourites are lists the person built, not Unicode categories. */
function personalList(c: Category) {
	return c === Category.recents ? state.recents : c === Category.favorites ? state.favorites : undefined
}

function filter(): SearchFilter {
	const list = personalList(state.category)
	return { category: state.category, allowed: list && new Set(list), hidden: state.hidden, includeUnrenderable: state.includeUnrenderable }
}

/** Pasted text broken into its characters, invisible ones included. Only for text with two or
 * more characters, at least one of them beyond printable ASCII. */
function inspectedText(): Entry[] {
	const scalars = [...state.query].map((c) => c.codePointAt(0)!)
	if (scalars.length < 2 || !scalars.some((s) => s > 0x7e || s < 0x20)) return []
	return scalars.map(entryFor).filter((e): e is Entry => !!e)
}

// MARK: - Search

let searchTimer = 0
let smartTimer = 0
let smartAbort: AbortController | undefined

function scheduleSearch(resetScroll = true) {
	clearTimeout(searchTimer)
	clearTimeout(smartTimer)
	smartAbort?.abort()
	state.thinking = false
	syncURL()
	if (!index) return
	if (!isSearching()) {
		state.direct = browse()
		state.related = []
		state.relatedTerms = []
		renderResults(resetScroll)
		return
	}
	searchTimer = window.setTimeout(() => {
		state.direct = index.search(state.query, filter())
		state.related = []
		state.relatedTerms = []
		renderResults(resetScroll)
		// Pasted text isn't a description, so it never goes to the model.
		if (!state.smartEnabled || inspectedText().length) return
		// Let typing settle before asking the model.
		smartTimer = window.setTimeout(runSmart, 350)
	}, 40)
}

async function runSmart() {
	const abort = (smartAbort = new AbortController())
	const query = state.query
	state.thinking = true
	renderResults(false)
	try {
		const terms = await smart.expand(query, abort.signal)
		if (abort.signal.aborted) return
		state.relatedTerms = terms
		state.related = index.related(terms, filter(), new Set(state.direct))
	} catch {
		if (abort.signal.aborted) return
	}
	state.thinking = false
	renderResults(false)
}

const browseCache = new Map<Category, number[]>()
function browse(): number[] {
	const list = personalList(state.category)
	if (list) return list.map((s) => index.byScalar.get(s)).filter((i): i is number => i !== undefined)
	let cached = browseCache.get(state.category)
	if (!cached) browseCache.set(state.category, (cached = index.indices(filter())))
	return cached
}

/** After characters turn out to be undrawable: drop them from what's on screen. */
function refilter() {
	browseCache.clear()
	if (!isSearching()) state.direct = browse()
	else {
		state.direct = index.search(state.query, filter())
		const f = filter()
		state.related = state.related.filter((i) => index.accepts(index.entries[i], f))
	}
	renderResults(false)
}

function syncURL() {
	const url = new URL(location.href)
	if (isSearching()) url.searchParams.set("q", state.query)
	else url.searchParams.delete("q")
	history.replaceState(null, "", url)
}

// MARK: - Copying, recents and favourites

let toastTimer = 0
function toast(text: string) {
	const el = document.getElementById("toast")!
	el.textContent = text
	el.classList.add("shown")
	clearTimeout(toastTimer)
	toastTimer = window.setTimeout(() => el.classList.remove("shown"), 1400)
}

async function copy(text: string, label?: string, scalar?: number) {
	try {
		await navigator.clipboard.writeText(text)
	} catch {
		// Older browsers and non-secure pages: copy through a hidden field.
		const field = h("textarea", { value: text, style: { position: "fixed", opacity: "0" } })
		document.body.append(field)
		field.select()
		document.execCommand("copy")
		field.remove()
	}
	if (scalar !== undefined) recordRecent(scalar)
	toast(`Copied ${label ?? text}`)
}

const charOf = (e: Entry) => String.fromCodePoint(e.id)
const copyCharacter = (e: Entry) => copy(charOf(e), e.glyph, e.id)

function recordRecent(scalar: number) {
	state.recents = [scalar, ...state.recents.filter((s) => s !== scalar)].slice(0, 60)
	store.set("recents", state.recents)
	if (state.category === Category.recents && !isSearching()) scheduleSearch(false)
}

function toggleFavorite(e: Entry) {
	if (state.favorites.includes(e.id)) {
		state.favorites = state.favorites.filter((s) => s !== e.id)
		toast(`Removed ${e.glyph} from Favourites`)
	} else {
		state.favorites = [...state.favorites, e.id]
		toast(`Added ${e.glyph} to Favourites`)
	}
	store.set("favorites", state.favorites)
	if (state.category === Category.favorites) scheduleSearch(false)
	renderDetail()
}

/** What ⏎ acts on: the hovered character, else the selected one, else the top result. */
function returnTarget(): Entry | undefined {
	if (state.hovered !== undefined) return entryFor(state.hovered)
	if (state.selection !== undefined) return entryFor(state.selection)
	const text = inspectedText()
	if (text.length) return text[0]
	const i = state.direct[0] ?? state.related[0]
	return i === undefined ? undefined : index.entries[i]
}

/** ⏎ copies (a web page can't paste into another app). */
function copyReturnTarget() {
	const e = returnTarget()
	if (!e) return
	select(e.id)
	copyCharacter(e)
}

function select(scalar: number | undefined) {
	state.selection = scalar
	for (const t of grid.tiles()) t.classList.toggle("selected", Number(t.dataset.id) === scalar)
	renderDetail()
}

// MARK: - Glyphs and tiles

const measureCanvas = document.createElement("canvas").getContext("2d")!

/** A character, or a labelled dashed box for spaces and format characters that draw nothing.
 * Glyphs wider than `room` shrink to fit, down to 40%, like the app's minimum scale factor. */
function glyphView(e: Entry, size: number, room: number) {
	if (isInvisible(e)) return h("span", { class: "invisible" }, abbreviation(e))
	measureCanvas.font = `${size}px ${fontStack(state.glyphFont)}`
	const width = measureCanvas.measureText(e.glyph).width
	const fitted = width > room ? Math.max(size * 0.4, (size * room) / width) : size
	return h("span", { class: "glyph", style: { fontSize: `${fitted}px` } }, e.glyph)
}

function renderTile(i: number) {
	const e = index.entries[i]
	return h(
		"div",
		{ class: `tile${state.selection === e.id ? " selected" : ""}`, "data-i": i, "data-id": e.id, draggable: "true" },
		glyphView(e, grid.tile / 2, grid.tile - 8),
	)
}

function sectionHeader(title: string, count: number, color: string) {
	return () =>
		h(
			"div",
			{ class: "header", style: { "--tint": color } },
			h("span", { class: "dot" }),
			h("span", { class: "title" }, title.toUpperCase()),
			h("span", { class: "count" }, count.toLocaleString()),
		)
}

function relatedHeader() {
	return h(
		"div",
		{ class: "header related" },
		h(
			"div",
			{ class: "header-line" },
			icon(icons.sparkles, 13),
			h("span", { class: "title" }, "RELATED"),
			state.thinking ? h("span", { class: "thinking" }, "thinking…") : h("span", { class: "count" }, state.related.length.toLocaleString()),
		),
		state.relatedTerms.length > 0 &&
			h(
				"div",
				{ class: "chips" },
				state.relatedTerms.map((term) => h("button", { class: "chip", onclick: () => setQuery(term) }, term)),
			),
	)
}

function renderResults(resetScroll: boolean) {
	const host = document.getElementById("results")!
	const empty = document.getElementById("empty")!
	const p = palette()
	const sections: Section[] = []
	if (isSearching()) {
		const text = inspectedText()
		if (text.length) {
			sections.push({ key: "t", items: text.map((e) => index.byScalar.get(e.id)!), header: sectionHeader("In your text", text.length, p.smart), headerHeight: 38 })
		}
		if (state.direct.length) sections.push({ key: "d", items: state.direct, header: sectionHeader("Matches", state.direct.length, p.accent), headerHeight: 38 })
		if (state.thinking || state.related.length) {
			sections.push({ key: "r", items: state.related, header: relatedHeader, headerHeight: state.relatedTerms.length ? 74 : 44 })
		}
	} else {
		sections.push({
			key: `b${state.category}`,
			items: state.direct,
			header: sectionHeader(categoryNames[state.category], state.direct.length, tint(p, state.category)),
			headerHeight: 38,
		})
	}
	const nothing = sections.every((s) => !s.items.length) && !state.thinking
	host.classList.toggle("is-empty", nothing)
	empty.replaceChildren(...(nothing ? emptyState() : []))
	grid.setSections(nothing ? [] : sections, resetScroll)
}

function emptyState(): Node[] {
	return emptyStateParts().filter((n): n is Node => n instanceof Node)
}

function emptyStateParts(): Child[] {
	let symbol = icon(icons.search, 28)
	let title = "No characters"
	let hint: string | undefined
	if (!isSearching() && state.category === Category.recents) {
		symbol = icon(icons.clock, 28)
		title = "Nothing copied yet"
		hint = isTouch ? "Double-tap a character to copy it." : "Double-click a character to copy it."
	} else if (!isSearching() && state.category === Category.favorites) {
		symbol = icon(icons.star, 28)
		title = "No favourites yet"
		hint = "Right-click a character, or press ☆ in the bottom bar."
	}
	return [
		symbol,
		h("div", { class: "empty-title" }, title),
		hint && h("div", { class: "empty-hint" }, hint),
		isSearching() && state.category !== Category.all && h("button", { class: "link", onclick: () => setCategory(Category.all) }, "Search all characters"),
	]
}

// MARK: - Sidebar

const sidebarOrder: (Category | "divider")[] = [
	Category.all, Category.recents, Category.favorites, "divider",
	Category.emoji, Category.arrows, Category.shapes, Category.math, Category.currency, Category.punctuation,
	Category.letters, Category.numbers, Category.symbols, Category.boxDrawing, Category.marks, Category.spaces,
	Category.ideographs,
]

function setCategory(c: Category) {
	state.category = c
	renderSidebar()
	scheduleSearch()
}

function renderSidebar() {
	const p = palette()
	const rows = sidebarOrder.map((c) =>
		c === "divider"
			? h("div", { class: "divider" })
			: h(
					"button",
					{ class: `side-row${state.category === c ? " selected" : ""}`, style: { "--tint": tint(p, c) }, onclick: () => setCategory(c) },
					icon(categoryIcons[c], 15),
					h("span", {}, categoryNames[c]),
				),
	)
	document.getElementById("categories")!.replaceChildren(...rows)
}

// MARK: - Detail bar

function renderDetail() {
	const bar = document.getElementById("detail")!
	const e = state.selection === undefined ? undefined : entryFor(state.selection)
	bar.classList.toggle("expanded", !!e)
	const returnButton = h(
		"button",
		{ class: "return-action", title: "Copy the hovered or selected character", onclick: copyReturnTarget },
		h("span", {}, "Copy"),
		h("kbd", {}, "⏎"),
	)
	if (!e) {
		bar.replaceChildren(
			h("span", { class: "hint" }, isTouch ? "tap a character  ·  double-tap to copy" : "hover or click a character  ·  ⏎ to copy  ·  double-click to copy"),
			h("span", { class: "spacer" }),
			returnButton,
		)
		return
	}
	const hex = e.id.toString(16).toUpperCase()
	const formats: [string, string][] = [
		["U+", codepoint(e.id)],
		["HTML", `&#x${hex};`],
		["Swift", `\\u{${hex}}`],
		["Name", e.name],
	]
	const favourite = state.favorites.includes(e.id)
	bar.replaceChildren(
		h("button", { class: "detail-glyph", title: "Copy character", onclick: () => copyCharacter(e) }, glyphView(e, 30, 44)),
		h(
			"div",
			{ class: "detail-text" },
			h("div", { class: "detail-name" }, displayName(e.name)),
			h(
				"div",
				{ class: "detail-meta" },
				h("span", { class: "cp" }, codepoint(e.id)),
				" · ",
				e.block,
				" · ",
				generalCategoryLabel[e.gc] ?? e.gc,
				renderCheck.get(index.byScalar.get(e.id)!) === false && h("span", { class: "nofont" }, " · no font"),
			),
		),
		h("span", { class: "spacer" }),
		h(
			"div",
			{ class: "pills" },
			h(
				"button",
				{ class: `pill star${favourite ? " on" : ""}`, title: favourite ? "Remove from Favourites (⌘D)" : "Add to Favourites (⌘D)", onclick: () => toggleFavorite(e) },
				icon(icons.star, 12, favourite),
			),
			formats.map(([label, value]) => h("button", { class: "pill", title: value, onclick: () => copy(value) }, label)),
		),
		h("span", { class: "separator" }),
		returnButton,
	)
}

// MARK: - Hover card

let hoverTimer = 0
let pointer = { x: 0, y: 0 }
const weightNames = ["Thin", "ExtraLight", "Light", "Regular", "Medium", "Semibold", "Bold", "Heavy", "Black"]
const weightCanvas = document.createElement("canvas").getContext("2d", { willReadFrequently: true })!

/** The weights the glyph font really draws differently, found by comparing renderings. Each
 * group of weights that draw alike is named for Regular or Bold when it has them. */
function distinctWeights(e: Entry): number[] {
	const c = weightCanvas.canvas
	c.width = c.height = 40
	const groups = new Map<number, number[]>()
	for (let w = 100; w <= 900; w += 100) {
		weightCanvas.clearRect(0, 0, 40, 40)
		weightCanvas.font = `${w} 28px ${fontStack(state.glyphFont)}`
		weightCanvas.textBaseline = "middle"
		weightCanvas.fillText(e.glyph, 4, 20)
		const data = weightCanvas.getImageData(0, 0, 40, 40).data
		let sum = 0
		for (let p = 3; p < data.length; p += 4) sum = (sum * 31 + data[p]) | 0
		groups.set(sum, [...(groups.get(sum) ?? []), w])
	}
	return [...groups.values()].map((ws) => (ws.includes(400) ? 400 : ws.includes(700) ? 700 : ws[0]))
}

function showHoverCard(e: Entry) {
	const card = document.getElementById("hovercard")!
	const weights = distinctWeights(e)
	const family = state.glyphFont || "System font"
	card.replaceChildren(
		h("div", { class: "hc-name" }, displayName(e.name)),
		h("div", { class: "hc-sub" }, weights.length === 1 ? `${family} · single weight` : `${family} · ${weights.length} weights`),
		h(
			"div",
			{ class: "hc-samples" },
			weights.map((w) =>
				h("div", { class: "hc-sample" }, h("span", { class: "glyph", style: { fontWeight: String(w) } }, e.glyph), weights.length > 1 && h("span", { class: "hc-label" }, weightNames[w / 100 - 1])),
			),
		),
	)
	card.classList.add("shown")
	positionHoverCard()
}

function positionHoverCard() {
	const card = document.getElementById("hovercard")!
	if (!card.classList.contains("shown")) return
	const bounds = document.getElementById("results")!.getBoundingClientRect()
	const w = card.offsetWidth
	const hgt = card.offsetHeight
	const x = Math.min(Math.max(8, pointer.x - bounds.left - w / 2), bounds.width - w - 8)
	let y = pointer.y - bounds.top + 22
	if (y + hgt > bounds.height - 8) y = pointer.y - bounds.top - hgt - 14
	card.style.transform = `translate(${x}px, ${Math.max(8, y)}px)`
}

function setHovered(scalar: number | undefined) {
	if (scalar === state.hovered) return
	state.hovered = scalar
	clearTimeout(hoverTimer)
	document.getElementById("hovercard")!.classList.remove("shown")
	const e = scalar === undefined ? undefined : entryFor(scalar)
	if (!e || isInvisible(e) || isTouch) return
	hoverTimer = window.setTimeout(() => showHoverCard(e), 450)
}

// MARK: - Menus

function closeMenus() {
	document.querySelectorAll(".menu").forEach((m) => m.remove())
}

function openMenu(items: (HTMLElement | false)[], x: number, y: number) {
	closeMenus()
	const menu = h("div", { class: "menu", onclick: (ev: Event) => ev.stopPropagation() }, items)
	document.body.append(menu)
	const r = menu.getBoundingClientRect()
	menu.style.left = `${Math.max(8, Math.min(x, innerWidth - r.width - 8))}px`
	menu.style.top = `${Math.max(8, Math.min(y, innerHeight - r.height - 8))}px`
	return menu
}

const menuItem = (label: string, action: () => void, checked?: boolean) =>
	h(
		"button",
		{ class: "menu-item", role: checked === undefined ? "menuitem" : "menuitemcheckbox", "aria-checked": checked === undefined ? undefined : String(checked), onclick: () => (action(), closeMenus()) },
		checked !== undefined && h("span", { class: "check" }, checked ? "✓" : ""),
		label,
	)

function openContextMenu(e: Entry, x: number, y: number) {
	const fav = state.favorites.includes(e.id)
	openMenu(
		[
			menuItem("Copy Character", () => copyCharacter(e)),
			menuItem(fav ? "Remove from Favourites" : "Add to Favourites", () => toggleFavorite(e)),
			h("div", { class: "menu-divider" }),
			menuItem("Copy Name", () => copy(e.name)),
			menuItem("Copy Code Point", () => copy(codepoint(e.id))),
		],
		x,
		y,
	)
}

const hideable = [
	Category.emoji, Category.letters, Category.ideographs, Category.marks, Category.spaces, Category.numbers,
	Category.punctuation, Category.math, Category.boxDrawing,
]

const filtersActive = () => state.hidden !== 0 || state.includeUnrenderable

function filtersChanged() {
	store.set("hiddenCategories", state.hidden)
	store.set("includeUnrenderable", state.includeUnrenderable)
	browseCache.clear()
	renderToolbar()
	scheduleSearch(false)
}

function openFilterMenu(anchor: HTMLElement) {
	const r = anchor.getBoundingClientRect()
	const toggleHidden = (c: Category) => {
		state.hidden ^= maskOf(c)
		filtersChanged()
	}
	openMenu(
		[
			h("div", { class: "menu-title" }, "Hide in Results"),
			...hideable.map((c) => menuItem(categoryNames[c], () => toggleHidden(c), (state.hidden & maskOf(c)) !== 0)),
			h("div", { class: "menu-divider" }),
			menuItem("Show Characters Without a Font", () => ((state.includeUnrenderable = !state.includeUnrenderable), filtersChanged()), state.includeUnrenderable),
			filtersActive() && menuItem("Reset Filters", () => ((state.hidden = 0), (state.includeUnrenderable = false), filtersChanged())),
		],
		r.right - 240,
		r.bottom + 6,
	)
}

// MARK: - Toolbar

function setQuery(q: string) {
	state.query = q
	const input = document.getElementById("search") as HTMLInputElement
	if (input.value !== q) input.value = q
	document.getElementById("clear")!.hidden = !q
	state.selection = undefined
	renderDetail()
	scheduleSearch()
}

function renderToolbar() {
	const filterButton = document.getElementById("filter")!
	filterButton.classList.toggle("active", filtersActive())
	const smartButton = document.getElementById("smart")!
	smartButton.classList.toggle("active", state.smartEnabled)
	smartButton.setAttribute("aria-pressed", String(state.smartEnabled))
	smartButton.title = smart.help
}

// MARK: - Settings

const fontChoices = [
	"", "Helvetica Neue", "Avenir Next", "Georgia", "Times New Roman", "Menlo", "SF Mono", "Courier New",
	"Arial", "Verdana", "Segoe UI", "Segoe UI Symbol", "Noto Sans", "Noto Sans Symbols 2", "Noto Serif",
	"DejaVu Sans", "Apple Symbols", "Arial Unicode MS", "Iosevka", "JetBrains Mono", "Fira Code", "serif", "monospace",
]

/** Whether a local font exists, by checking that text draws wider or narrower than the fallbacks. */
function hasFont(family: string) {
	if (!family || ["serif", "monospace"].includes(family)) return true
	const ctx = weightCanvas
	return ["monospace", "serif", "sans-serif"].some((fallback) => {
		ctx.font = `20px ${fallback}`
		const base = ctx.measureText("mmmmmlli1WQ").width
		ctx.font = `20px "${family}", ${fallback}`
		return ctx.measureText("mmmmmlli1WQ").width !== base
	})
}

function setGlyphFont(family: string) {
	state.glyphFont = family.trim()
	store.set("glyphFont", state.glyphFont)
	document.documentElement.style.setProperty("--glyph-font", fontStack(state.glyphFont))
	renderCheck.setFont(fontStack(state.glyphFont))
	browseCache.clear()
	scheduleSearch(false)
	renderSettings()
}

function setTheme(name: string) {
	state.theme = name
	store.set("theme", name)
	applyTheme(palette())
	renderSidebar()
	renderResults(false)
	renderSettings()
}

function openSettings(tab: "appearance" | "about" = "appearance") {
	const dialog = document.getElementById("settings") as HTMLDialogElement
	dialog.dataset.tab = tab
	renderSettings()
	dialog.showModal()
}

function renderSettings() {
	const dialog = document.getElementById("settings") as HTMLDialogElement
	if (!dialog.open && !dialog.dataset.tab) return
	const tab = dialog.dataset.tab ?? "appearance"
	const tabButton = (id: string, label: string) =>
		h("button", { class: `tab${tab === id ? " selected" : ""}`, onclick: () => ((dialog.dataset.tab = id), renderSettings()) }, label)
	const available = fontChoices.filter(hasFont)
	if (state.glyphFont && !available.includes(state.glyphFont)) available.push(state.glyphFont)
	const families = [...new Set(themes.map((t) => t.family))]

	const appearance = [
		h("h2", {}, "Glyph Font"),
		h(
			"div",
			{ class: "font-row" },
			h(
				"select",
				{ onchange: (ev: Event) => setGlyphFont((ev.target as HTMLSelectElement).value) },
				available.map((f) => h("option", { value: f, selected: f === state.glyphFont }, f || "System")),
			),
			h("input", {
				type: "text",
				placeholder: "Or type any installed font…",
				value: fontChoices.includes(state.glyphFont) ? "" : state.glyphFont,
				onchange: (ev: Event) => setGlyphFont((ev.target as HTMLInputElement).value),
			}),
		),
		h("div", { class: "font-preview glyph" }, "A g ★ → ∑ ☃ ♞ 😀"),
		h(
			"p",
			{ class: "note" },
			state.glyphFont
				? `Characters ${state.glyphFont} doesn't have fall back to other fonts. Characters no font can draw are hidden.`
				: "Best coverage: the system font, with the browser picking the right fallback font for everything else.",
		),
		h("h2", {}, "Theme"),
		families.map((family) =>
			h(
				"section",
				{ class: "theme-family" },
				h("h3", {}, family),
				h(
					"div",
					{ class: "theme-grid" },
					themes
						.filter((t) => t.family === family)
						.map((t) =>
							h(
								"button",
								{ class: `theme-card${t.name === state.theme ? " selected" : ""}`, onclick: () => setTheme(t.name), style: { "--card-accent": t.accent } },
								h(
									"div",
									{ class: "theme-preview", style: { background: t.background, color: t.text } },
									h("span", { class: "theme-glyphs" }, "★→◆"),
									h("span", { class: "theme-dots" }, [t.accent, t.attribute, t.smart, t.preprocessor, t.character].map((c) => h("i", { style: { background: c } }))),
								),
								h("span", { class: "theme-name" }, t.name),
							),
						),
				),
			),
		),
	]

	const about = [
		h(
			"div",
			{ class: "about" },
			h("img", { src: "icon.png", alt: "", width: 96, height: 96 }),
			h("div", { class: "about-name" }, "Unifind"),
			h("div", { class: "about-version" }, `Version ${version} · web`),
			h("p", {}, "A Unicode character finder. This is the in-browser companion to the native Mac app, which adds Apple Intelligence search and ⏎ to paste straight into the app you were using."),
			installCard(),
			h("a", { class: "link", href: repoURL, target: "_blank", rel: "noopener" }, "Source on GitHub ", icon(icons.external, 12)),
		),
	]

	dialog.replaceChildren(
		h(
			"div",
			{ class: "settings-head" },
			h("div", { class: "tabs" }, tabButton("appearance", "Appearance"), tabButton("about", "About")),
			h("button", { class: "icon-button", title: "Close", onclick: () => dialog.close() }, icon(icons.x, 16)),
		),
		h("div", { class: "settings-body" }, tab === "about" ? about : appearance),
	)
}

function installCard() {
	return h(
		"div",
		{ class: "install" },
		h("div", { class: "install-title" }, icon(icons.download, 13), "Get the Mac app"),
		h(
			"button",
			{ class: "install-command", title: "Copy the Homebrew command", onclick: () => copy(brewCommand, "the install command") },
			h("code", {}, "brew install --cask ", h("wbr"), "zmscode/unifind/unifind"),
			icon(icons.copy, 13),
		),
		h("div", { class: "install-note" }, "macOS 26 · Apple silicon"),
	)
}

// MARK: - Layout and events

function buildLayout() {
	const app = document.getElementById("app")!
	const search = h("input", {
		id: "search",
		type: "search",
		placeholder: "Search characters",
		autocomplete: "off",
		spellcheck: false,
		value: state.query,
		oninput: (ev: Event) => setQuery((ev.target as HTMLInputElement).value),
	})
	app.replaceChildren(
		h(
			"aside",
			{ class: "sidebar" },
			h("nav", { id: "categories" }),
			h(
				"div",
				{ class: "sidebar-foot" },
				installCard(),
				h(
					"button",
					{ class: "badge", title: `About Unifind ${version}`, onclick: () => openSettings("about") },
					h("img", { src: "icon.png", alt: "", width: 34, height: 34 }),
					h("span", { class: "badge-text" }, h("span", { class: "badge-name" }, "Unifind"), h("span", { class: "badge-version" }, `Version ${version}`)),
				),
			),
		),
		h(
			"main",
			{},
			h(
				"header",
				{ class: "toolbar" },
				h(
					"label",
					{ class: "search-field" },
					icon(icons.search, 14),
					search,
					h("button", { id: "clear", class: "clear", title: "Clear", hidden: !state.query, onclick: () => (setQuery(""), search.focus()) }, icon(icons.x, 12)),
				),
				h("button", { id: "filter", class: "icon-button", title: "Filter results", onclick: (ev: Event) => (ev.stopPropagation(), openFilterMenu(ev.currentTarget as HTMLElement)) }, icon(icons.filter, 17)),
				h(
					"button",
					{
						id: "smart",
						class: "icon-button smart",
						onclick: () => {
							state.smartEnabled = !state.smartEnabled
							store.set("smartEnabled", state.smartEnabled)
							if (state.smartEnabled) smart.load()
							renderToolbar()
							scheduleSearch(false)
						},
					},
					icon(icons.sparkles, 17),
				),
				h("button", { class: "icon-button", title: "Settings", onclick: () => openSettings() }, icon(icons.settings, 17)),
			),
			h("nav", { id: "category-strip", class: "category-strip" }),
			h("div", { id: "results" }, h("div", { id: "empty", class: "empty" }), h("div", { id: "hovercard", class: "hovercard" })),
			h("footer", { id: "detail", class: "detail" }),
		),
		h("div", { id: "toast", class: "toast" }),
		h("dialog", { id: "settings", class: "settings", onclick: (ev: Event) => ev.target === ev.currentTarget && (ev.currentTarget as HTMLDialogElement).close() }),
	)

	const results = document.getElementById("results")!
	grid = new Grid(results, renderTile, (visible) => {
		if (!renderCheck.checkNow(visible)) return false
		refilter()
		return true
	})
	const tileOf = (ev: Event) => (ev.target as HTMLElement).closest<HTMLElement>(".tile")
	const scroller = grid.scroller
	scroller.addEventListener("pointermove", (ev) => {
		pointer = { x: ev.clientX, y: ev.clientY }
		const t = tileOf(ev)
		setHovered(t ? Number(t.dataset.id) : undefined)
		positionHoverCard()
	})
	scroller.addEventListener("pointerleave", () => setHovered(undefined))
	scroller.addEventListener("scroll", () => setHovered(undefined), { passive: true })
	scroller.addEventListener("click", (ev) => {
		const t = tileOf(ev)
		if (t) select(Number(t.dataset.id))
	})
	scroller.addEventListener("dblclick", (ev) => {
		const t = tileOf(ev)
		if (t) copyCharacter(entryFor(Number(t.dataset.id))!)
	})
	scroller.addEventListener("contextmenu", (ev) => {
		const t = tileOf(ev)
		if (!t) return
		ev.preventDefault()
		openContextMenu(entryFor(Number(t.dataset.id))!, ev.clientX, ev.clientY)
	})
	scroller.addEventListener("dragstart", (ev) => {
		const t = tileOf(ev)
		if (t) ev.dataTransfer?.setData("text/plain", String.fromCodePoint(Number(t.dataset.id)))
	})

	document.addEventListener("click", closeMenus)
	document.addEventListener("keydown", (ev) => {
		const dialogOpen = (document.getElementById("settings") as HTMLDialogElement).open
		if (ev.key === "Escape") {
			if (document.querySelector(".menu")) closeMenus()
			else if (!dialogOpen && state.query) setQuery("")
			return
		}
		if (dialogOpen) return
		const inField = ev.target instanceof HTMLElement && ev.target.matches("input, select, textarea, button") && ev.target !== search
		if (ev.key === "Enter" && !inField && !ev.isComposing) {
			ev.preventDefault()
			copyReturnTarget()
		} else if ((ev.metaKey || ev.ctrlKey) && ev.key.toLowerCase() === "d" && state.selection !== undefined) {
			ev.preventDefault()
			toggleFavorite(entryFor(state.selection)!)
		} else if ((ev.metaKey || ev.ctrlKey) && ev.key === ",") {
			ev.preventDefault()
			openSettings()
		} else if (ev.key === "/" && document.activeElement !== search && !inField) {
			ev.preventDefault()
			search.focus()
		}
	})
}

/** On phones the sidebar becomes a strip of category chips under the search field. */
function renderCategoryStrip() {
	const p = palette()
	const strip = document.getElementById("category-strip")!
	strip.replaceChildren(
		...sidebarOrder
			.filter((c): c is Category => c !== "divider")
			.map((c) =>
				h(
					"button",
					{ class: `strip-chip${state.category === c ? " selected" : ""}`, style: { "--tint": tint(p, c) }, onclick: () => (setCategory(c), renderCategoryStrip()) },
					icon(categoryIcons[c], 13),
					categoryNames[c],
				),
			),
		h("button", { class: "strip-chip mac", onclick: () => openSettings("about") }, icon(icons.download, 13), "Mac app"),
	)
}

async function start() {
	const base = import.meta.env.BASE_URL
	const [file, themeList] = await Promise.all([
		fetch(`${base}data/characters.json`).then((r) => r.json() as Promise<CharacterFile>),
		fetch(`${base}data/themes.json`).then((r) => r.json() as Promise<Palette[]>),
	])
	themes = themeList
	applyTheme(palette())
	document.documentElement.style.setProperty("--glyph-font", fontStack(state.glyphFont))
	buildLayout()
	index = new CharacterIndex(decode(file))
	renderCheck = new RenderCheck(index.entries)
	index.renderable = (id) => renderCheck.get(index.byScalar.get(id)!)
	// Idle-time checks find undrawable characters in bursts; catch the results up twice a second.
	let refilterTimer = 0
	renderCheck.onChange = () => {
		if (!refilterTimer) refilterTimer = window.setTimeout(() => ((refilterTimer = 0), refilter()), 500)
	}
	renderCheck.setFont(fontStack(state.glyphFont))
	if (import.meta.env.DEV) Object.assign(window, { unifind: { index, renderCheck, state } })
	smart.onChange = renderToolbar
	smart.start()
	renderSidebar()
	renderCategoryStrip()
	renderToolbar()
	renderDetail()
	scheduleSearch()
	document.body.classList.remove("loading")
	if (!isTouch) (document.getElementById("search") as HTMLInputElement).focus()
}

start().catch((error) => {
	console.error(error)
	document.getElementById("app")!.textContent = "Couldn't load the character data."
})
