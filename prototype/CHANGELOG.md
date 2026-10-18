# Prototype change log

This file records prototype changes, newest first. Find each commit with `git log -- prototype/CHANGELOG.md`.
Use `## YYYY-MM-DD — title` and the Issue, Change, Reason, and Alternative considered fields for each entry.

## 2026-10-18 — Baseline of the current prototype

- Issue: Owner request, no issue.
- Change: Record the existing prototype without changing its render. It shows Staged and Unstaged streams, inline and full-file editing, unchanged-line folds, a file tree, folder and single-file windows, and a window bar. The harness simulates agent writes, staging, clean state, window changes, and light/dark appearance.
- Reason: Establish the visual and motion reference before future native UI changes. `DESIGN.md` owns product behavior. Preview with `blueprint preview prototype`.
- Alternative considered: A separate prototype or a native-only preview. Keep the existing interactive prototype so the owner always has one preview path.
