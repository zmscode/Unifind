import { readFileSync } from "node:fs"
import { defineConfig } from "vite"

export default defineConfig({
	// Relative, so the build works at zmscode.github.io/Unifind/ and anywhere else.
	base: "./",
	define: {
		__APP_VERSION__: JSON.stringify(readFileSync(new URL("../VERSION", import.meta.url), "utf8").trim()),
	},
	build: { target: "es2022" },
})
