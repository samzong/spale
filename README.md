# spale

<img src="Resources/logo.svg" alt="spale" width="64" height="64">

spale is a native macOS reader for live Git changes and a plain-text editor. It uses Swift and AppKit.

Run `make install` on macOS 14 or later with Apple Command Line Tools and one Apple Development signing identity. The installer builds and signs `/Applications/spale.app`. It links `spale` and `code` in `/opt/homebrew/bin` to the app, so `code .` works like `spale .`. Save any open spale documents before installation. Run `make` to list the other targets.

Run `spale` from a Git working tree, or run `spale <path>`. A file inside a repository opens in its full-file view. A file outside a repository opens in a text window. Use `make check` for the focused contract tests.

spale reads Git with `/usr/bin/git --no-optional-locks`. It never stages, commits, or changes Git state. Edits stay in memory until Save. The Staged stream is read-only.

`DESIGN.md` is the product specification. `prototype/` contains the visual reference with fixed sample data.
