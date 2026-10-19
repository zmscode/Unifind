# Unifind

A native macOS Unicode character finder. Search by name, character or code point with
fuzzy, fzf-style matching, browse by category, and let Apple Intelligence (on device)
suggest related characters: type "shape" and get triangles, squares and circles too.

- Themes ported from Lines (Gruvbox, Catppuccin, Dracula, Ayu…) and a glyph font of your choice, in Settings (⌘,)
- Hover a character to see it in every weight its font has
- Double-click or ⏎ to copy; the bottom bar copies U+, HTML, Swift and the name

Requires macOS 26 or later on Apple silicon.

## Install

```sh
brew install --cask zmscode/unifind/unifind
```

Or from source: `just install` builds and copies it to /Applications.

## Develop

`just` lists the tasks: `just run`, `just test`, `just install`,
`just release` / `just publish` (see RELEASING.md).
