# Higgsfield Usage Widget — Design

**Date:** 2026-07-28
**Status:** Approved
**Project folder:** `~/Desktop/Code & Software/higgsfield-usage-widget/`

## Goal

A native macOS menu bar app that shows the current Higgsfield credit balance at
a glance, with a popover for details: credit history, per-model spend breakdown
(which models consumed the most credits and how many generations were made with
them), and recent transactions. Plus a WidgetKit desktop widget. Modeled on the
existing `claude-usage-widget` (same author, same architecture), but standalone
and cleanly separated.

## Approaches considered

1. **Native Swift app, forked from claude-usage-widget architecture** — chosen.
   Proven pattern, supports WidgetKit desktop widget, no runtime dependencies.
2. SwiftBar plugin — rejected: SwiftBar not installed, no desktop widget, no
   custom popover; does not meet the "full like Claude Usage" requirement.
3. Electron menu bar app — rejected: heavyweight, overkill.

## Data source

The `higgsfield` CLI (`/opt/homebrew/bin/higgsfield`, resolved via PATH with
Homebrew fallback), called from Swift via `Process` with `--json`:

- `higgsfield account status --json`
  → `{"email": "...", "credits": 2451.5, "subscription_plan_type": "creator"}`
- `higgsfield account transactions --size 100 --json`
  → array of `{"display_name": "Nano Banana Pro", "credits": -2,
  "action": "spend", "created_at": "2026-07-28T11:47:55.248813Z"}`

No Python helper, no cookie decryption. Auth is delegated entirely to the CLI
(`higgsfield auth login`).

## Architecture

Same layout as claude-usage-widget:

```
main.swift              SwiftUI menu bar app: MenuBarController, popover,
                        settings window, fetcher, aggregation logic
HiggsfieldWidget.swift  WidgetKit extension (small + medium)
WidgetShared.swift      App Group snapshot codec shared by app + widget
build.sh                Compile app bundle (arm64, ad-hoc signed)
package.sh              Build distributable DMG
install.sh              Install to /Applications
```

- Bundle id: `com.higgsfield.usage-widget` (widget:
  `com.higgsfield.usage-widget.HiggsfieldUsageWidget`)
- App name: **Higgsfield Usage**
- `LSUIElement` = true (menu bar only, no Dock icon)
- macOS 14+, arm64

## Data flow

1. Timer fires (default every 2 min, configurable 1–15 min).
2. Fetcher runs `account status --json` and `account transactions --size 100
   --json` (sequentially, off the main thread).
3. Transactions are merged into a local history file
   `~/.higgsfield-usage-widget/transactions.json`, deduplicated by
   `(created_at, display_name, credits)`. History therefore grows beyond the
   API page size and enables true long-term stats.
4. A balance snapshot `(timestamp, credits)` is appended to
   `~/.higgsfield-usage-widget/balance-history.json` (for the sparkline).
   Appended once per successful fetch; entries older than 90 days are pruned.
5. Aggregation (pure functions): per-model totals over a selected time window —
   sum of spent credits, count of spend transactions (= generations).
6. UI updates; a snapshot is written to the App Group container and
   `WidgetCenter.reloadAllTimelines()` is called.

## UI

**Menu bar:** bolt symbol + integer credit count (e.g. `⚡ 2451`). Turns the
warning color when credits fall below the configured threshold.

**Popover:**
- Header: credits (large), plan badge (`creator`), account email
- Balance sparkline from local balance history
- **Model breakdown**: time-window toggle **7 days / 30 days / All**; models
  sorted by credits spent, each row: model name, proportional bar,
  `487 cr · 243 gens`
- Recent transactions: last 5 (model, credits, relative time)
- Footer: last-refresh time, Refresh / Settings / Quit buttons

**Desktop widget (WidgetKit):**
- Small: credits + plan
- Medium: credits + top-3 models of the current window
- Reads the App Group snapshot; no networking of its own

**Settings window:**
- Refresh interval (1–15 min, default 2)
- Low-credit warning threshold (absolute credits, default 500)
- Launch at login (SMAppService)
- Language DE/EN (reuse the L10n enum pattern from claude-usage-widget)

Config file: `~/.higgsfield-usage-widget/config.json`.

## Error handling

- CLI missing or not logged in → menu bar shows `⚡ –`; popover shows a hint
  with the exact fix (`brew install …` / `higgsfield auth login`).
- Fetch/network error → keep last known data, show staleness ("Stand: 11:47");
  menu bar keeps the last value.
- Malformed JSON → treated like a fetch error; never crashes the app.
- Transactions fetch failing while status succeeds → balance still updates,
  breakdown marked stale.

## Testing

- Aggregation logic (dedupe, window filtering, per-model totals, sparkline
  downsampling) implemented as pure functions on Codable structs; covered by
  `swift test` (SwiftPM test target).
- UI verified by building and running the app manually (same approach as
  claude-usage-widget).

## Non-goals

- No Intel build (arm64 only, like the original)
- No notarization (ad-hoc signed)
- No write operations against Higgsfield (read-only)
- No tracking/telemetry; no data leaves the machine except CLI calls to the
  Higgsfield API
