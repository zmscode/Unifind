// Turns a loose query ("shape", "happy", "weather") into words found in Unicode names, like the
// app's SmartSearch.swift: Chrome's built-in Prompt API (Gemini Nano, on device) when the
// browser has it, otherwise a small built-in synonym map.

export type Engine = "model" | "synonyms"

const instructions =
	"You help people find Unicode characters. The user types a loose description; you reply with " +
	"words that appear in official Unicode character names (as in the Unicode Character Database) " +
	"for characters that fit the description. Think about synonyms, examples and members of the " +
	'category. For example, "shape" -> TRIANGLE, SQUARE, CIRCLE, DIAMOND, LOZENGE, PENTAGON, ' +
	'HEXAGON, RECTANGLE, ELLIPSE, STAR, PARALLELOGRAM. "happy" -> SMILING, GRINNING, LAUGHING, JOY, ' +
	'BEAMING. "weather" -> SUN, CLOUD, RAIN, SNOWFLAKE, UMBRELLA, LIGHTNING, TORNADO. ' +
	"Give at least ten different words. Only output single words or two-word phrases that really occur in Unicode names."

const schema = {
	type: "object",
	properties: {
		terms: {
			type: "array",
			description:
				"Words that literally appear in official Unicode character names and match what the user is looking for, most relevant first. Use singular uppercase-style English words like TRIANGLE, ARROW, HEART.",
			items: { type: "string" },
			minItems: 10,
			maxItems: 20,
		},
	},
	required: ["terms"],
}

/** Words in so many names that they'd swamp the results ("face" matches every animal face). */
const tooGeneric = new Set([
	"face", "sign", "symbol", "letter", "mark", "small", "capital", "with", "black", "white",
	"emotion", "character", "glyph", "icon", "shape", "form", "type",
])

/** Chrome's Prompt API, which isn't in TypeScript's DOM types yet. */
interface LanguageModelSession {
	prompt(input: string, options?: { responseConstraint?: object; signal?: AbortSignal }): Promise<string>
	clone(options?: { signal?: AbortSignal }): Promise<LanguageModelSession>
	destroy(): void
}
interface LanguageModelStatic {
	availability(options?: object): Promise<"unavailable" | "downloadable" | "downloading" | "available">
	create(options?: object): Promise<LanguageModelSession>
}

const modelOptions = {
	initialPrompts: [{ role: "system", content: instructions }],
	expectedInputs: [{ type: "text", languages: ["en"] }],
	expectedOutputs: [{ type: "text", languages: ["en"] }],
}

export class SmartSearch {
	private static get api() {
		return (globalThis as unknown as { LanguageModel?: LanguageModelStatic }).LanguageModel
	}

	engine: Engine = "synonyms"
	/** Why the on-device model isn't being used, for the toggle's tooltip. */
	status = SmartSearch.api ? "Checking for Chrome's on-device model…" : "This browser has no on-device model"
	private base?: LanguageModelSession
	private cache = new Map<string, string[]>()
	onChange?: () => void

	async start() {
		const LanguageModel = SmartSearch.api
		if (!LanguageModel) return
		try {
			const availability = await LanguageModel.availability(modelOptions)
			if (availability === "available") await this.load()
			else if (availability === "unavailable") this.status = "Chrome's on-device model isn't available on this device"
			else this.status = "Chrome's on-device model isn't downloaded yet: turn Smart Search off and on to download it"
		} catch {
			this.status = "Chrome's on-device model isn't available"
		}
		this.onChange?.()
	}

	/** Downloading the model needs a click, so the Smart Search toggle calls this too. */
	async load() {
		const LanguageModel = SmartSearch.api
		if (!LanguageModel || this.base) return
		try {
			this.base = await LanguageModel.create({
				...modelOptions,
				monitor: (m: EventTarget) =>
					m.addEventListener("downloadprogress", (e) => {
						this.status = `Downloading Chrome's on-device model… ${Math.round((e as ProgressEvent).loaded * 100)}%`
						this.onChange?.()
					}),
			})
			this.engine = "model"
			this.status = "Smart Search uses Chrome's on-device model to find related characters"
		} catch {
			this.status = "Chrome's on-device model couldn't start"
		}
		this.onChange?.()
	}

