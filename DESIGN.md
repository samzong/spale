# spale design

This document is the authoritative product and interaction specification for the native app. The interactive prototype in `prototype/` is the visual and motion reference; where the two differ, this document wins. The prototype's footer controls (open window, close window, new file, git add, appearance, agent update, clean state) only simulate the outside world and are not part of the product.

## Product

spale does two things, in priority order:

1. **Live reader of uncommitted changes.** It shows what an agent (or anyone) is changing in a Git working tree right now: staged and unstaged changes against `HEAD`, updated live as files are written.
2. **The most basic plain-text editor.** Mainstream editors have turned into agent tools; spale keeps a plain editor for the moments the user wants to change a file themselves.

Platform and stack: macOS only, Swift and AppKit, no SwiftUI, zero configuration, no settings window.

### Boundary

spale never performs a Git operation and never writes Git state. It has no history, log, blame, commit, stage, unstage, checkout, branch switching, stash, or remote features. It reads the working tree, the index, and `HEAD`, and nothing else. Every save checks the destination again, including Save As and symbolic links. Git metadata in ordinary repositories, bare repositories, and separate Git directories is protected. A rejected save preserves the document's path and unsaved edits. This protection does not repair earlier changes to Git metadata.

The editor excludes project search, multiple cursors, completion, language servers, formatting, bracket pairing, plugins, tabs, split panes, and a terminal.

Moving this boundary requires proof of value and an explicit owner decision.

### Interaction principle

Every shortcut and every mode is a cost to the user. Add none unless it is necessary. The user operates spale with ordinary computer habits: click, scroll, type, the arrow keys, and standard macOS commands. Nothing has to be learned.

Keyboard commands are exactly these; anything else must be clickable UI:

| Keys | Action |
|---|---|
| ⌘S, ⇧⌘S | Save, Save As |
| ⌘Z, ⇧⌘Z | Undo, Redo |
| ⌘F, ⌘G, ⇧⌘G | System find bar in the current text |
| ⌘X, ⌘C, ⌘V, ⌘A, ⌘H, ⌘M, ⌘Q | Standard macOS editing and app commands |
| ⌘N, ⌘W | New file, Close window |
| ⌘B | Show or hide the sidebar |
| ⌃⌘F | Enter or exit full screen, in repository and single-file windows |
| Tab | Indent, following the file's existing indentation |
| Esc | Return from the full-file view to the stream |

There are no single-key commands, no reading or editing modes, no ⌘1…⌘9, and no stream-switching shortcut.

### Quality bar

spale must feel like a top-tier professional tool the instant it opens: unified, restrained, refined, and orderly. Nothing may look cheap, assembled from parts, static, or feature-stuffed. Interaction design, typography, spacing, and motion are release criteria, not polish. Every surface follows the tokens and motion rules below; any element that does not earn its place is removed.

## Windows

### Repository windows

One window per repository root or worktree root, deduplicated by real path. Native window tabs are disabled (`tabbingMode = .disallowed`).

Layout, top to bottom: title bar, sidebar plus reader, window bar.

**Title bar.** Left-aligned next to the traffic lights, stated once:

- Main checkout: `ledger  main`
- Linked worktree: `ledger › review-5  feat/review`

The branch is dimmed. A `●` follows the name while any file in the window has unsaved edits. The title never contains a file path. On the right are icon buttons: Previous change, Next change, and a source toggle. The toggle uses code brackets for Show source and text lines for Show changes. It stays in the same position in both views.

**Sidebar.** Header `CHANGED FILES` with the number of unique files across both groups. Two groups, `Staged` and `Unstaged`, each listing its files. A partially staged file appears in both. Each row shows the group's real Git status letter, coloured, with no background:

| Letter | Meaning | Colour |
|---|---|---|
| A | Added | add green |
| U | Untracked | add green |
| M | Modified | neutral |
| D | Deleted | remove red, name struck through |
| R | Renamed | blue, shown as `old → new` |

The Staged group uses the `HEAD`→index status; the Unstaged group uses the index→worktree status. The heading of the group whose stream is showing is highlighted. ⌘B collapses the sidebar and the reader takes the full width.

**Window bar.** A one-line bar at the bottom listing every open spale document window, from the left, in opening order. The current window is highlighted. Labels are `repo` or `repo › worktree` for repository windows, the folder name for folder windows, and the file name for single-file windows, with `●` for unsaved edits. Clicking a label brings that window forward, including its display and Space. The bar never opens windows and updates live as windows open and close.

