# Bugs

One list of known bugs. Add a bug when it's found, with steps if there are any. Move it to Fixed with the PR that fixed it. Feature requests go in `docs/gaps.md`, not here.

Workbooks named here are fixtures in `Fixtures/`. Never name a customer file.

## Open

| # | Bug | Where | Notes |
| --- | --- | --- | --- |
| | A product like 186000 × 0.7 showed as 130199.99999999999 instead of 130200 | 1.4 (`claude/1.4`): numbers show at most 15 significant digits, as Excel does |

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
| | Seven BugBashRunner checks failed on every run, so a new failure was easy to miss | 1.4 (`claude/1.4`), Nov 11: all 96 pass. The shared-formula check builds its workbook instead of reading Fixtures (the sandbox blocks it); the three pixel checks capture the grid's own frame plus the chart and frozen-pane views (`layer.render` misses both off screen); the spell check waits for the open calculation; the unsaved-prompt check uses a spreadsheet window; the conditional bold check no longer expects the extension copy of each rule that Nov 4 removed |
| | `FormulaEngine.recalculateEntireWorkbook` mixed up unqualified ranges across sheets: three evaluators were built without their sheet's name, so Daily Q1's `SUM(C5:C64)` read Monthly Summary's cached C5:C64; with the name set, the sheet-wave pass read row-strip formulas as blank (190 cells on the stress workbook) | 1.4 (`claude/1.4`): every evaluator knows its sheet, and the whole-workbook pass is the dependency-ordered pass the app runs on open (0 mismatches on the stress workbook's 114,609 formulas, faster). The wave pass stays as `recalculateEntireWorkbookInSheetWaves` for the fast-path counter checks |
| | Cells typed in this session went blank when scrolling with the trackpad, and came back on a click (seen in 1.3 on a CSV while editing). The grid scrolls with pictures it draws while idle; an edit redrew the cell on screen but left those pictures as they were. | 1.4 (`claude/1.4`): the pictures covering an edited cell are dropped and drawn again; BugBash `edit then tile scroll shows edit` |
| | Sort A to Z then Undo left #REF! in the Total row: the sort took the total row along, its SUM moved up off the sheet, and Undo put the rows back but not the formulas | 1.4 (`claude/1.4`): Undo puts back each formula as it was, and the toolbar sort leaves a total row under the table in place |
| 7 | No toolbar control for tables | 1.3: Insert → Table, the Data menu (Create Table, Table Style, Remove Table) and the cell menu. No toolbar button: the toolbar is full at laptop widths (Sam, Nov 7) |
| | Segmented controls (Settings, Find Duplicates, Sort, filters, dropdown lists, Print) and the Settings tabs stayed macOS blue with Spark amber chosen | 1.4 (`claude/1.4`) |
| | Typing a value did not update a chart from the file that reads it, or recolor the rest of a color scale, data bar or icon set range, until the sheet was redrawn (switching sheets) | 1.3 (`claude/1.3`) |
| | Opening a file into a running Spark Grid (Finder, `open`) quit the app: SwiftUI closed the only window to open the file in a new one. In 1.2 too | 1.3 (`claude/1.3`) |
| | Excel's default text color (`theme="1"`) was read as white: numbers vanished on light fills in dark mode, and the color was saved back as white. Theme colors 0 to 3 were in the wrong order | 1.3 (`claude/1.3`) |
| | The window title stayed "Spark Grid" when a file opened while the app was in the background | 1.3 (`claude/1.3`) |
| | Google Sheets showed no conditional formatting in files saved by Spark Grid: each rule was also written to an extension block with a made-up id | 1.3 (`claude/1.3`) |
| | Opening a file with rules in both the sheet and Excel's extension block kept only the extension's rules | 1.3 (`claude/1.3`) |
| 6 | Charts from other apps are kept on save but not drawn | 1.3 (`claude/1.3`) |
| | Sheet tab colors from other apps were kept on save but not shown, and couldn't be set | 1.3 (`claude/1.3`) |
| | Files saved with a Spark Grid chart had an invalid drawing part (`<xdr:xfrm>` closed as `</a:xfrm>`), so strict apps could ask to repair them and drop the chart. Since Oct 15 | 1.3 (`claude/1.3`) |
| | Objects in one drawing shared ids: every Spark Grid chart was 2, pictures 1, 2, 3… Each object now gets its own | 1.3 (`claude/1.3`) |
| | After AutoSum (or any edit that keeps the selection) the edited row lost its gridlines until the next full redraw | 1.3 (`claude/1.3`) |
| | Inserting a row or column took 1.4 to 2.1 s on the stress workbook: every formula on every sheet was parsed. Now only formulas naming the sheet, in parallel: 0.04 s on a small sheet, 0.65 s on Orders | 1.3 (`claude/1.3`) |
| | Closing the Settings window asked to close the whole app | 1.3 (`claude/1.3`) |
| | Icon set checkmark drawn upside down; stacked bar labels overlapped | 1.3 (`claude/1.3`) |
| | Icon sets saved as 0/33/67 percent and drew by percentile instead of their own thresholds | 1.3 (`claude/1.3`) |
| | Files' "duplicate values" and "unique values" highlight rules were dropped on open | 1.3 (`claude/1.3`) |
| 11 | No visible controls for comments: resting on a commented cell shows its card | Spark-Grid#77 / SparkGrid#1 |
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
| | Reopening a file saved after a sort looks empty: recalculating its 114,599 formulas took 6 minutes in Release (now 8 s) | Spark-Grid#77 / SparkGrid#1 |
| | Unqualified VLOOKUP tables on two sheets at the same address could share one cached lookup | Spark-Grid#77 / SparkGrid#1 |
| | Data bars lose their saved scale (0 to 1.5 came back min to max) | Spark-Grid#77 / SparkGrid#1 |
| 2 | Sorting looks like it only sorts the typed columns: formula columns kept showing the old row's results at each address after a sort, and scroll tiles drew the unsorted rows | Spark-Grid#77 / SparkGrid#1 |
| | Highlights vanished after a reopen: a rule reading a formula cell got a blank when the cell's value came from the background calculation | Spark-Grid#77 / SparkGrid#1 |
| | Typing in a cell, switching sheets, then clicking a cell saved the typing twice: once on its own sheet and again into the cell selected on the new sheet, and undo then crossed sheets | Spark-Grid#77 / SparkGrid#1 |
| | In dark mode, automatic text on a file's light fill (such as a totals row) drew white and was nearly invisible | Spark-Grid#77 / SparkGrid#1 |
| | Hiding the active sheet jumped to the first tab instead of the one beside it | Spark-Grid#77 / SparkGrid#1 |
| | File → Open accepted any text file and opened it as a one-column CSV | Spark-Grid#77 / SparkGrid#1 |
| | Highlight rules lost after reopening a file without saved results: they were worked out from the blanks shown while it calculated | Spark-Grid#77 / SparkGrid#1 |
| | Opening a file without saved results showed wrong totals on Daily Q1 and Weekly Windows (another sheet's SUM); open calculation also 12 s, now 8 s | Spark-Grid#77 / SparkGrid#1 |
| 3b | Scrolling lags after clicking a row number: the toolbar's Overflow/Wrap button scanned every cell on the sheet on each render | Spark-Grid#77 / SparkGrid#1 |