	get help() {
		return this.engine === "model" ? this.status : `Smart Search uses built-in synonyms. ${this.status}.`
	}

	async expand(query: string, signal?: AbortSignal): Promise<string[]> {
		const key = query.trim().toLowerCase()
		if (key.length < 2 || !/\p{L}/u.test(key)) return []
		const hit = this.cache.get(key)
		if (hit) return hit

		let terms: string[] = []
		if (this.base) {
			try {
				// A fresh session per query, so earlier answers don't steer this one.
				const session = await this.base.clone({ signal })
				const reply = await session.prompt(`Find Unicode characters for: ${key}`, { responseConstraint: schema, signal })
				session.destroy()
				terms = (JSON.parse(reply) as { terms: string[] }).terms ?? []
			} catch (e) {
				if (signal?.aborted) throw e
				// Guardrail or model errors: fall back to the synonyms below.
			}
		}
		if (!terms.length) terms = synonymsFor(key)

		const seen = new Set<string>()
		terms = terms
			.map((t) => t.toLowerCase().trim())
			.filter((t) => t && t !== key && !tooGeneric.has(t) && !seen.has(t) && (seen.add(t), true))
		this.cache.set(key, terms)
		return terms
	}
}

/** Each query word's concept, singular or plural, looked up in the map below. */
function synonymsFor(query: string): string[] {
	const out: string[] = []
	for (const word of query.split(/[^\p{L}\p{N}]+/u)) {
		const forms = [word, word.replace(/ies$/, "y"), word.replace(/e?s$/, "")]
		for (const f of forms) {
			const list = synonyms[f] ?? synonyms[aliases[f]]
			if (list) {
				out.push(...list)
				break
			}
		}
	}
	return out
}

const aliases: Record<string, string> = {
	shapes: "shape", geometry: "shape", geometric: "shape", smile: "happy", smiley: "happy", joy: "happy",
	glad: "happy", cheerful: "happy", unhappy: "sad", upset: "sad", cry: "sad", mad: "angry",
	climate: "weather", sky: "weather", song: "music", sound: "music", note: "music", pet: "animal",
	creature: "animal", beast: "animal", direction: "arrow", pointer: "arrow", money: "currency",
	cash: "currency", price: "currency", love: "heart", romance: "heart", tick: "check",
	checkmark: "check", yes: "check", no: "cross", wrong: "cross", cancel: "cross", meal: "food",
	eat: "food", drink: "food", fruit: "food", vehicle: "transport", travel: "transport", car: "transport",
	plant: "nature", flower: "nature", tree: "nature", sport: "sports", game: "games", play: "games",
	maths: "math", mathematics: "math", equation: "math", calculator: "math", time: "clock",
	hour: "clock", calendar: "clock", tool: "tools", office: "tools", work: "tools", danger: "warning",
	alert: "warning", caution: "warning", hand: "hands", gesture: "hands", person: "people",
	human: "people", family: "people", flag: "flags", country: "flags", building: "places",
	house: "places", home: "places", space: "astronomy", planet: "astronomy", celestial: "astronomy",
	box: "lines", border: "lines", frame: "lines", table: "lines", bullet: "bullets", list: "bullets",
	quote: "quotes", brackets: "bracket", parenthesis: "bracket", religion: "religious", faith: "religious",
	zodiac: "astrology", horoscope: "astrology", chess: "games", card: "games", dice: "games",
	computer: "technology", phone: "technology", tech: "technology", keyboard: "technology",
	medical: "health", medicine: "health", hospital: "health", fire: "hot", cold: "winter", snow: "winter",
	christmas: "winter", party: "celebration", birthday: "celebration", festive: "celebration",
	scary: "spooky", halloween: "spooky", ghost: "spooky", fast: "speed", power: "energy",
	electricity: "energy", lock: "security", key: "security", secret: "security", mail: "communication",
	letter: "communication", message: "communication", chat: "communication", sleepy: "tired", sleep: "tired",
	ok: "check", done: "check", correct: "check", stop: "cross", delete: "cross", plus: "math", minus: "math",
	equal: "math", infinity: "math", greek: "greek", ornament: "decoration", fancy: "decoration",
	pretty: "decoration", divider: "decoration", star: "stars", sparkle: "stars", shine: "stars",
}

