# Prototype change log

This file records prototype changes, newest first. Find each commit with `git log -- prototype/CHANGELOG.md`.
Use `## YYYY-MM-DD — title` and the Issue, Change, Reason, and Alternative considered fields for each entry.

## 2026-11-05 — Selected narrow layouts for conflicts, paths, and windows

- Issue: Owner request, C01–C03 in the design audit. No issue.
- Change: C01 keeps both conflict actions on a second row when narrow and uses one row when wide. C02 A keeps full paths when they fit, removes leading directories before shortening filenames, and shows the full path on hover whenever text is elided. C03 scrolls full window names horizontally and reveals the current window only when the current window, window list, or bar width changes. Editing and refresh preserve manual scrolling. Rename headers retain both filenames and the arrow before falling back to the new filename. Remove alternative controls; retain light/dark scenes and width, path, and window-count fixtures. Keep the scenario controls at a 16px gap.
- Reason: Fixed frames hide conflict actions, filenames, and later windows. These are the owner’s selected layouts. The prototype conflict strings change from Chinese to the native English strings: Changed on disk, Keep my version, and Use disk version. The sidebar, save behavior, and opening order stay the same.
- Alternative considered: Stacking each conflict action uses more reading height. Growing headers moves code down. Middle-truncating the whole path hides useful filenames too soon. Equal-width window labels hide distinct endings. The owner chose the layouts above.

## 2026-11-05 — Collapsible changed-files section

- Issue: Owner request, no issue.
- Change: CHANGED FILES now uses the same 40 px disclosure row and 380 ms ease as FILES. An empty or clean state collapses it by default, and FILES takes the remaining space. A click stores the choice per window. The harness can keep that choice or follow clean-state changes.
- Reason: The two sidebar sections need a shared collapse interaction while retaining the file tree when there are no changes.
- Alternative considered: Reset the section to its count-based default after each clean-state change. Keep a manual choice instead because a clean-state toggle should not override the user's selection.

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
