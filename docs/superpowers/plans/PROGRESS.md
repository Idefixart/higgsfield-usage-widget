# Execution Progress — 2026-07-28

Plan: `2026-07-28-higgsfield-usage-widget.md` · Branch: `feat/v1` · Mode: subagent-driven (batches)

## Done
- **Batch A (Tasks 1–5, core lib):** implemented, committed (8701fb1..ed1c446), `swift test` 19/19 green.
  - Spec review: ✅ byte-identical to plan.
  - Quality review: **open findings, not yet fixed:**
    1. [Important] `HistoryMerge.merge` sorts by raw `createdAt` string — breaks chronological order when fraction widths differ (e.g. `...00Z` vs `...00.123456Z`). Fix: sort by parsed `tx.date` with string fallback; add test with mixed fraction widths.
    2. [Important] `SharedStore.write/read` disk path untested — add roundtrip test against a temp-dir (or accept as app-level risk).
    3. [Important] Silent `try?` on all persistence paths — at minimum consider `os_log` on failure (may accept as-is, mirrors sibling project).
    4. [Minor] `modelBreakdown` tie-break nondeterministic — add secondary sort by name.
- `.gitignore` note: add `.build/` (SwiftPM cache currently untracked but unignored).

## Next (on resume)
1. Fix Batch A quality findings (1 + 4 mandatory; 2 recommended; 3 judgment call) → re-run quality review or verify inline.
2. Batch B: Tasks 6–8 (AppSupport.swift, Store.swift, Views.swift + typechecks).
3. Batch C: Tasks 9–10 (main.swift, entitlements, build.sh, widget).
4. Batch D: Tasks 11–12 (install/package/README, e2e verification).
5. Final review, merge `feat/v1` → `main`.
