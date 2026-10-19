// A virtualised glyph grid in sections (Matches, Related, a category…), with the section header
// pinned at the top like the app's LazyVStack. Only the rows in view are in the DOM.

export interface Section {
	key: string
	/** Entry indices, in order (pasted text may repeat them). */
	items: number[]
	header: () => HTMLElement
	headerHeight: number
}

type Row = { kind: "header"; section: number; top: number; height: number } | { kind: "tiles"; section: number; start: number; top: number; height: number }

export class Grid {
	readonly scroller: HTMLElement
	private content: HTMLElement
	private pinned: HTMLElement
	private sections: Section[] = []
	private rows: Row[] = []
	/** Each section's header row. */
	private headers: Row[] = []
	private columns = 1
	private painted = new Map<string, HTMLElement>()
	private pinnedSection = -1
	tile = 54
	gap = 4
	padding = 18
	/** On phones, tiles spread out to fill the row. */
	private columnGap = 4

	private renderTile: (entryIndex: number) => HTMLElement
	private beforePaint: (entryIndices: number[]) => boolean

	constructor(
		host: HTMLElement,
		renderTile: (entryIndex: number) => HTMLElement,
		/** Lets the app check the tiles about to be shown; returns true if it changed the sections. */
		beforePaint: (entryIndices: number[]) => boolean,
	) {
		this.renderTile = renderTile
		this.beforePaint = beforePaint
		this.scroller = document.createElement("div")
		this.scroller.className = "grid-scroller"
		this.content = document.createElement("div")
		this.content.className = "grid-content"
		this.pinned = document.createElement("div")
		this.pinned.className = "grid-pinned"
		this.scroller.append(this.content)
		host.append(this.scroller, this.pinned)
		this.scroller.addEventListener("scroll", () => this.paint(), { passive: true })
		new ResizeObserver(() => this.relayout()).observe(this.scroller)
	}

	setSections(sections: Section[], resetScroll: boolean) {
		const anchor = resetScroll ? undefined : this.anchor()
		this.sections = sections
		this.clear()
		this.layout()
		if (resetScroll) this.scroller.scrollTop = 0
		else if (anchor) this.restore(anchor)
		this.paint()
	}

	/** Redraws the tiles in view (after selection or favourites change). */
	refresh() {
		this.clear()
		this.paint()
	}

	private clear() {
		for (const el of this.painted.values()) el.remove()
		this.painted.clear()
		this.pinnedSection = -1
	}

	private relayout() {
		const cols = this.computeColumns()
		if (cols === this.columns && this.rows.length) return this.paint()
		const anchor = this.anchor()
		this.clear()
		this.layout()
		if (anchor) this.restore(anchor)
		this.paint()
	}

	private computeColumns() {
		// Phones get smaller tiles, as in the stylesheet's narrow layout.
		const narrow = matchMedia("(max-width: 720px)").matches
		this.tile = narrow ? 48 : 54
		this.padding = narrow ? 16 : 18
		this.content.style.setProperty("--tile", `${this.tile}px`)
		const room = this.scroller.clientWidth - this.padding * 2
		const columns = Math.max(1, Math.floor((room + this.gap) / (this.tile + this.gap)))
		this.columnGap = narrow && columns > 1 ? (room - columns * this.tile) / (columns - 1) : this.gap
		return columns
	}

	private layout() {
		this.columns = this.computeColumns()
		this.rows = []
		this.headers = []
		let top = 0
		const step = this.tile + this.gap
		this.sections.forEach((s, si) => {
			const header: Row = { kind: "header", section: si, top, height: s.headerHeight }
			this.rows.push(header)
			this.headers.push(header)
			top += s.headerHeight
			for (let start = 0; start < s.items.length; start += this.columns) {
				this.rows.push({ kind: "tiles", section: si, start, top, height: step })
				top += step
			}
		})
		this.content.style.height = `${top + this.padding}px`
	}

