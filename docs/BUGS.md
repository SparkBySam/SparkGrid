# Bugs

One list of known bugs. Add a bug when it's found, with steps if there are any. Move it to Fixed with the PR that fixed it. Feature requests go in `docs/gaps.md`, not here.

Workbooks named here are fixtures in `Fixtures/`. Never name a customer file.

## Open

| # | Bug | Where | Notes |
| --- | --- | --- | --- |
| | A formula with an empty argument, such as `=IF(A2>1,,2)` or `=VLOOKUP(A1,B:C,2,)`, did not parse, so it showed nothing | 1.5 (`claude/1.5-empty-arguments`): an argument left out reads as a blank (0, "" or FALSE), and IF, CHOOSE, SWITCH, IFERROR and IFNA give 0 when they pick one; written back as typed (`EmptyArgumentTests`) | Found importing Numbers formulas, which now bring these in as formulas |
| | `%` after a value (`=A2%`, `=B2*10%`) was not read at all, so the formula showed nothing | 1.5 (`claude/1.5-numbers-formulas`): postfix percent divides by 100, binding tighter than `^` and a sign, as other apps read it (`PercentOperatorTests`) | Found importing Numbers formulas |
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
| | Trackpad and mouse scrolling went the opposite way to the Mac's setting, up/down and left/right (a Reddit review of 1.4, Nov 18: "completely backwards to what macOS does"). The grid added the scroll amounts where macOS means them to be taken away, so it felt right only with Natural Scrolling off, as on Sam's Mac | 1.6 (`claude/1.6-scroll-direction`): the grid follows the Mac on both axes; Settings › General › Scrolling › Reverse scroll direction turns it around for the grid (BugBash "scroll follows the Mac") |
| | `=SUM(B1:INDEX(B:B,COUNTA(B:B)))`, the usual way to sum down to the last filled row, did not parse, nor did `INDIRECT("B1"):INDIRECT("B3")` or the space (intersection) operator `B1:B9 A3:D3`; ISREF, ISFORMULA, CELL, PERCENTILE.EXC and QUARTILE.EXC were #NAME? | 1.6 (`claude/1.6-references`): `:` takes any reference on either side (INDEX, INDIRECT, OFFSET), a space between references is their intersection (`#NULL!` when they share no cell), and the five functions are written; 38 formulas match Excel 16.115 (`ExcelEdgeCaseTests`) |
| | A formula typed into a General cell showed a plain number where other apps format it: =DATE(2026,3,1) as 46082, =PMT(...) as -1073.64324602428, =A1+30 on a date as a number | 1.6 (`claude/1.6-auto-formats`): `FormulaAutoFormat` gives the format Excel 16.115 gives, for each of 35 formulas asked of it (`FormulaAutoFormatTests`) |
| | Text that reads like a number lost being text: ZIP codes such as 02134 showed as 2134, 007 as 7 (LEN 1), long IDs as 1.2E+19, ISTEXT was FALSE and SUM added them. Saving wrote them as numbers, so the zeros were gone for good in every app (since 1.0; caught live on Nov 18 when the stress workbook, saved by the 1.5 Debug build, turned its text "1" into the number 1). Typing '007 kept the apostrophe | 1.6 (`claude/1.6-text-cells`): `Cell.isText` marks it from a file's text cells and from a typed apostrophe; reads, formulas and saving honour it; the formula bar shows '007. The build-10 stop-gap that compared number-like text with numbers as numbers is gone; text is never equal to a number, as in Excel (`TextCellTests`) |
| | After saving and reopening, the formula bar showed `=IF(D7="","",_xlfn.XLOOKUP(...))`: formulas from a file kept the `_xlfn.` / `_xlfn._xlws.` prefixes the file stores newer functions with (XLOOKUP, XMATCH, IFS, TEXTJOIN, CONCAT, FILTER, SORT, UNIQUE, SEQUENCE and the rest), and `_xlfn.ANCHORARRAY(G1)` instead of `G1#` | `claude/1.6-xlfn-display`, Nov 17: opening removes the prefixes the save adds back (cells, shared formulas, conditional-format formulas, defined names), so a save writes the same text; conditional-format and defined-name formulas now get the prefixes on save too (`ExcelFutureFunctions.unprefixed`, `FutureFunctionPrefixTests`) |
| | After the Nov 18 comparison change, `TEXTAFTER("north-west-1","-",-1)` compared with a cell holding the text "1" was FALSE: a cell's text that reads as a number is read back as that number, so text "1" from a formula met a number 1 (the stress workbook's New in 1.4 check D79, found by the release check of 1.5 build 9) | 1.5 (`claude/1.5-numeric-text`): number against number-like text compares as numbers, as before; the rest of the order stays (`ExcelEdgeCaseTests`) |
| | A window made half as wide after starting full width pushed the grid far to the right and cut the toolbar off (Sam, Nov 18; in 1.4 and 1.5; a window opened at half width was fine). The toolbar measured its own width to choose how much to show, and a wide variant kept that width when the window shrank, so it still "fit" | 1.5 (`claude/1.5-toolbar-shrink`): the width measured is the window's (`minWidth: 0`), the toolbar clips for the moment before folding; checked full → half → full, with and without captions |
| | OFFSET, LOOKUP and YEARFRAC were #NAME? | 1.5 (`claude/1.5-offset-lookup-yearfrac`): written, 97 formulas match Excel 16.115 |
| | Every edit on the stress workbook's Orders sheet spent 2.3 s (Release) looking for spilling formulas: each of 105,000 formulas was uppercased and searched for thirty function names | 1.5 (`claude/1.5-range-spills`): one pass over the bytes, 0.063 s for all sheets |
| | `=A1:A3`, `=B1:B8*10`, `=LEN(D1:D8)` and `=ROW(B1:B4)` typed in a cell were #VALUE!; other apps spill them | 1.5 (`claude/1.5-range-spills`) (`RangeSpillTests`) |
| | `=A3` with A3 empty, an IF or lookup picking an empty cell, and an empty cell in a FILTER or SORT spill showed blank where other apps show 0, and formulas reading them saw an empty cell (found by script) | 1.5 (`claude/1.5-blank-answers`) (`CrossSheetSequenceTests`) |
| | Approximate lookups took the largest value up to the needle, so `MATCH(9.99E+307,B:B)` and `MATCH("zzz",D:D)`, which other apps answer with the last number and the last text, gave other rows; VLOOKUP and MATCH with a text needle and TRUE found nothing; `MATCH(2,1/(…))` was #N/A; `"~"<"a"` was FALSE | 1.5 (`claude/1.5-sorted-search`): Excel's sorted search and text order, 37 of 37 lookups match Excel 16.115 (`ExcelEdgeCaseTests`) |
| | INDIRECT and ADDRESS were #NAME? | 1.5 (`claude/1.5-indirect-address`): written, checked against Excel 16.115 |
| | `SUM(LEN(A1:A8))`, `MAX(IF(B1:B8<50,B1:B8))`, `SUMPRODUCT(LEN(…))` and FILTER with `ISNUMBER(SEARCH(…))` were #VALUE!: a one-value function given a range did not work through it | 1.5 (`claude/1.5-array-maths`): 44 of 44 array formulas match Excel 16.115 (`ExcelEdgeCaseTests`) |
| | A second batch of 126 formulas against Excel 16.115: 94 matched. Fixed: COUNTIF(…,"*") counted numbers and TRUE (wildcards match text only) and ">a" counted TRUE; VALUE did not read dates or times; LEFT and RIGHT with a negative count gave blank, not #VALUE!; TRIM removed non-breaking spaces and tabs; `0.0,,"M"` did not scale; TEXT("abc","@@") gave abc | 1.5 (`claude/1.5-bug-bash-2`): 102 of 126 match; the rest are in docs/gaps.md item 4 (`ExcelEdgeCaseTests`) |
| | 176 edge-case formulas typed into Excel 16.115 and Spark Grid by script: 148 matched. Fixed: TRUE in a range counted as 1 in SUM, COUNT and AVERAGE; `1=TRUE` was TRUE and `"10"<"9"` FALSE; `0.1+0.2=0.3` was FALSE; `(-8)^(1/3)` showed "nan" and overflow "inf"; DAY, MONTH and YEAR read serials up to 60 a day early (YEAR(1) was 1899); exact VLOOKUP, HLOOKUP and MATCH ignored wildcards; exact lookups matched an empty cell for 0; XLOOKUP refused its sixth argument and an empty if_not_found; UPPER("straße") was STRASSE and PROPER("o'neil") O'neil; MAX of no numbers was #VALUE! | 1.5 (`claude/1.5-bug-bash-2`): 166 of 176 match; the rest are in docs/gaps.md (`ExcelEdgeCaseTests`) |
| | A typed time (`10:30`, `9:05 am`) stayed text, so SUM of hours was 0; `(5)` and `($1,234.50)` stayed text; `$1,234.50` and `1,234` lost their currency and grouping when shown; `1,23` read as 123 (found by script) | 1.5 (`claude/1.5-typed-entry`): stored and shown as Excel 16.115 stores the same typing (`TypedEntryTests`) |
| | A formula typed after opening a file, reading another sheet that reads this one back (`Data!G1 = 'Second Sheet'!B1*2`, B1 = `SUM(Data!E1:E6)`), kept its old answer when Data changed, even retyped, until something on Second Sheet was edited. The workbook graph built at open did not have the typed formulas (found by script) | 1.5 (`claude/1.5-bug-bash`): a changed formula rebuilds the graph off the main thread (0.4 s for the stress workbook in Release) (`CrossSheetSequenceTests`) |
| | Two edits to different sheets in quick succession lost the first one's reach: Config!B5 then a cell on another sheet left the Dashboard total and Orders flags with the old answers until a full recalculation (found by script on the stress workbook) | 1.5 (`claude/1.5-bug-bash`): a background update replaced by one for another sheet is carried into it (`CrossSheetSequenceTests`) |
| | `SUM(C1#)`, `ROWS(C1#)` and other readers of a spill kept the old answer when a value further down the spill changed or the spill grew, until something else recalculated them (found by script) | 1.5 (`claude/1.5-bug-bash`): they recalculate once the spill is laid out (BugBash "spill readers without waiting") |
| | TEXTJOIN and SUMPRODUCT read only the first value of a typed list or a spilling result: `SUMPRODUCT({1,2,3},{4,5,6})` was 4, `TEXTJOIN("-",TRUE,{3,1,2})` was "3" (found by script) | 1.5 (`claude/1.5-bug-bash`) (`ArrayShapeTests`) |
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
