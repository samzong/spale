# Prototype change log

This file records prototype changes, newest first. Find each commit with `git log -- prototype/CHANGELOG.md`.
Use `## YYYY-MM-DD — title` and the Issue, Change, Reason, and Alternative considered fields for each entry.

## 2026-11-02 — Symbols icons in the file tree

- Issue: Owner request, no issue.
- Change: File tree rows show colored file and folder icons from the Symbols icon theme (MIT, `miguelsolorio/vscode-symbols`) instead of two monochrome SF Symbols. Icons follow the theme's file name, extension, and folder name rules. Hidden entries show their icon at half opacity. Title bar buttons and the FILES chevron keep SF Symbols.
- Reason: Two generic glyphs did not tell file types apart, and the owner found them arbitrary. A maintained theme gives a recognizable icon for each common type.
- Alternative considered: Keep SF Symbols with a per-type glyph and tint. It adds no assets, but it covers far fewer types and needs a hand-maintained mapping.

## 2026-10-18 — Baseline of the current prototype

- Issue: Owner request, no issue.
- Change: Record the existing prototype without changing its render. It shows Staged and Unstaged streams, inline and full-file editing, unchanged-line folds, a file tree, folder and single-file windows, and a window bar. The harness simulates agent writes, staging, clean state, window changes, and light/dark appearance.
- Reason: Establish the visual and motion reference before future native UI changes. `DESIGN.md` owns product behavior. Preview with `blueprint preview prototype`.
- Alternative considered: A separate prototype or a native-only preview. Keep the existing interactive prototype so the owner always has one preview path.
