// SmartSearch with a stand-in for Chrome's Prompt API, and the synonym fallback.
import { test } from "node:test"
import assert from "node:assert/strict"
import { SmartSearch } from "../src/smart.ts"

test("synonyms without a model", async () => {
	const smart = new SmartSearch()
	assert.equal(smart.engine, "synonyms")
	const shape = await smart.expand("shapes")
	assert.ok(shape.includes("triangle") && shape.includes("lozenge"))
	assert.ok((await smart.expand("happy")).includes("smiling"))
	assert.deepEqual(await smart.expand("x"), [])
})

test("the on-device model, with too-generic words filtered", async () => {
	const prompts: string[] = []
	const session = {
		prompt: async (input: string, options?: { responseConstraint?: object }) => {
			prompts.push(input)
			assert.ok(options?.responseConstraint)
			return JSON.stringify({ terms: ["SUN", "Cloud", "face", "symbol", "weather", "sun", "RAIN"] })
		},
		clone: async () => session,
		destroy() {},
	}
	;(globalThis as Record<string, unknown>).LanguageModel = {
		availability: async () => "available",
		create: async (options: { initialPrompts: { content: string }[] }) => {
			assert.match(options.initialPrompts[0].content, /Unicode character names/)
			return session
		},
	}
	const smart = new SmartSearch()
	await smart.start()
	assert.equal(smart.engine, "model")
	assert.deepEqual(await smart.expand("Weather"), ["sun", "cloud", "rain"])
	assert.deepEqual(prompts, ["Find Unicode characters for: weather"])
	await smart.expand("weather ")
	assert.equal(prompts.length, 1, "answers are cached")
	delete (globalThis as Record<string, unknown>).LanguageModel
})