	/** The first row at or below `y`. */
	private rowAt(y: number) {
		let lo = 0
		let hi = this.rows.length - 1
		while (lo < hi) {
			const mid = (lo + hi + 1) >> 1
			if (this.rows[mid].top <= y) lo = mid
			else hi = mid - 1
		}
		return lo
	}

	private anchor() {
		if (!this.rows.length) return undefined
		const y = this.scroller.scrollTop
		if (y <= 0) return undefined
		const row = this.rows[this.rowAt(y)]
		const section = this.sections[row.section]
		const item = row.kind === "tiles" ? section.items[row.start] : undefined
		return { key: section.key, item, offset: y - row.top }
	}

	private restore(a: { key: string; item?: number; offset: number }) {
		const si = this.sections.findIndex((s) => s.key === a.key)
		if (si < 0) return
		let target: Row | undefined = this.headers[si]
		if (a.item !== undefined) {
			const pos = this.sections[si].items.indexOf(a.item)
			if (pos >= 0) target = this.rows.find((r) => r.section === si && r.kind === "tiles" && pos >= r.start && pos < r.start + this.columns) ?? target
		}
		if (target) this.scroller.scrollTop = target.top + a.offset
	}

	private paint() {
		if (!this.rows.length) return
		const y = this.scroller.scrollTop
		const h = this.scroller.clientHeight
		const first = this.rowAt(Math.max(0, y - 200))
		let last = first
		while (last + 1 < this.rows.length && this.rows[last + 1].top < y + h + 200) last++

		// Let the app check what's about to show; it may drop undrawable tiles and re-lay out.
		const visible: number[] = []
		for (let r = first; r <= last; r++) {
			const row = this.rows[r]
			if (row.kind === "tiles") visible.push(...this.sections[row.section].items.slice(row.start, row.start + this.columns))
		}
		if (this.beforePaint(visible)) return

		const keep = new Set<string>()
		for (let r = first; r <= last; r++) {
			const row = this.rows[r]
			const section = this.sections[row.section]
			const key = `${section.key}:${row.kind}:${row.kind === "tiles" ? row.start : 0}:${this.columns}`
			keep.add(key)
			if (this.painted.has(key)) continue
			let el: HTMLElement
			if (row.kind === "header") {
				el = section.header()
				el.classList.add("section-header")
			} else {
				el = document.createElement("div")
				el.className = "tile-row"
				el.style.gap = `${this.columnGap}px`
				for (const i of section.items.slice(row.start, row.start + this.columns)) el.append(this.renderTile(i))
			}
			el.style.transform = `translateY(${row.top}px)`
			el.style.height = `${row.height}px`
			el.style.left = el.style.right = `${this.padding}px`
			this.content.append(el)
			this.painted.set(key, el)
		}
		for (const [key, el] of this.painted) {
			if (!keep.has(key)) {
				el.remove()
				this.painted.delete(key)
			}
		}
		this.paintPinned(y)
	}

	/** The header of the section scrolled under the top edge stays visible. */
	private paintPinned(y: number) {
		const row = this.rows[this.rowAt(y)]
		const header = this.headers[row.section]
		const si = y > header.top ? row.section : -1
		if (si !== this.pinnedSection) {
			this.pinnedSection = si
			this.pinned.replaceChildren()
			if (si >= 0) {
				const el = this.sections[si].header()
				el.classList.add("section-header")
				el.style.height = `${this.sections[si].headerHeight}px`
				this.pinned.append(el)
			}
		}
		this.pinned.style.left = this.pinned.style.right = `${this.padding}px`
		// The next section's header pushes this one up.
		const next = si >= 0 ? this.headers[si + 1] : undefined
		const height = si >= 0 ? this.sections[si].headerHeight : 0
		const push = next ? Math.min(0, next.top - y - height) : 0
		this.pinned.style.transform = `translateY(${push}px)`
	}

	/** Tile elements currently in the DOM. */
	tiles(): NodeListOf<HTMLElement> {
		return this.content.querySelectorAll<HTMLElement>(".tile")
	}
}
