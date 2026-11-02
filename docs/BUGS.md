# Bugs

One list of known bugs. Add a bug when it's found, with steps if there are any. Move it to Fixed with the PR that fixed it. Feature requests go in `docs/gaps.md`, not here.

Workbooks named here are fixtures in `Fixtures/`. Never name a customer file.

## Open

| # | Bug | Where | Notes |
| --- | --- | --- | --- |
| 6 | Charts from other apps are kept on save but not drawn | Any file with an imported chart | The chart parts round-trip; Spark Grid doesn't render them. |
| 7 | No toolbar control for tables | | Tables can be reached through the name box. There is no create or edit UI. |
| 11 | No visible controls for comments | | Comments work from the context menu only. |
| | `FormulaEngine.recalculateEntireWorkbook` mixes up unqualified ranges across sheets | Benchmarks, BugBashRunner | Its range cache keys unqualified ranges with no sheet, so Daily Q1's `SUM(F5:F64)` got Monthly Summary's answer. Adding the sheet name exposed a bulk loader that reads uncalculated same-sheet formulas as 0. The app no longer uses it on open. |
| | Icon sets always save as 0/33/67 percent thresholds | Any file with an icon set | The file's own thresholds are dropped on save, the way data bar thresholds were. |

## Not Spark Grid bugs

| # | Report | What it is |
| --- | --- | --- |
| 8 | Google Sheets warns "Some Excel elements may be dropped" | Sheets can't show data bars. The original fixture has the same data bar and gets the same warning. |
| 9 | `=CONCAT(Reps!$C$2," / ",Reps!$B$2)` shows #N/A in Google Sheets | Spark Grid saves `_xlfn.CONCAT` with three arguments and the right result. Sheets' CONCAT takes only two. |

## Won't fix for now

| Bug | Why |
| --- | --- |
| Blue input text is hard to read in light and dark mode | Kept as is, Oct 31. |

## Fixed

| # | Bug | Fixed in |
| --- | --- | --- |
| 1 | Data bars paint a sliver in rows a filter hides | Spark-Grid#77 / SparkGrid#1 |
| 3a | Row headers with a filter color only the first row after each hidden gap | Spark-Grid#77 / SparkGrid#1 |
| 4 | Formula bar shows `0.45` and date serials instead of `45%` and `3/14/2026`; typed dates are stored as text | Spark-Grid#77 / SparkGrid#1 |
| 5 | Selecting a merged cell washes only its left column | Spark-Grid#77 / SparkGrid#1 |
| | Dropdown button covers the fill handle | Spark-Grid#77 / SparkGrid#1 |
| | Undo after switching sheets jumps to the top of the sheet | Spark-Grid#77 / SparkGrid#1 |
| | Cells go blank after a nearby edit (overflow text skipped in limited repaints) | Spark-Grid#77 / SparkGrid#1 |
| | Cmd+A in the formula bar or name box selects the grid | Spark-Grid#77 / SparkGrid#1 |
| | Name box needs two clicks to focus | Spark-Grid#77 / SparkGrid#1 |
| | Hide/unhide undo applies to the wrong sheet | Spark-Grid#77 / SparkGrid#1 |
| | The last visible sheet can be deleted | Spark-Grid#77 / SparkGrid#1 |
| | List dropdowns with `&` in the source show escaped text | Spark-Grid#77 / SparkGrid#1 |
| | Date filter rules compare as text | Spark-Grid#77 / SparkGrid#1 |
| | `-0` shown; ROUND returns negative zero | Spark-Grid#77 / SparkGrid#1 |
| | Go To accepts addresses past the sheet limits | Spark-Grid#77 / SparkGrid#1 |
| 10 | Monthly Summary row 78 saved as `-0` (ROUND returned negative zero) | Spark-Grid#77 / SparkGrid#1 |
| | Reopening a file saved after a sort looks empty: recalculating its 114,599 formulas took 6 minutes in Release (now 8 s) | Next PR |
| | Unqualified VLOOKUP tables on two sheets at the same address could share one cached lookup | Next PR |
| | Data bars lose their saved scale (0 to 1.5 came back min to max) | Next PR |
| 2 | Sorting looks like it only sorts the typed columns: formula columns kept showing the old row's results at each address after a sort, and scroll tiles drew the unsorted rows | Next PR |
| | Highlights vanished after a reopen: a rule reading a formula cell got a blank when the cell's value came from the background calculation | Next PR |
| | Typing in a cell, switching sheets, then clicking a cell saved the typing twice: once on its own sheet and again into the cell selected on the new sheet, and undo then crossed sheets | Next PR |
| | File → Open accepted any text file and opened it as a one-column CSV | Next PR |
| | Highlight rules lost after reopening a file without saved results: they were worked out from the blanks shown while it calculated | Next PR |
| | Opening a file without saved results showed wrong totals on Daily Q1 and Weekly Windows (another sheet's SUM); open calculation also 12 s, now 8 s | Next PR |
| 3b | Scrolling lags after clicking a row number: the toolbar's Overflow/Wrap button scanned every cell on the sheet on each render | Next PR |
