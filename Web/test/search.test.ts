// The Mac app's SearchTests, run against the exported data.
import { readFileSync } from "node:fs"
import { test } from "node:test"
import assert from "node:assert/strict"
import { decode, Category, maskOf } from "../src/data.ts"
import { CharacterIndex, boundaryRuns, defaultFilter } from "../src/search.ts"

const file = JSON.parse(readFileSync(new URL("../public/data/characters.json", import.meta.url), "utf8"))
let t0 = performance.now()
const index = new CharacterIndex(decode(file))
console.log("index built in", Math.round(performance.now() - t0), "ms")

const top = (q: string, n = 5, category: Category = Category.all) =>
	index.search(q, { ...defaultFilter(), category, includeUnrenderable: true }).slice(0, n).map((i) => index.entries[i].name)

test("exact word ranks first", () => {
	assert.deepEqual(top("snowman", 1), ["SNOWMAN"])
	assert.ok(top("right arrow", 5).includes("RIGHTWARDS ARROW"))
	assert.ok(index.search("heart").length < 500)
})

test("typos and prefixes", () => {
	assert.ok(top("snowmen", 3).includes("SNOWMAN"))
	assert.ok(top("triangel", 10).some((n) => n.includes("TRIANGLE")))
	assert.ok(top("lozen", 3).some((n) => n.includes("LOZENGE")))
})

test("initials", () => {
	assert.ok(top("bupt", 3).includes("BLACK UP-POINTING TRIANGLE"))
	assert.ok(top("rarr", 5).includes("RIGHTWARDS ARROW"))
	assert.equal(boundaryRuns("bupt", "black up-pointing triangle"), 3)
	assert.equal(boundaryRuns("lack", "black"), undefined)
})

test("literal and code point", () => {
	assert.deepEqual(top("→", 1), ["RIGHTWARDS ARROW"])
	assert.deepEqual(top("U+2603", 1), ["SNOWMAN"])
})

test("categories", () => {
	const shapes = index.indices({ ...defaultFilter(), category: Category.shapes }).map((i) => index.entries[i].name)
	assert.ok(shapes.includes("BLACK UP-POINTING TRIANGLE"))
	assert.ok(top("euro", 3, Category.currency).includes("EURO SIGN"))
})

test("related terms", () => {
	const r = index.related(["triangle", "squares"])
	assert.ok(r.length > 50)
	assert.ok(!r.slice(0, 20).map((i) => index.entries[i].name).includes("SQUARE ROOT"))
})

test("blocks", () => {
	assert.ok(top("shape", 200).includes("BLACK UP-POINTING TRIANGLE"))
	assert.equal(index.entries[index.byScalar.get(0x25b2)!].block, "Geometric Shapes")
	const noEmoji = { ...defaultFilter(), hidden: maskOf(Category.emoji) }
	assert.ok(!index.search("heart", noEmoji).some((i) => index.entries[i].id === 0x1f496))
})

test("timing samples", () => {
	for (const q of ["shape", "heart", "arow", "right arrow", "bupt", "wsq"]) {
		t0 = performance.now()
		const r = index.search(q)
		console.log(q, Math.round(performance.now() - t0), "ms", r.length, r.slice(0, 30).map((i) => index.entries[i].glyph).join(" "))
	}
})