### Folder windows and file trees

A folder outside Git opens one window per real path. Its title and window bar label use the folder name. It has a `FILES` tree and an editable full-file reader. It has no streams, Git status, change marks, change navigation, or source toggle. Before a file opens, the reader says `Choose a file in the sidebar.`

Repository windows keep `CHANGED FILES` above `FILES` in the same sidebar. Each region has its own scroll area and one background selection signal. The regions share the height equally. Collapsing the `FILES` heading gives its space to `CHANGED FILES`. This keeps both lists available without a new sidebar mode. A top switch is the alternative, but it hides one list and adds a mode.

Clicking a file in `FILES` opens its full-file view. In a repository, Back or Esc returns to the current stream. In a folder window, the full-file reader stays open. The existing keyboard table does not change.

The tree reflects only the file system. It shows ignored files and folders with the same style as other entries, without Git status letters or colors. Names that start with `.` use secondary text color; their children keep their own styles. An entry named `.git`, whether a file or folder, is hidden at every level. Folders sort before files. Each group sorts by name without case sensitivity, with dot-prefixed names in normal lexical order. Empty folders have no disclosure arrow and cannot expand. A folder containing only `.git` is empty for this purpose. Directory symbolic links do not expand. This avoids cycles and traversal outside the root. File symbolic links resolve before opening and saving, so saving preserves the link. Git metadata remains read-only. Git metadata directories, including bare repositories, cannot be folder roots.

Directory listings and direct-child emptiness checks run on a background queue. Only the root and expanded directories refresh. Collapsed descendants are not scanned. Each directory shows at most 2,000 entries. An additional row says `Only the first 2,000 items are shown.` The subset follows directory enumeration order, then sorts for display. This bounds work in a large flat folder without building a recursive index. Revisit this limit if ordinary projects hit the message. A Git file index is the alternative, but it requires a separate path for ordinary folders and omits ignored content.

FSEvents refreshes expanded directories and open buffers. Tree refreshes run one at a time and merge pending requests into one follow-up refresh. Events only inside Git metadata do not refresh the tree. An empty root shows `This folder is empty.` Expansion and collapse use 380 ms and the existing ease curve; Reduce Motion disables animation. Unavailable directories show `This folder is unavailable.` They keep a disclosure arrow instead of appearing empty. Window restoration uses AppKit state for the root, selected file, sidebar visibility, expanded directories, and collapsed `FILES` heading. No separate persistence layer is used.

When an open file becomes unavailable, the reader preserves its last content and unsaved edits. It shows `File unavailable` and disables editing. `Use disk version` is unavailable until the file can be read again. For unsaved edits, `Keep my version` saves the preserved text.

### Single-file windows

Used for a file outside any repository, and for new files. No sidebar, no file header, no stream: the title shows the file name once, and the text starts at the first line, like TextEdit. The window bar is still shown.

## Reading

### Two streams

A repository window has two continuous streams. Each concatenates the diffs of its files in sidebar order.

- **Unstaged stream**: index → worktree. What changed since the last `git add`. Open by default. Editable.
- **Staged stream**: `HEAD` → index. What would be committed. Strictly read-only, because its right side is the index snapshot, not a file on disk.

Clicking a group heading switches to that stream. Clicking anywhere in a file row, including its counts and blank space, switches to that stream and scrolls to that file. When `git add` runs in a terminal, the added changes move from the Unstaged stream to the Staged stream live.

Reading position, expanded folds, caret, and collapsed files are kept per window and per stream. Switching streams restores each stream exactly where it was left.

### Stream content