const synonyms: Record<string, string[]> = {
	shape: ["triangle", "square", "circle", "diamond", "lozenge", "pentagon", "hexagon", "rectangle", "ellipse", "star", "parallelogram", "octagon", "trapezium"],
	happy: ["smiling", "grinning", "laughing", "joy", "beaming", "smile", "grin", "relieved", "hugging", "star-struck"],
	sad: ["crying", "frowning", "tear", "disappointed", "pensive", "sob", "worried", "broken heart", "anguished", "weary"],
	angry: ["angry", "pouting", "rage", "steam", "cursing", "anger", "frowning", "furious", "symbol anger"],
	weather: ["sun", "cloud", "rain", "snowflake", "umbrella", "lightning", "tornado", "fog", "thunder", "snowman", "rainbow", "wind", "droplet"],
	music: ["musical", "note", "notes", "clef", "flat", "sharp", "natural", "guitar", "piano", "drum", "violin", "trumpet", "saxophone", "microphone", "headphone"],
	animal: ["cat", "dog", "horse", "cow", "pig", "mouse", "rabbit", "monkey", "bird", "fish", "snake", "tiger", "lion", "bear", "elephant", "frog", "turtle"],
	arrow: ["arrow", "arrowhead", "harpoon", "pointing", "rightwards", "leftwards", "upwards", "downwards", "chevron", "triangle-headed"],
	currency: ["currency", "dollar", "euro", "pound", "yen", "rupee", "won", "bitcoin", "coin", "money", "banknote", "cent", "lira", "peso"],
	heart: ["heart", "hearts", "love", "kiss", "cupid", "valentine", "ribbon", "rose"],
	check: ["check", "tick", "ballot", "heavy check", "white check", "checkbox", "ok"],
	cross: ["cross", "multiplication", "ballot x", "saltire", "prohibited", "no entry", "cancellation", "heavy multiplication"],
	food: ["apple", "banana", "bread", "cheese", "pizza", "hamburger", "cake", "cookie", "coffee", "tea", "beer", "wine", "rice", "noodle", "grapes", "cherries", "taco"],
	transport: ["car", "bus", "train", "airplane", "bicycle", "ship", "boat", "rocket", "taxi", "truck", "motorcycle", "tram", "helicopter", "automobile"],
	nature: ["flower", "tree", "leaf", "herb", "blossom", "rose", "tulip", "sunflower", "cactus", "seedling", "mushroom", "maple", "clover", "palm"],
	sports: ["ball", "football", "basketball", "baseball", "tennis", "golf", "trophy", "medal", "skier", "swimmer", "runner", "boxing", "volleyball"],
	games: ["chess", "playing card", "die", "domino", "mahjong", "joystick", "game", "puzzle", "dice", "spade", "club", "diamond", "pawn", "knight"],
	math: ["plus", "minus", "multiplication", "division", "equals", "integral", "summation", "infinity", "square root", "less-than", "greater-than", "element", "subset", "union", "intersection", "not equal"],
	clock: ["clock", "watch", "hourglass", "stopwatch", "timer", "alarm", "calendar", "o'clock"],
	tools: ["hammer", "wrench", "scissors", "pencil", "pen", "paperclip", "pushpin", "ruler", "gear", "key", "lock", "briefcase", "clipboard", "file"],
	warning: ["warning", "caution", "radioactive", "biohazard", "exclamation", "prohibited", "no entry", "high voltage", "siren", "skull"],
	hands: ["hand", "finger", "thumbs", "fist", "pointing", "clapping", "waving", "palm", "victory", "ok hand", "raised hand", "handshake"],
	people: ["man", "woman", "person", "boy", "girl", "baby", "child", "adult", "family", "couple", "people", "older"],
	flags: ["flag", "chequered", "pennant", "triangular flag", "waving", "regional indicator"],
	places: ["house", "building", "office", "hospital", "school", "church", "castle", "tower", "stadium", "factory", "mountain", "beach", "city"],
	astronomy: ["sun", "moon", "star", "planet", "comet", "saturn", "earth", "globe", "crescent", "telescope", "satellite", "rocket", "milky way"],
	lines: ["box drawings", "horizontal", "vertical", "light", "heavy", "double", "corner", "block", "shade", "dash"],
	bullets: ["bullet", "middle dot", "triangular bullet", "hyphen bullet", "circle", "black small square", "dot"],
	quotes: ["quotation", "guillemet", "apostrophe", "prime", "quote"],
	bracket: ["bracket", "parenthesis", "brace", "angle bracket", "ceiling", "floor", "corner bracket"],
	religious: ["cross", "star of david", "crescent", "om", "wheel of dharma", "yin yang", "menorah", "peace", "khanda", "ankh", "church", "mosque", "synagogue"],
	astrology: ["aries", "taurus", "gemini", "cancer", "leo", "virgo", "libra", "scorpius", "sagittarius", "capricorn", "aquarius", "pisces", "ophiuchus"],
	technology: ["computer", "keyboard", "mouse", "telephone", "mobile phone", "laptop", "printer", "battery", "plug", "disk", "floppy", "television", "camera", "satellite"],
	health: ["pill", "syringe", "stethoscope", "hospital", "bandage", "medical", "staff of aesculapius", "caduceus", "dna", "microbe", "thermometer"],
	hot: ["fire", "flame", "hot", "sun", "volcano", "pepper", "thermometer", "sweat"],
	winter: ["snowflake", "snowman", "snow", "ice", "freezing", "cold", "skier", "christmas", "mitten", "scarf"],
	celebration: ["party", "balloon", "confetti", "fireworks", "sparkler", "gift", "cake", "birthday", "tada", "champagne", "bottle with popping cork", "ribbon"],
	spooky: ["ghost", "skull", "jack-o-lantern", "bat", "spider", "web", "zombie", "vampire", "crossbones", "coffin"],
	speed: ["lightning", "rocket", "high-speed", "racing", "dash", "runner", "zap", "fast"],
	energy: ["lightning", "high voltage", "battery", "plug", "power", "atom", "fire", "electric"],
	security: ["lock", "key", "shield", "padlock", "locked", "unlocked", "closed lock", "eye", "ninja"],
	communication: ["envelope", "mail", "telephone", "speech balloon", "inbox", "outbox", "postbox", "mailbox", "satellite", "antenna", "loudspeaker", "megaphone"],
	tired: ["sleeping", "sleepy", "yawning", "zzz", "bed", "weary", "tired", "moon"],
	decoration: ["ornament", "fleuron", "floral", "hedera", "dingbat", "asterisk", "star", "flower", "leaf", "rotated heavy black heart"],
	stars: ["star", "sparkle", "sparkles", "asterisk", "glowing star", "dizzy", "shooting star", "pentagram", "stars"],
	greek: ["alpha", "beta", "gamma", "delta", "epsilon", "lambda", "mu", "pi", "sigma", "omega", "theta", "phi", "psi"],
	cat: ["cat", "kitten", "lion", "tiger", "leopard", "paw"],
	dog: ["dog", "poodle", "wolf", "fox", "paw", "guide dog", "service dog"],
	bird: ["bird", "eagle", "owl", "duck", "penguin", "chicken", "rooster", "dove", "parrot", "swan", "flamingo", "peacock"],
	sea: ["fish", "whale", "dolphin", "octopus", "shark", "crab", "shell", "wave", "squid", "lobster", "anchor", "boat"],
	water: ["water", "droplet", "wave", "ocean", "rain", "fountain", "potable water", "shower", "bathtub", "ice"],
	write: ["pencil", "pen", "fountain pen", "writing hand", "memo", "paper", "scroll", "notebook", "ink", "crayon"],
	book: ["book", "books", "notebook", "ledger", "bookmark", "scroll", "page", "newspaper", "library"],
	eye: ["eye", "eyes", "glasses", "sunglasses", "telescope", "microscope", "magnifying glass", "visible"],
}
