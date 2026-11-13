# Status

Updated: 2026-11-12. Commit this file in the same commit as the work it describes.

## 1.4, on `claude/1.4`

- Deleting rows or columns at the edge of a range shrinks the range (`=SUM(A2:A10)` with row 2 deleted is `=SUM(A2:A9)`). It used to become `#REF!` whenever a deleted row was the range's first or last one. A range is `#REF!` only when all of its rows (or columns) are deleted. This covers ranges on other sheets, whole-column and whole-row ranges, and named ranges (`FormulaRewriter.shiftRange`, `StructureShiftRangeTests`).
- Saved spills now open in Excel without a repair prompt (checked in Excel 16.115 on Nov 12). Two things made Excel call the file damaged and drop formulas: a blocked spill's `#SPILL!` saved as an error value (only the ECMA-376 error codes may be; `#SPILL!` and `#CALC!` are now saved as text), and a `G1#` reference saved as typed (now `_xlfn.ANCHORARRAY(G1)`). A formula that can spill but fills one cell, or is blocked, is now saved as a one-cell dynamic array as Excel saves it, and `xl/metadata.xml` is written whenever any formula is (`SpillFileTests`). In licensed Excel all 38 spilled values matched Spark Grid's. Excel saved the same file back (`Fixtures/excel-dynamic-arrays.xlsx`, saved path and author name replaced) in the same form, except that Excel stores a blocked spill as `#VALUE!` plus a rich-value part saying `#SPILL!`; Spark Grid opens it with every spill as a spill and, recalculated, gets Excel's values and the blocked spill (`ExcelSavedSpillTests`).
- Spill references: `C1#` is every cell C1's results spill into, and `_xlfn.ANCHORARRAY(C1)` from a saved file reads the same. It is a range taken from the spill's current size, so COUNTIF, INDEX and the rest read it; `#REF!` when nothing spills from C1 or its spill is blocked; `=C1#*2` spills itself; it is shown and saved back as `C1#`. Formulas reading it are recalculated by the background update, not on the edit itself: recalculated on the edit, they read C1's old results and the background update kept them. Two engine fixes came with it: a background update that replaces one not yet applied now carries that one's cells (laying out a spill makes two updates in a row, and the first one's formulas kept old results; two quick edits did the same), and a spilling formula about to recalculate drops the range snapshots over its cell. Also `#N/A` and `#DIV/0!` typed in a formula now parse (`/` ended the error name). The Excel fixture's `ROWS(G1#)` gives Excel's 3 (`SpillReferenceTests`, `ExcelSavedSpillTests`, BugBash "spill references follow the spill").

- Checked the other 1.4 file features in Excel 16.115 (Nov 13): a file made with Spark Grid's own commands (two pivot tables, a pivot chart, GETPIVOTDATA, print area, page breaks, row and column groups, links, a protected sheet) opens with no repair prompt; Excel keeps the print area, breaks, groups, links and the protection (password `spark` and its allowances), and the pivot values match. One bug fixed: grouped columns opened zero wide (hidden) in Excel, because a `<col>` without a width reads as width 0; every `<col>` now carries a width, and the default one is not kept as a set width on open. Excel's save is `Fixtures/excel-1.4-features.xlsx` (`ExcelSavedFeaturesTests`). Not fixed: Spark Grid's pivot tables are saved as values plus Spark Grid's own settings, so Excel has no pivot to read: `GETPIVOTDATA` over one shows `#REF!` in Excel, and a save from Excel drops the settings, so the pivot comes back as plain cells.

- Size limit on opening files (Sam agreed Nov 13): 2 GB unpacked in all, and no part over 200 MB. Bytes are counted as they unpack, not taken from the sizes the file declares, so a small file that unpacks to far more stops early with "This workbook is too large to open…" instead of filling memory (`ZipPackage.Limits`, `ZipLimitTests`). The other two places that unpack parts use the same per-part cap.

- Sam's 1.3 reports (Nov 13): (1) typing over a value showed the new letter over the old word (the typed letter drawn over a predicted word) while typing. The cell editor had macOS inline word predictions on, drawn a few points off the typed letters; predictions and automatic completion are now off in the cell editor and formula bar (`EditorSpellCheck`). (2) Coloring filtered rows also colored the rows the filter hid; formatting now skips filter-hidden rows, as Delete already did (`applyFormat`). Both in BugBash ("typing over a value hides the old text", "fill skips filtered rows"; each fails without its fix). Open: a fill that shows two shades split partway through a row, not yet reproduced (needs Sam's steps).

