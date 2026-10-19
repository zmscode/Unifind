import {
	ArrowUpRight, Clock, Copy, CornerDownLeft, DollarSign, Download, ExternalLink, Grid2x2, Grid3x3,
	Hash, Languages, ListFilter, Quote, Search, Settings, Sigma, Smile, Space, Sparkles, Star,
	TextCursor, Triangle, Type, X, createElement, type IconNode,
} from "lucide"
import { Category } from "./data.ts"

export const icons = {
	search: Search, filter: ListFilter, sparkles: Sparkles, settings: Settings, star: Star, x: X,
	copy: Copy, enter: CornerDownLeft, download: Download, external: ExternalLink, clock: Clock,
}

/** The SF Symbols the app's sidebar uses, as their nearest Lucide icons. */
export const categoryIcons: Record<Category, IconNode> = {
	[Category.all]: Grid3x3,
	[Category.recents]: Clock,
	[Category.emoji]: Smile,
	[Category.arrows]: ArrowUpRight,
	[Category.shapes]: Triangle,
	[Category.math]: Sigma,
	[Category.currency]: DollarSign,
	[Category.punctuation]: Quote,
	[Category.letters]: Type,
	[Category.numbers]: Hash,
	[Category.symbols]: Star,
	[Category.boxDrawing]: Grid2x2,
	[Category.marks]: TextCursor,
	[Category.spaces]: Space,
	[Category.ideographs]: Languages,
	[Category.favorites]: Star,
}

export function icon(node: IconNode, size = 16, filled = false): SVGElement {
	const svg = createElement(node, { width: size, height: size, "stroke-width": 2 })
	svg.classList.add("icon")
	if (filled) svg.setAttribute("fill", "currentColor")
	return svg
}
