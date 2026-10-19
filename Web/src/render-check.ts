// Which characters this browser can draw. The Mac app asks CoreText which fonts cover a scalar;
// a browser can't, so we measure each glyph on a canvas and compare it with what the browser draws
// for characters no font has: the .notdef box, or on macOS the LastResort font's placeholders,
// which differ per block but all share one bounding box.
import { isInvisible, type Entry } from "./data.ts"

const unassigned = [0x0378, 0x05ff, 0x1e02f, 0x2fffd, 0xe0080]

/** 0 = not checked yet, 1 = drawable, 2 = no font. */
type Status = 0 | 1 | 2

export class RenderCheck {
	private status: Uint8Array
	private ctx: CanvasRenderingContext2D
	private tofu = new Set<string>()
	private storageKey = ""
	private cursor = 0
	private pending = 0
	private dirty = false
	private saveTimer = 0
	/** Called (batched) when characters turn out not to be drawable. */
	onChange?: () => void

	private entries: Entry[]

	constructor(entries: Entry[]) {
		this.entries = entries
		this.status = new Uint8Array(entries.length)
		this.ctx = document.createElement("canvas").getContext("2d")!
	}

	/** Starts over for a glyph font stack (CSS font-family list), reusing saved results. */
	setFont(stack: string) {
		this.storageKey = `renderable2:${stack}:${navigator.userAgent}:${this.entries.length}`
		this.status.fill(0)
		this.cursor = 0
		try {
			const saved = localStorage.getItem(this.storageKey)
			if (saved) {
				const bytes = Uint8Array.from(atob(saved), (c) => c.charCodeAt(0))
				for (let i = 0; i < this.status.length; i++) this.status[i] = ((bytes[i >> 2] >> ((i & 3) * 2)) & 3) as Status
			}
		} catch {
			// Private windows and blocked storage just check again.
		}
		this.ctx.font = `20px ${stack}`
		this.tofu = new Set(unassigned.map((cp) => this.signature(String.fromCodePoint(cp))))
		this.tofu.delete(blank)
		this.sampleBlocks()
		this.schedule()
	}

	/** Whether entry `i` is drawable; `undefined` until it has been checked. */
	get(i: number): boolean | undefined {
		const s = this.status[i]
		return s === 0 ? undefined : s === 1
	}

	/** Checks entries right away (the visible tiles); true if any turned out undrawable. */
	checkNow(indices: Iterable<number>): boolean {
		let removed = false
		for (const i of indices) if (this.status[i] === 0 && this.check(i) === 2) removed = true
		if (removed) this.dirty = true
		return removed
	}

	get progress() {
		return this.cursor / this.entries.length
	}

	private check(i: number): Status {
		const e = this.entries[i]
		let s: Status = 1
		if (!isInvisible(e)) {
			// Combining marks are tested bare, without the dotted circle tiles draw them on.
			const text = e.glyph.startsWith("◌") ? e.glyph.slice(1) : e.glyph
			if (this.tofu.has(this.signature(text))) s = 2
		}
		this.status[i] = s
		return s
	}

	/** Missing glyphs are slow to measure (the browser searches every font), and most of them are
	 * in big blocks no font has at all (newer CJK extensions, Tangut…). Sampling each big block
	 * first settles those in one go. */
	private sampleBlocks() {
		const n = this.entries.length
		for (let start = 0; start < n; ) {
			let end = start
			while (end < n && this.entries[end].block === this.entries[start].block) end++
			if (end - start >= 512) {
				const step = (end - start) / 48
				let missing = true
				for (let k = 0; k < 48 && missing; k++) {
					const i = start + Math.floor(k * step)
					if (this.status[i] === 0) this.check(i)
					missing = this.status[i] === 2
				}
				if (missing) this.status.fill(2, start, end)
			}
			start = end
		}
	}

	/** Checks everything else in idle time, a slice at a time, so startup stays quick. */
	private schedule() {
		if (this.pending) return
		const idle = window.requestIdleCallback ?? ((cb: IdleRequestCallback) => setTimeout(() => cb({ timeRemaining: () => 8, didTimeout: false }), 16))
		this.pending = idle((deadline) => {
			this.pending = 0
			const n = this.entries.length
			while (this.cursor < n && deadline.timeRemaining() > 1) {
				const end = Math.min(n, this.cursor + 200)
				for (; this.cursor < end; this.cursor++) {
					if (this.status[this.cursor] === 0 && this.check(this.cursor) === 2) this.dirty = true
				}
			}
			this.flush()
			if (this.cursor < n) this.schedule()
		}) as unknown as number
	}

	private flush() {
		if (!this.dirty) return
		this.dirty = false
		this.onChange?.()
		clearTimeout(this.saveTimer)
		this.saveTimer = window.setTimeout(() => this.save(), 1000)
	}

	/** Called after the UI has used `checkNow`, so other views and the saved copy catch up. */
	commit() {
		this.flush()
	}

	private save() {
		const bytes = new Uint8Array(Math.ceil(this.status.length / 4))
		for (let i = 0; i < this.status.length; i++) bytes[i >> 2] |= this.status[i] << ((i & 3) * 2)
		let binary = ""
		for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
		try {
			localStorage.setItem(this.storageKey, btoa(binary))
		} catch {
			// Full or blocked storage: results just aren't kept.
		}
	}

	/** The glyph's ink bounds, which the placeholders for missing glyphs all share. */
	private signature(text: string): string {
		const m = this.ctx.measureText(text)
		const r = (v: number) => Math.round(v * 100)
		return `${r(m.actualBoundingBoxLeft)} ${r(m.actualBoundingBoxRight)} ${r(m.actualBoundingBoxAscent)} ${r(m.actualBoundingBoxDescent)}`
	}
}

const blank = "0 0 0 0"