- Print setup has a "Row and column headings" switch (Sam, Nov 13), on by default as before. Off, the printout leaves out the column letters and row numbers and pages reserve no room for them, so more rows fit. Like Gridlines it is chosen at print time, not saved in the file (BugBash "print without headings").

## 1.3 (version 1.3, build 7), not yet submitted

1.2 (build 6) is in App Review. 1.3 is on `claude/1.3` (Spark-Grid#79, SparkGrid#3). Release notes are in `docs/release-notes-1.3.md`; `docs/BUGS.md` lists the fixes.

- Charts from files (`ForeignChart`) are read by `ImportedChartReader` and drawn by `ImportedChartView`, live from their cells. Move, resize, duplicate, reorder and delete edit the kept anchor (`DrawingAnchorXML`); Edit Chart rewrites the kept chart part with `ImportedChartWriter` (XMLDocument), changing only what was edited.
- Saving numbers every object in a drawing, and the drawing part is valid XML again (`</xdr:xfrm>`; since Oct 15 it closed with `</a:xfrm>`).
- Highlight styles write both `fgColor` and `bgColor` for a solid fill.
- Duplicates (`SpreadsheetViewModel+Duplicates`), tables (`SpreadsheetViewModel+Tables`, `SheetTable+Style`), tab colors (`SheetFileExtras+TabColor`), icon thresholds, selection stats and AutoSum, and tabbed Settings.
- Row insert: formulas on other sheets that don't name the changed sheet are skipped by a byte scan, and the rest are shifted in parallel.
- Checked: an edited stress workbook opens in Excel with no repair prompt and imports into Numbers; a table from the app's template opens in Excel as a styled table.
- Still to check by hand: Remove Duplicates, Undo, save; a changed shortcut after a relaunch. Still to make: App Store screenshots and a preview video.



1.1.1 shipped on 2026-10-29. 1.2 follows `Future Features.md`: compatibility first. The bug bash (PR #77) is merged; `docs/BUGS.md` lists what is open. Release notes are in `docs/release-notes-1.2.md`.

- A save keeps what the file had: hidden rows, columns and sheets, grouped rows and columns, tab color, sheet protection, page setup and headers, dropdown rules, comments, links, tables, charts the app does not draw, and pivot tables. These live in `Sheet.fileExtras` and `Workbook.pivotCaches` and move with inserted, deleted and sorted rows. The Oct 29 audit workbook keeps every item, and a saved copy opens in Excel with no repair prompt.
- Hidden rows and columns are hidden in the grid. Hide and Unhide are on the header menus and the Sheet menu; hidden sheets leave the tab bar and come back from the tab menu.
- Dropdown lists show a button and a menu (Option-Down opens it). Comments show a corner mark and a tooltip. Links have Open Link.
- The fill handle continues numbers, dates, numbered text, and month and day names; Option-drag copies.
- Tables: a column inserted inside a table joins its column list (named Column1, Column2, and so on, written into the header row) and a deleted one leaves it; filter columns follow. Kept charts declare each namespace once; a file saved by the first 1.2 build with namespaces declared twice is cleaned on the next save. Excel opened the stress workbook with both table edits and no repair prompt. A formula whose reference becomes #REF! after a delete drops its saved result, so the file asks to be calculated on open. Highlight rules of the kind "cell value equals some text" were read as `=A1="""text"""`, which pointed at the wrong cell and never matched, in the grid or after a save; they now read as `=N2="text"` for the rule's first cell.
- Large format changes (alternating row colors, fill, bold, borders on thousands of cells) are one pass over one sheet copy with one undo step. Alternating colors on the stress workbook's Orders sheet (15,000 rows) used to copy the sheet once per row and register an undo per cell; it now applies in about a second in a Debug build, and Undo and Redo are one step each.
- Every visible cell with a dropdown list shows a faint chevron; the selected one shows the full button.
- Release timings, 1.1.1 (`6465903`) vs 1.2 (`4478523`), this Mac, best of three: KPI open 0.39 vs 0.39 s, slowest first screen 0.036 vs 0.035 s, edit to pixels 0.003 vs 0.003 s, export 0.18 vs 0.185 s, worst scroll 0.026 vs 0.019 s. 50,000-row ledger: open 2.75 vs 2.70 s, export 0.45 vs 0.43 s, memory 1682 vs 1754 MB. The benchmark's own answer check flags every formula on both builds alike; `spark-grid-cli check` is the answer check that counts (0 mismatches).
- Functions batch 1: 37 functions and the `#NUM!` error (`FormulaEvaluator+Batch1.swift`, `evalExtremeIFS` for MAXIFS and MINIFS).
- `data.sort` takes `then` levels. Sort, Format Cells, Conditional Formatting, Insert Chart and Print use the shared `SparkDialog` layout.
- Import of the KPI file: debug `testFullWorkbookImportWallClock` 2.80 s on this branch, 2.77 s on `main` (row attributes are read in one pass).

## Phase

Phase D and Phase E are done. A file saved after an edit stores a result on every formula. Reopening that file shows those results and does not recalculate. On the KPI file, Release export is 0.159 s and the saved file is 1,199,509 bytes. Full recalculation orders sheets from the dependency graph. The name-based sheet rank and the legacy strip planners are gone. The rules grep over `Packages/SparkGridCore/Sources`, `Spark Grid/State`, and `Spark Grid/Grid` prints nothing. Paint, shuffled, edits, and full recalculation are at 0 mismatches except `YTD Summary!R5`. Ledger ground truth: 1,646 formulas, 0 mismatches.

## Next task

Stop. Do not start another phase from this status alone.

## Open to the first grid (2026-10-22)

Release, this Mac, the KPI reference file. The clock stops when the opened sheet has been painted. The other sheets finish after that. Before is `bdac6a2`. After is this change. The first scroll is one viewport on the opened sheet. 48,191 formulas, all cached.

| Path | Before | After |
|---|---|---|
| Open to the first painted grid | 0.576 s | 0.256 s |
| First scroll of the opened sheet | 0.017 s | 0.017 s |
| First switch to the heavy sheet | 0.025 s | 0.028 s |
| First scroll of that sheet | 0.023 s | 0.024 s |

The opened sheet is drawn from the values stored in the file. Shared formulas on the other sheets are expanded after that paint. The tiles that cover the first screen are rasterized before the scroll. Rows that were not on that screen are not. A scroll onto those rows still paints cells, and that scroll did not get slower.

The workbook is imported in full before the first paint. Stored formula results are what the grid draws, so open does not recalculate. Tiles for the screen already in view are rastered from that sheet's own column and row offsets.

A file saved without formula results used to calculate those formulas inside the first grid draw, on the main thread, so a click was not accepted until the draw returned. Debug File → Open of that file, from the start of load until the first grid draw returned: 2.2 s (import 2.0 s, draw 0.03 s). The uncached formulas are calculated after that draw, off the main thread. Column letters are drawn from the sheet's widths. The column-header tile placeholder, one 512 pt tile at the default column width, is not shown over them.

## Last gate result

2026-10-16, after W8. `scripts/ci.sh` printed `PASS (215.3s)`. Lint, format, package, xcodebuild, layers, privacy-assets, ledger, and fuzz passed. KPI skipped because `SPARK_GRID_CORPUS` was unset. That skip is not a local pass anymore. `scripts/ci.sh` sets `SPARK_GRID_CORPUS` when the manifest file is in `~/Downloads` or `~/SparkGridCorpus`, and a skipped KPI stage fails the local gate. Hosted CI still skips KPI. Ledger ground truth the same day: 1646 formulas, 0 mismatches. Fuzz smoke: seed 1, 20 steps, pass.

The real KPI baseline is the display path, not full recalculation. On 2026-10-16, against the original saved results with caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 9,915 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 32,833 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 9,915 | 1 |
| Full recalculation | 367 | 1 |

Paint order differs in 9,916 formulas. That count is the 9,915 mismatches plus the one exempt cell, `YTD Summary!R5`. Record 9,916 as the baseline. The check still fails until every path is 0 mismatches except that cell. Do not weaken it. An earlier unseeded random walk differed in 32,571; the gate uses seed 1. Full recalculation differed in 368, which is 367 plus the exempt cell. The scalar check on `2958120` was 11,894 mismatches and is not ground truth.

Range reads now calculate formula cells in the range before the range is assembled. Same day, Release, same machine, caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 896 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 2,118 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 896 | 1 |
| Full recalculation | 367 | 1 |

Full recalculation was unchanged at 367 plus the exempt cell. Paint order and the edit path dropped from 9,915. The shuffled path dropped from 32,833.

`TEXT` now uses `ExcelFormatCode` for date, time, and number codes. Same day, Release, caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 531 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 1,753 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 531 | 1 |
| Full recalculation | 2 | 1 |

The 365 `TEXT` formulas that were wrong on every path now match. The check still fails until every path is 0 mismatches except `YTD Summary!R5`.

Unqualified ranges are cached on the sheet that owns the formula. A summary that adds two sheets' `COUNTIF` results no longer reuses the first sheet's column. Same day, Release package test, caches cleared, 48,191 formulas. Release timings were not re-run for this commit.

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 2 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 1,224 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 2 | 1 |
| Full recalculation | 2 | 1 |

Paint, edits, and full recalculation miss `YTD Summary!R62` and `YTD Summary!R63`. The shuffled path still misses 1,224.

A cached aggregate range is now dropped when a cell inside it is calculated later. `testDayWindowCountsMatchWhenTheRowTotalIsVisitedFirst` passed. The four paths above were not re-run. Release timings were not re-run.

`AVERAGE` and `AVERAGEIFS` return an error that sits in the averaged cells. `IFERROR` then shows its fallback. Same day, Release package test, caches cleared, 48,191 formulas. Release timings were not re-run.

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 0 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 1,222 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 0 | 1 |
| Full recalculation | 0 | 1 |

Paint, edits, and full recalculation match except `YTD Summary!R5`. The shuffled path dropped from 1,224 to 1,222.

`eval()` restores the outer origin, and `calculateWithPrecedents` calculates a same-sheet precedent. Same day, Release package test, caches cleared, 48,191 formulas. Ledger ground truth the same day: 1,646 formulas, 0 mismatches.

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 0 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 0 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 0 | 1 |
| Full recalculation | 0 | 1 |

Phase C does not change calculation. The same Release check, run again at the end of Phase C on 2026-10-20, is still 0 mismatches on all four paths except the one exempt cell. Ledger ground truth was not re-run: Phase B measured 1,646 formulas and 0 mismatches, and this phase does not touch Calc or Engine.

Phase E removes the name rank and the legacy strip planners. Same day, Release `spark-grid-cli check`, caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 0 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 0 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 0 | 1 |
| Full recalculation | 0 | 1 |

Open, edit, scroll, and save were not re-timed. Those paths do not call the removed planners.

## Latest Release numbers

Date: 2026-10-21. Binary: Release build on `cursor/phase-d-save-c95e`. Machine: this Mac. Edit to pixels starts at `commitEdit` and stops when that display pass returns. The painted count is cells drawn in that pass. The benchmark loads a copy of the workbook.

Phase D does not change the grid. The 120 Hz fling below is the Phase C measurement and was not re-run. Scroll frames are a scripted trackpad fling at 120 Hz in a 1280×800 window, 252 frames. Fill is the slowest tile from the moment it enters the clip until its bitmap is installed.

| Sheet | p50 | p95 | max | dropped | over 16 ms | fill |
|---|---|---|---|---|---|---|
| June | 1.289 ms | 2.099 ms | 2.601 ms | 0 | 0 | 0.003 ms |
| YTD Summary | 1.662 ms | 2.583 ms | 3.583 ms | 0 | 0 | 0.002 ms |
| Ledger | 0.867 ms | 1.461 ms | 2.470 ms | 0 | 0 | 0.003 ms |

Before the tile change, the same fling was June p95 43.894 ms (1,100 dropped, 252 frames over 16 ms), YTD Summary p95 29.012 ms (537 dropped, 252 over 16 ms), Ledger p95 48.380 ms (107 dropped, 21 over 16 ms).

On 2026-10-21, before Phase D, the same machine measured export at 2.243 s (KPI) and 0.836 s (ledger). A save after an edit wrote no formula caches, so reopening calculated. The KPI edit-save was 13,968,826 bytes. The ledger edit-save was 18,120,889 bytes.

KPI reference file, after Phase D:

| Path | Release |
|---|---|
| Import | 0.367 s |
| Fingerprint | 3.762 s |
| Export | 0.159 s |
| Autosave on the main thread | 0.000 s |
| Autosave in the background | 0.187 s |
| Open | 0.585 s |
| Unsaved-changes check | 0.000 s |
| Slowest first screen | 0.032 s (YTD Summary) |
| Tab switch | 0.000 s |
| One edit commit | 0.003 s (January) |
| Edit to pixels | 0.003 s, 1 cell painted |
| Save on the main thread | 0.000 s |
| Save in the background | 0.572 s |
| Saved file after an edit | 1,199,509 bytes, 48,191 of 48,191 formulas cached |
| Reopen display, no recalculation | 0.074 s, 1 mismatch (the exempt cell) |
| Worst scroll screen | 0.025 s (Config, 17 ticks) |
| Dependency-graph builds on that edit and the following save | 0 |
| Resident memory | ~305 MB |

Synthetic ledger, after Phase D:

| Path | Release |
|---|---|
| Import | 0.518 s |
| Fingerprint | 0.419 s |
| Export | 0.437 s |
| Autosave on the main thread | 0.000 s |
| Autosave in the background | 73.055 s (the file has no caches, so the save calculates them) |
| Open | 3.497 s |
| Slowest first screen | 1.102 s (IndexMatch) |
| Tab switch | 0.000 s |
| One edit commit | 0.001 s (VLOOKUP) |
| Edit to pixels | 0.001 s, 1 cell painted |
| Save on the main thread | 0.000 s |
| Save in the background | 72.490 s |
| Saved file after an edit | 1,863,568 bytes, 1,646 of 1,646 formulas cached |
| Reopen display, no recalculation | 0.040 s |
| Worst scroll screen | 0.611 s (Ledger, 7 ticks) |
| Dependency-graph builds on that edit and the following save | 0 |
| Resident memory | ~2462 MB |

The original KPI file is 1,119,816 bytes. A Spark Grid save of it is 1,199,509 bytes.

Previous Release run, 2026-10-20, on `cursor/phase-b-edit-pixels-c95e`: KPI import 0.334 s, fingerprint 3.897 s, export 2.249 s, open 0.552 s, slowest first screen 0.062 s (July), June scroll worst 0.017 s (13 ticks), tab 0.000 s, edit to pixels 0.005 s (1 cell) and 0.002 s on YTD Summary (1 cell). Ledger import 0.535 s, fingerprint 0.444 s, export 0.886 s, open 3.596 s, slowest first screen 1.116 s (IndexMatch), scroll worst 0.598 s (7 ticks), edit to pixels 0.150 s (1 cell).

Previous Release run, 2026-10-16, on `cursor/workflow-gates`: KPI import 0.369 s, fingerprint 3.808 s, export 2.226 s, open 0.669 s, slowest first screen 0.056 s (May), June scroll worst 0.127 s (13 ticks), tab 0.000 s, edit to pixels 0.046 s (1452 cells). Ledger import 0.532 s, fingerprint 0.423 s, export 0.832 s, open 3.783 s, slowest first screen 1.124 s (IndexMatch), scroll worst 0.684 s (7 ticks), edit to pixels 3.510 s (92 cells). Older baseline (2026-10-11) is in `.cursor/rules/performance.mdc`. Use the table above when a commit needs before/after numbers, and replace it when a new Release run finishes.
