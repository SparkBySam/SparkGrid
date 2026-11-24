# Roadmap

## Stage

1.5 (build 10) is submitted for App Review (Nov 18, 2026). 1.4 is live on the Mac App Store (Nov 18). Build 9 of 1.5 was uploaded the same day but has a comparison bug and was not submitted; the next upload is build 11. What comes next is in `Future Features.md` under "Next, agreed Nov 18" and "Ideas for 1.6 and later".

## Headline numbers

Nov 18, 2026, main `c0e7d0d` (1.5 build 10):

- Stress workbook (`Fixtures/Sales-Ops-Stress-2026-1.5.xlsx`, 16 sheets, 114,796 formulas, results calculated by its generator): the Release answer check matches on all four paths (paint, shuffled, edits, full) except RANDARRAY's random cell, New in 1.5!H35.
- Against Excel 16.115, typed into both by script: 480 TEXT and format cells, 146 batch-3 cells, 91 shape-function cells and about 800 edge-case formulas; what still differs is listed in `docs/gaps.md`.
- BugBash 119/119. The full gate (`scripts/ci.sh`) passes.
- Looking for spilling formulas after an edit: 0.063 s for every sheet of the stress workbook in Release (2.3 s for its Orders sheet alone before Nov 18).
- Release timings of open, scroll and edit-to-pixels were last run for 1.2 and are not re-run since.

## Progress log

- 2026-11-18 — 1.5 build 10 submitted for review. Build 9 uploaded earlier that day; the release check then found text "1" no longer equal to a cell's "1" after the new comparison order (#122), so build 10 carries the fix. 1.4 live on the Mac App Store; website deployed for 1.4. Same day: script bug bash against Excel (#110–#122), INDIRECT, ADDRESS, OFFSET, LOOKUP, YEARFRAC, array maths, ranges that spill, the half-width window fix, and the spill-search speedup.
- 2026-11-17 — 1.5 scope agreed and most of it merged: start screen and templates, Quick Look, Numbers import, multiple windows, empty arguments, extras warning (#92–#99). 1.4 build 8 uploaded and submitted.
- 2026-11-13 — 1.4: checked in Excel 16.115 (no repair prompt, pivots as real pivot tables, groups, protection, links); Sam's manual pass fixes (undo cannot unprotect, faster row deletes, quicker arrow keys in a half-width window); protected ranges.
- 2026-11-11 — 1.4: pivot tables (make, date grouping, PivotChart, GETPIVOTDATA, refresh file pivots), links, spilling FILTER/SORT/SORTBY/UNIQUE, whole-workbook recalculation follows dependencies (stress workbook 0 wrong), BugBash 96/96.
- 2026-11-07 — 1.4 list agreed: toolbar flow, Paste Special, Format Painter, Fill Down/Right, Clear, functions batch 2, Text to Columns, grouping, sheet protection.
- 2026-11-06 — 1.3 released: charts on the sheet, Find Duplicates, tables, tab colors, AutoSum, Settings window.
- 2026-11-04 — 1.2 released: nothing lost on save, dropdowns and comments, hide and unhide, fill series, multi-column sort, rule filters, 37 more functions. Website deployed for 1.2.
- 2026-10-29 — 1.1.1 released: filter panel, tab reordering, Command-arrow, overlay scroll bars and fixes.
- 2026-10-20 — Phase C: the Release answer check is 0 mismatches on all four paths except one exempt cell.
- 2026-10-16 — `AVERAGE` and `AVERAGEIFS` return an error in the averaged cells. KPI answer check: paint 0, shuffled 1222, edits 0, full 0, plus 1 exempt. Release timings were not re-run.
- 2026-10-16 — Unqualified ranges stay on the sheet that owns the formula. KPI answer check: paint 2, shuffled 1224, edits 2, full 2, plus 1 exempt. Release timings were not re-run.
- 2026-10-16 — `TEXT` date and time codes use `ExcelFormatCode`. KPI answer check: paint 531, shuffled 1753, edits 531, full 2, plus 1 exempt. Release timings are in `docs/STATUS.md`.
- 2026-10-16 — Range reads calculate formula cells before the range is assembled. KPI answer check: paint 896, shuffled 2118, edits 896, full 367, plus 1 exempt. Release timings are in `docs/STATUS.md`.
- 2026-10-16 — Release timings after the W7 edit path, including edit to pixels. KPI edit to pixels 0.046 s (1452 cells). Ledger edit to pixels 3.281 s (92 cells). Numbers are in `docs/STATUS.md`.
- 2026-10-16 — W8: `ATTRIBUTION.md`, KPI-derived answer file removed, synthetic samples live under `Fixtures/`, `hero.png` is under 1 MB. `scripts/ci.sh` printed `PASS (215.3s)` with the private KPI check skipped. With the corpus set, KPI is still 48191 formulas, 367 mismatches, 1 exempt.
- 2026-10-15 — 1.1 released: large workbooks open fast, saving never freezes the window, formula cells show results.
- 2026-10-15 — W7: view-model cell edits, paste, fill, structure changes, sort, and sheet add, rename, and delete go through `WorkbookSession.apply`. Document undo stays on `UndoManager`. Full gate still blocked by privacy and assets.
- 2026-10-15 — W6: `spark-grid-cli` eval, cat, recalc, check, bench, and run. Smoke: `eval '=ABS(-2)'` prints `2`. Full gate still blocked by privacy and assets.
- 2026-10-15 — W5: corpus manifest (hash only), ledger Python ground truth (1646 formulas, 0 mismatches), KPI saved-result check (48191 formulas, 367 mismatches, 1 exempt), fuzz smoke (seed 1, 20 steps, pass), unit tests for every present function. Full gate still blocked by privacy and assets.
- 2026-10-15 — W4: crash-rule violations removed, hostile-input caps added, recovery copy written after edits. SwiftLint and swift-format pass. Full gate still blocked by later stages.
- 2026-10-15 — W3: `scripts/ci.sh` is the commit gate. First run `FAIL (0.6s)` at SwiftLint 0.65.1 strict (13 violations). No full PASS.
- 2026-10-15 — W2: engine moved into `Packages/SparkGridCore` with nine layers. Layer check passed. Gate script still not built.
- 2026-10-15 — W1: agent rulebook, status, gaps, and function parity. Gate not built yet.
- 2026-10-15 — `2958120`: sheet switch returns before cross-sheet calc; save returns before the export write finishes. Viewport scroll and Find focus stay.
- 2026-10-11 — Performance rules and the older KPI baseline recorded on `main`.
- 2026-10-06 — 1.0 released on the Mac App Store.
