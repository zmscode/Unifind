// Theme.swift's palette maths: eight source colours, with the panel shades mixed in between.
import { Category, type Palette } from "./data.ts"

export const defaultTheme = "Gruvbox Dark Soft"

/** Default glyph font: the system UI font, with the browser picking fallbacks for the rest. */
export const systemStack = "system-ui, -apple-system, 'Segoe UI', Roboto, 'Noto Sans', sans-serif"

export function fontStack(family: string) {
	if (!family) return systemStack
	const generic = ["serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui"]
	const quoted = generic.includes(family) ? family : `"${family.replace(/"/g, "")}"`
	return `${quoted}, ${systemStack}`
}

const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))

/** Background blended `t` of the way toward the text colour. */
function mix(p: Palette, t: number) {
	const a = rgb(p.background)
	const b = rgb(p.text)
	return `rgb(${a.map((v, i) => Math.round(v * (1 - t) + b[i] * t)).join(" ")})`
}

/** The theme's highlight colours, for giving each category its own tint. */
export const spectrum = (p: Palette) => [p.accent, p.attribute, p.smart, p.preprocessor, p.character]

export function tint(p: Palette, c: Category) {
	if (c === Category.all) return p.accent
	const s = spectrum(p)
	return s[c % s.length]
}

export function paletteVars(p: Palette): Record<string, string> {
	return {
		"--bg0": p.background,
		"--bg1": mix(p, 0.05),
		"--bg2": mix(p, 0.12),
		"--bg3": mix(p, 0.24),
		"--fg": p.text,
		"--fg4": mix(p, 0.68),
		"--gray": p.muted,
		"--accent": p.accent,
		"--smart": p.smart,
	}
}

export function applyTheme(p: Palette) {
	const root = document.documentElement
	const vars = { ...paletteVars(p), "color-scheme": p.isDark ? "dark" : "light" }
	for (const [k, v] of Object.entries(vars)) root.style.setProperty(k, v)
	try {
		localStorage.setItem("themeVars", JSON.stringify(vars))
	} catch {
		// Without storage the page starts in the default theme.
	}
	document.querySelector('meta[name="theme-color"]')?.setAttribute("content", p.background)
}
