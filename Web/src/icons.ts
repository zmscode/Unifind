// Phosphor icons (regular weight, with fill variants for "on" states), standing in for the SF
// Symbols the app uses.
import arrowSquareOut from "@phosphor-icons/core/assets/regular/arrow-square-out.svg?raw"
import arrowUpRight from "@phosphor-icons/core/assets/regular/arrow-up-right.svg?raw"
import clock from "@phosphor-icons/core/assets/regular/clock.svg?raw"
import copy from "@phosphor-icons/core/assets/regular/copy.svg?raw"
import currencyDollar from "@phosphor-icons/core/assets/regular/currency-dollar.svg?raw"
import cursorText from "@phosphor-icons/core/assets/regular/cursor-text.svg?raw"
import downloadSimple from "@phosphor-icons/core/assets/regular/download-simple.svg?raw"
import funnelSimple from "@phosphor-icons/core/assets/regular/funnel-simple.svg?raw"
import funnelSimpleFill from "@phosphor-icons/core/assets/fill/funnel-simple-fill.svg?raw"
import fn from "@phosphor-icons/core/assets/regular/function.svg?raw"
import gearSix from "@phosphor-icons/core/assets/regular/gear-six.svg?raw"
import gridFour from "@phosphor-icons/core/assets/regular/grid-four.svg?raw"
import gridNine from "@phosphor-icons/core/assets/regular/grid-nine.svg?raw"
import hash from "@phosphor-icons/core/assets/regular/hash.svg?raw"
import magnifyingGlass from "@phosphor-icons/core/assets/regular/magnifying-glass.svg?raw"
import quotes from "@phosphor-icons/core/assets/regular/quotes.svg?raw"
import selection from "@phosphor-icons/core/assets/regular/selection.svg?raw"
import smiley from "@phosphor-icons/core/assets/regular/smiley.svg?raw"
import sparkle from "@phosphor-icons/core/assets/regular/sparkle.svg?raw"
import sparkleFill from "@phosphor-icons/core/assets/fill/sparkle-fill.svg?raw"
import star from "@phosphor-icons/core/assets/regular/star.svg?raw"
import starFill from "@phosphor-icons/core/assets/fill/star-fill.svg?raw"
import textAa from "@phosphor-icons/core/assets/regular/text-aa.svg?raw"
import translate from "@phosphor-icons/core/assets/regular/translate.svg?raw"
import triangle from "@phosphor-icons/core/assets/regular/triangle.svg?raw"
import xIcon from "@phosphor-icons/core/assets/regular/x.svg?raw"
import { Category } from "./data.ts"

export interface Icon {
	regular: string
	fill?: string
}

export const icons = {
	search: { regular: magnifyingGlass },
	filter: { regular: funnelSimple, fill: funnelSimpleFill },
	sparkles: { regular: sparkle, fill: sparkleFill },
	settings: { regular: gearSix },
	star: { regular: star, fill: starFill },
	x: { regular: xIcon },
	copy: { regular: copy },
	download: { regular: downloadSimple },
	external: { regular: arrowSquareOut },
	clock: { regular: clock },
} satisfies Record<string, Icon>

/** The SF Symbols the app's sidebar uses, as their nearest Phosphor icons. */
export const categoryIcons: Record<Category, Icon> = {
	[Category.all]: { regular: gridNine },
	[Category.recents]: { regular: clock },
	[Category.emoji]: { regular: smiley },
	[Category.arrows]: { regular: arrowUpRight },
	[Category.shapes]: { regular: triangle },
	[Category.math]: { regular: fn },
	[Category.currency]: { regular: currencyDollar },
	[Category.punctuation]: { regular: quotes },
	[Category.letters]: { regular: textAa },
	[Category.numbers]: { regular: hash },
	[Category.symbols]: { regular: star },
	[Category.boxDrawing]: { regular: gridFour },
	[Category.marks]: { regular: cursorText },
	[Category.spaces]: { regular: selection },
	[Category.ideographs]: { regular: translate },
	[Category.favorites]: { regular: star },
}

export function icon(i: Icon, size = 16, filled = false): SVGElement {
	const template = document.createElement("template")
	template.innerHTML = (filled && i.fill) || i.regular
	const svg = template.content.firstElementChild as SVGElement
	svg.setAttribute("width", String(size))
	svg.setAttribute("height", String(size))
	svg.setAttribute("aria-hidden", "true")
	svg.classList.add("icon")
	return svg
}
