# Higgsfield Usage Widget

A lightweight macOS menu bar app + desktop widget that shows your Higgsfield
credit balance in real time — balance sparkline, per-model spend breakdown
(credits + generation count over 7d/30d/all), and recent transactions.

Data comes from the official `higgsfield` CLI (`higgsfield account status`,
`higgsfield account transactions`) — no API keys, no cookies, read-only.

## Requirements

- macOS 14 (Sonoma) or newer, Apple Silicon
- [higgsfield CLI](https://higgsfield.ai) installed and signed in:
  `brew install higgsfield && higgsfield auth login`

## Build & install

```bash
./build.sh          # compile app + widget bundle
./install.sh        # install to /Applications, optional login item
./package.sh        # optional: build a shareable DMG
```

## Tests

Core logic (parsing, history dedupe, aggregation, snapshot IO) is a SwiftPM
library:

```bash
swift test
```

## Configuration

Click the bolt in the menu bar → Settings:
refresh interval (1–15 min), low-credit warning threshold, launch at login,
language (EN/DE). Config: `~/.higgsfield-usage-widget/config.json`.
Local history: `transactions.json`, `balance-history.json` (same folder).
History accumulates across refreshes, so per-model stats reach further back
than the API's transaction page.

## Project layout

```
main.swift / AppSupport.swift / Store.swift / Views.swift   menu bar app
HiggsfieldWidget.swift                                      WidgetKit extension
Sources/HiggsfieldUsageCore/                                testable core logic
build.sh / install.sh / package.sh                          build & distribution
```

MIT.
