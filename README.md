# Higgsfield Usage Widget

A lightweight macOS menu bar app + desktop widget that shows your Higgsfield
credit balance in real time — balance sparkline, per-model spend breakdown
(credits + generation count over 7d/30d/all), and recent transactions.

Data comes from the official `higgsfield` CLI (`higgsfield account status`,
`higgsfield account transactions`) — no API keys, no cookies, read-only.

## Requirements

- macOS 14 (Sonoma) or newer, Apple Silicon
- Node.js — the CLI ships as an npm package

You do **not** need to install the `higgsfield` CLI yourself. If it is missing,
the popover shows an **Install higgsfield CLI** button that runs
`npm install -g @higgsfield/cli` for you and disappears once it worked. Only if
Node.js itself is absent does the card send you to nodejs.org first.

The app finds the CLI wherever npm put it — Homebrew, the official Node
installer, a custom `npm prefix`, nvm, fnm or Volta — so a working `higgsfield`
in your terminal is enough.

You do **not** need to be signed in on the command line either. The app keeps
its own session (see [Why it has its own login](#why-it-has-its-own-login)) —
click **Sign in to Higgsfield** in the popover on first launch.

## Install

```bash
git clone <repo-url>
cd higgsfield-usage-widget
./install.sh        # builds, installs to /Applications, offers a login item
```

The app is ad-hoc signed, not notarized. On first launch macOS will refuse to
open it: **right-click the app → Open → Open**. If it still refuses:

```bash
xattr -dr com.apple.quarantine "/Applications/Higgsfield Usage.app"
```

Then click the glyph in the menu bar and sign in.

## Build

```bash
./build.sh          # compile app + widget bundle
./package.sh        # optional: build a shareable DMG
```

## Why it has its own login

The CLI stores its credentials under `~/.config/higgsfield` and rotates a
refresh token there. If the app used that same file, it and your terminal would
invalidate each other's session — refreshing from one side makes the other
side's token stale, and the CLI then deletes the credentials outright.

So the app runs the CLI with `HOME` pointed at
`~/Library/Application Support/HiggsfieldUsage/cli-home`, giving it an
independent session. Your workspace selection is copied over on first run; the
credentials deliberately are not. Signing in on the command line and signing in
here are separate, and neither disturbs the other.

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

## Notes

Unofficial and not affiliated with Higgsfield. The glyph used for the menu bar
and app icon is their trademark, included here to identify the service the app
reports on. Read-only: the app never writes to your Higgsfield account.

MIT — see [LICENSE](LICENSE).
