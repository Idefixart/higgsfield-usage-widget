# Execution Progress — 2026-07-30

Plan: `2026-07-28-higgsfield-usage-widget.md` · Branch: `feat/v1` → merged to `main`

## Status: v1.0.0 complete

All 12 tasks done. `swift test` → 28/28 green. `./build.sh` → signed app + widget
bundle. Installed to `/Applications/Higgsfield Usage.app`, running.

Batch A quality-review findings all fixed in
`fix: chronological merge sort, deterministic tie-break, testable snapshot IO`:
- merge sorts by parsed date (raw ISO strings mis-sort across fraction widths)
- `modelBreakdown` ties break on name (dictionary order is per-process random)
- `SharedStore.write/read(to:from:)` URL variants + 6 disk-path tests
- Silent `try?` on persistence kept deliberately (mirrors sibling project; a
  failed load degrades to empty history, which the UI already surfaces as stale)

## Deviation from plan

Tasks 9+10 landed in one commit (`feat: menu bar entry point, build script and
WidgetKit extension`) instead of two — writing the app-only `build.sh` first and
immediately replacing it was pure churn.

## Field fix not in the plan

The CLI is a `#!/usr/bin/env node` script, so `node` must resolve on PATH. GUI
apps inherit launchd's PATH, which usually lacks the Homebrew prefix.
`HiggsfieldCLI.run` now prepends `/opt/homebrew/bin:/usr/local/bin`.

## Verified

- App launches, polls the CLI, writes
  `~/Library/Group Containers/group.com.higgsfield.usage-widget/credits-snapshot.json`
  with a fresh `updatedAt` each refresh
- Widget `.appex` carries `app-sandbox` + the app group in its signature
- Error path confirmed live: CLI logged out → popover/snapshot carry
  "Not authenticated. Hint: Run: hf auth login", menu bar falls back to `⚡ –`

## Blocked on user

`higgsfield auth login` — `~/.config/higgsfield/credentials.json` is missing, so
no live credit numbers could be verified. Everything downstream of a successful
`account status` (balance card, sparkline, model breakdown, transactions,
widget content) is unverified against real data until then.

Desktop widget gallery entry also needs a manual check:
right-click desktop → Edit Widgets → "Higgsfield".
