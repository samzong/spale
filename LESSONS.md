# Lessons from development

reviewed-through: d1463fc2c9569c07d81b0d2f8d1eb9886fa7c553

Read this file before work. The marker covers history through that commit, inclusive.
Each entry contains a Rule, Why, Evidence with repository-qualified SHA(s), and `Seen N×` with separate evidence dates.
Dates count observed mistakes, not repeated reads. The nightly procedure is in `AGENTS.md`.
The seeded entries record owner-reported incidents and the source evidence listed below.

## Build releases with the CI SDK, on macos-26

- Rule: Use the `macos-26` runner for release builds. Inspect vtool SDK and minos output from the packaged binary.
- Why: A local SDK 27 build does not prove the CI SDK. The v0.1.0 tag run failed on macos-15 because `NSTextBlock.VerticalAlignment.top` was unavailable. The independent review of the release work found that macos-15 / SDK 15.5 links the pre-26 appearance on macOS 26.
- Evidence: `samzong/spale` `762726b8932364ac5eff903e7059eb70865db42d`, failed tag run [39103276388](https://github.com/samzong/spale/actions/runs/39103276388). PR #6, `20775e77e6d7fc44f15e5f2e74aff54c2898e336`, changed `.top` to `.topAlignment`. PR #7, `d1463fc2c9569c07d81b0d2f8d1eb9886fa7c553`, selected macos-26 and printed vtool output. That change fixed the appearance issue identified by the independent release review. The bootstrap checks did not repeat that review.
- Seen 1×: 2026-10-18.

## Publish the asset before the tap cask bump

- Rule: Confirm the release asset exists before merging a spale cask bump. Use the published asset SHA-256.
- Why: Tap PR #235 merged spale 0.1.0 with a local checksum before its release existed. Downloads returned 404. The scan compares versions, so it cannot repair the same version. Recovery required v0.1.1.
- Evidence: `samzong/homebrew-tap` `6527af377ae2acf94efeeec6295a8adf299f289f` (PR #235). Its PR body records the local checksum, 404, and same-version scan limit. The v0.1.1 release followed the failed `samzong/spale` tag target `762726b8932364ac5eff903e7059eb70865db42d`. The v0.1.1 cask bump is `samzong/homebrew-tap` `e82405e309725489652d6b54ffa33db3c78b4454`.
- Seen 1×: 2026-10-18.