- Each file starts with a file header row: status, path, and `+N −N` counts. Clicking the header row collapses or expands that file's diff. Collapsed files are skipped by Previous/Next change. A collapsed file expands automatically when an agent writes to it, including when it has unsaved edits, so new content and the `Changed on disk` banner are never hidden. Collapse state lives in memory only.
- Deleted lines are shown as read-only red rows. Added lines are green. Within a changed line pair, the changed words are highlighted.
- Unchanged runs of four or more lines between hunks collapse into a `N unchanged lines` fold. Clicking it expands the lines in place and turns its arrow over; clicking it again folds them.
- In the Staged stream, `.md` and `.markdown` files render as prose with added and removed blocks marked. Headings, paragraphs, lists, quotes, code, tables, and HTTP(S) links use the native Markdown parser. Block comparison includes structure and link destinations; line wrapping alone does not mark unchanged prose. Images do not fetch remote content. The source toggle opens the full-file view. Everywhere else, every file is plain text with syntax highlighting.
- Markdown parsing and comparison run with the repository computation off the main thread. Native attributed text keeps prose in the existing reader without a web view or another rendering dependency. Tables use native text cells to preserve empty columns, column alignment, and wrapping within each cell. Save protection belongs to the shared document write boundary so menu saves and AppKit save operations use the same check.
- When an agent write changes a visible line, that line shows a soft highlight that fades over 3 seconds. The view never jumps: the reading position is anchored to the line under the reader, even when the write splits or merges the fold that line was in.
- Empty streams read `No unstaged changes.` or `No staged changes.` A repository with no changes at all reads `No changes. A little room to think.`

### Full-file view

Show source opens the current file's whole content from disk, editable, with changes marked against `HEAD`: added and modified lines carry a gutter mark, and deleted lines appear as a marker at their boundary. It is the same view from either stream, so a fully staged file can still be edited.

Its file header is identical to the stream's header for that file. Clicking another file in the sidebar shows that file's full content and stays in the full-file view. Clicking the same toggle, now Show changes, or pressing Esc returns to the stream at the exact position it was opened from.

### Navigation

Previous change and Next change move through change blocks across files in the current stream, skipping collapsed files. Scrolling, clicking, and the sidebar cover everything else.

## Editing

Editing is NSTextView plus NSDocument behaviour; prefer what AppKit already provides.

- **Where.** In the Unstaged stream the added and context lines are the worktree file itself: click anywhere and type; deleted rows are not editable. The full-file view and single-file windows are fully editable. The Staged stream is never editable.
- **Live diff.** While typing, the diff is recomputed from the edited buffer, so rows change colour immediately without saving. When an edit makes a file equal to the index, the file leaves the Unstaged stream and the view moves to that file's full-file view with the caret kept in place.
- **Saving.** Explicit ⌘S only, and it saves only the file holding the caret; other edited files stay unsaved until the user saves them. Never write the original file automatically, because half-typed code would be read by the agent or a build. There is no autosave or draft copy: unsaved edits live only in the open window. Untitled files go through Save As. Closing a window with unsaved edits asks first.
- **Defaults.** Fira Code; smart quotes, smart dashes, autocorrect, and spell checking off; Return keeps the previous line's indentation; Tab follows the file's existing indentation and inserts a tab character when it cannot be determined; syntax highlighting stays on while editing.
- **Integrity.** Only UTF-8 text is editable. Line endings (LF or CRLF) and the presence of a final newline are preserved. Non-UTF-8 and binary files are read-only, and the view states why. Binary files show a single row instead of a diff.
- **Changes on disk.** Without unsaved edits, a file follows disk live. With unsaved edits, an outside write stops following and shows a banner above the file: `Changed on disk` with `Keep my version` (save over the disk version) and `Use disk version` (discard edits). There is no merge.
- **New files.** ⌘N opens an untitled single-file window.

## Opening

- `spale` opens the repository containing the current directory, or the current folder outside Git. `spale <path>` follows the same rule. The repository or worktree root is resolved and deduplicated by real path: an existing window comes forward, otherwise a new one opens. The command returns immediately.
- `spale <file>` inside a repository opens that repository's window on the file's full-file view. An unchanged file appears in `FILES`, and appears in `CHANGED FILES` only when it has changes. A file outside any repository opens in a single-file window.
- A path that does not exist prints a one-line error and exits non-zero. Nothing opens. A folder outside Git opens a folder window.
- Finder "Open With" and dropping onto the Dock icon work as usual. There is no Open command and no recent list. Folders outside Git open folder windows.
- The `spale` command needs no setup: the installer links it onto `PATH`, together with a `code` alias that behaves identically. There is no in-app "install command line tool" step.

## Launch

### First launch

The first time the empty-state window appears after installation, spale plays its one-time opening, then rests in the empty state. It is shown once per installation, recorded in user defaults; if the very first launch opens a repository directly, the opening plays the first time the empty state appears later.

Sequence, about 1.6 seconds, using `--ease`:

