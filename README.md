# Unifind

A native macOS Unicode character finder. Search by name, character or code point with
fuzzy, fzf-style matching, browse by category, and let Apple Intelligence (on device)
suggest related characters: type "shape" and get triangles, squares and circles too.

- Themes ported from Lines (Gruvbox, Catppuccin, Dracula, Ayu…) and a glyph font of your choice, in Settings (⌘,)
- Hover a character to see it in every weight its font has
- Double-click or ⏎ to copy; the bottom bar copies U+, HTML, Swift and the name

Requires macOS 26 or later on Apple silicon.

**Try it in your browser:** [zmscode.github.io/Unifind](https://zmscode.github.io/Unifind/), the web
version, with the same search over the same character data. ⏎ copies instead of pasting, and
Smart Search uses Chrome's on-device model where available (built-in synonyms elsewhere).

## Install

```sh
brew install --cask zmscode/unifind/unifind
```

Or from source: `just install` builds and copies it to /Applications.

## Develop

`just` lists the tasks: `just run`, `just test`, `just install`,
`just release` / `just publish` (see RELEASING.md).

The web version lives in `Web/` (TypeScript and Vite, no framework). `just web-data` exports the
app's character index and themes to `Web/public/data`, `just web` runs a dev server and
`just web-build` builds the static site into `Web/dist`. Pushing to `main` deploys it to GitHub
Pages (`.github/workflows/pages.yml`).