1. 0–900 ms: the spale mark draws itself on the empty window: a single thin stroke peeling off a straight edge and curling into a shaving, like a plane stroke on wood.
2. 600–1100 ms: the wordmark `spale` in Fira Code Light fades in beneath it and rises 4 pt into place.
3. 1100–1600 ms: the mark and wordmark shrink together as one centred group, from 28/22 scale to their final size. The hint fades in as one line over 180 ms linear.

Any click or key press finishes the sequence immediately at its final frame; that input does nothing else. With Reduce Motion, the whole opening is a 200 ms crossfade into the empty state. No sound, no splash window, no welcome text, no tour, no permission prompt.

### Every later launch

Standard macOS window restoration reopens the previous repository, folder, and file windows, following the system setting "Close windows when quitting an application". When nothing is restored, or when the Dock icon is clicked with no windows open, spale shows the empty-state window. Closing the last window does not quit the app.

### Empty state

A single quiet window, centred, about 640 × 420 pt, with no window bar and nothing to click:

- The spale mark uses a 72 pt canvas with a visible stroke about 40 pt wide. It uses the icon's warm gold in dark appearance and darker bronze in light appearance, including during the opening. The mark and wordmark form one centred group.
- At the bottom, one centred line reads `Run spale . in a terminal.` The command `spale .` uses Fira Code in the soft colour. The surrounding text uses the muted system font. A quiet line-colour chip surrounds the command, with 6 pt horizontal padding and a 5 pt corner radius. The chip and text fade in together.

The empty-state window is not listed in the window bar.

### App icon

The icon is the same shaving mark on a calm surface, made with the system icon format for current macOS so it adapts to light, dark, and tinted appearances.

## Visual system

Typography uses two families: Fira Code Light for code and the wordmark, and the system font with tabular numbers for interface text. Every text style is one of these:

| Style | Font |
|---|---|
| code, line numbers, `spale .` | Fira Code Light 12/18 |
| wordmark | Fira Code Light 22 (28 during the opening) |
| interface text, folds, counts, window bar | system 12/18 |
| title bar name | system 12 medium |
| sidebar file names | system 13 |
| file header path | system 13 medium |
| empty-stream message | system 15 |
| Markdown body | system 14, 4 pt line spacing, 10 pt paragraph spacing |
| Markdown headings | system semibold 24 / 20 / 16, 12 pt paragraph spacing |

Appearance follows the system light or dark setting; there is no in-app switch.

| Token | Light | Dark |
|---|---|---|
| page (window chrome) | `#e7e8eb` | `#242527` |
| bg (reader) | `#f5f5f7` | `#161719` |
| fg | `#24292f` | `#e6edf3` |
| strong | `#292d33` | `#e6e7e9` |
| muted | `#656970` | `#9c9ea3` |
| mark | `#9c713f` | `#e9c08a` |
| soft | `#555960` | `#c3c4c7` |
| line | `#0000000d` | `#ffffff10` |
| hover | `#00000009` | `#ffffff12` |
| selection | `#0000000d` | `#ffffff1a` |
| pressed | `#00000017` | `#ffffff26` |
| add | `#116329` | `#8dbfac` |
| remove | `#a40e26` | `#e7a39d` |
| modify | `#9a6700` | `#c7ad79` |
| add-bg | `#1163290c` | `#3fb9500e` |
| remove-bg | `#cf222e09` | `#ff7b720b` |
| add-word | `#11632920` | `#3fb95027` |
| remove-word | `#cf222e1c` | `#ff7b7225` |
| keyword | `#8250df` | `#d2a8ff` |
| string | `#116329` | `#8dbfac` |
| number | `#0969da` | `#79c0ff` |

Motion uses one curve, `--ease: cubic-bezier(.22, .8, .2, 1)`: 380 ms for layout changes (sidebar, fold expansion, view transitions), 180 ms linear for opacity, 3 s for the agent-write highlight. Reduce Motion removes animation and transitions; Reduce Transparency removes translucency. Everything else follows the prototype's `style.css`.

## Engineering constraints

- Read Git state without taking locks: never create `index.lock` or refresh the index (for the `git` CLI, use `--no-optional-locks`), so spale never blocks or races an agent's own Git commands.
- Watch the worktree, the index, and `HEAD` with FSEvents; coalesce bursts of writes; respect `.gitignore` for untracked files.
- Stay smooth while an agent rewrites large files: diff work happens off the main thread and the reading position is preserved across every update.
- No network access, telemetry, accounts, or configuration files.
