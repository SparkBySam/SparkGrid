### Future Features

Compatibility first: never lose what is in a file, then let people edit it. Each big feature ships in two halves: keep it (show it and save it back unchanged), then edit it.

**Shipped**

- 1.0 (Oct 6, 2026): first Mac App Store release
- 1.1 (Oct 15, 2026): large workbooks open fast, saving never freezes the window, and formula cells show their results with the formula in the formula bar
- 1.1.1 (Oct 29, 2026): filter panel (search, counts, sort and unsort, undo), drag tabs to reorder, Command-arrow, overlay scroll bars, Command-click and Command-drag to deselect
- 1.1.1: fixed fill drag jumping near the bottom of the screen, Delete Rows removing only one row, formula brackets lost on sort, formatting lost on open, Undo after opening a file, saves stuck after a sort
- 1.2 (Nov 4, 2026): nothing gets lost on save (hidden rows, columns and sheets, protection, dropdown lists, comments, links, tables, charts, pivot tables, grouping, page setup, tab colors); dropdown lists and comments you can make and edit; hide and unhide; fill series; sort by more than one column; rule filters; name box and F2; 37 more functions
- 1.3 (Nov 6, 2026): charts from files drawn on the sheet, then moved, resized and edited; pie, scatter and multi-series charts; the Charts panel; Find Duplicates; tables you can make and style; tab colors; AutoSum and the selection sum; icon set thresholds; a new Settings window with shortcuts you can change
- 1.4 (live Nov 18, 2026; build 8 uploaded Nov 17): everything in the 1.4 list below
- 1.5 (build 10 submitted for review Nov 18, 2026; build 9 uploaded the same day has a comparison bug and was not submitted): everything in the 1.5 list below

**1.4: Pivot tables, links, and the everyday tools** (all done; live Nov 18, 2026)

Agreed with Sam on Nov 7, 2026, in this order:

1. Toolbar flow: one row, no ribbon tabs, today's symbols kept. Decimals as one control, size arrows on the size field, Strike under More, one Layout menu for Align, Vertical, Overflow and Rotate. Then Sort, Filter, AutoSum (Sum, Average, Count, Max, Min) and Highlight, then Chart, Table, Pivot and Link. Captions hide first in a narrow window, then groups fold into a » menu. Mockup: https://claude.ai/artifact/L6jYAukHF113WrJEEhK97S. Done Nov 7; a window shrunk from full width pushed the grid right until the Nov 18 fix (in 1.5)
2. Paste Special: values only, formats only, transpose. Done Nov 7
3. Format Painter. Done Nov 7
4. Fill Down and Fill Right (Command-D, Command-R). Done Nov 7
5. Clear: formats only, contents only, all. Done Nov 7
6. Functions batch 2: PMT, NPV, IRR, FV, PV, RATE, NETWORKDAYS, WORKDAY, DATEDIF, DAYS, COUNTUNIQUE, FILTER, SORT, UNIQUE and more. Nov 7: 65 functions in (loans and cash flows, working days and week numbers, STDEV/VAR/PERCENTILE/QUARTILE/MODE, CORREL/SLOPE/FORECAST, MROUND/TRUNC/LOG/FACT/GCD, SWITCH/CHOOSE/XOR, TEXTBEFORE/TEXTAFTER, HYPERLINK's text). Nov 11: FILTER, SORT, SORTBY and UNIQUE in, with results that spill into the cells below and beside the formula (#SPILL! when something is in the way). They save and open as other apps' spilling formulas. Nov 12: checked against a file Excel saved
7. Text to Columns. Nov 7: done (delimiters, repeats as one, quoted text, preview, one undo). Nov 11: fixed width added (break positions, suggested from the gaps that line up)
8. Group and outline rows and columns (make and remove groups, fold them). Nov 7: done: Sheet menu Group/Ungroup (Shift-Command-K/J), Collapse or Expand Group, Collapse/Expand All, +/− in the headers, nested groups, saved with the outline depth other apps need. Nov 11: Sheet > Show Row Levels / Show Column Levels (1, 2, 3…) do what the level buttons do; no button strip beside the headers
9. Sheet protection on and off. Nov 7: done: Protect/Unprotect Sheet with optional password (reads SHA-512 and legacy hashes, writes legacy), Format > Locked, locked cells/rows/columns/formatting refused with an alert, unlocked cells and protection saved. Nov 11: the file's allow flags (format cells/rows/columns, insert/delete rows/columns, links, sort, filters) are honoured and can be set in Protect Sheet. Nov 13: Allow Edit Ranges and range locks
10. Print area and page breaks. Nov 10: done: File > Print Area (set, clear), Sheet > Insert/Remove/Reset Page Breaks with dashed lines on the grid, both saved per sheet the way other apps read them. Printing now splits pages on row and column edges, honours breaks, repeats headers and frozen rows/columns, and leaves hidden rows and columns off. Several separate print areas on one sheet are kept but not printed
11. PDF export. Nov 10: done: File > Export as PDF and a Save as PDF button in the Print window, same pages as printing, text kept as text, each sheet paged on its own when exporting the workbook. Printing the workbook pages each sheet the same way now
12. Links: add, edit and remove hyperlinks on a cell (web and email), internal links to a sheet, cell or named range, Command-click to follow, and HYPERLINK. Nov 11: done: Insert > Link (Command-K) and the cell menu add, edit and remove links; Command-click follows web, email, sheet/cell/range and named-range links, and =HYPERLINK formulas (including "#Sheet!A1"). No toolbar button (the toolbar is full at laptop widths)
13. Pivot tables: those in files show and refresh; create one from a range; a field panel (Rows, Columns, Values, Filters; sum, count, average, min, max); date grouping; GETPIVOTDATA; pivot charts. Nov 11, part 1 done: Data > PivotTable makes one from a range on a new sheet, a field panel (Rows, Columns, Values with sum/count/average/min/max, Filters with item choices), Edit and Refresh, one undo step each. Settings save in the xlsx as xl/sparkGrid/pivotsN.json (Sam OK'd Nov 11); other apps see the values. Date grouping (year, quarter, month, day) done Nov 11. PivotChart (follows the table) done Nov 11. GETPIVOTDATA done Nov 11 (reads the drawn table; formulas on the pivot's sheet recalculate when it redraws). File pivots refresh done Nov 11: Refresh reads a file pivot's fields, hidden items and source, draws it in Spark Grid's layout where it was, links it (editable, GETPIVOTDATA), keeps the file's pivot with its area covering the drawing and refreshOnLoad set so the other app rebuilds it. Calculated fields, grouped fields, show-values-as and other summaries are left as drawn with a message. Nov 13: checked in Excel 16.115 and saved as real pivot tables there (refresh on open, filters, GETPIVOTDATA); date-grouped pivots stay values
14. Out of sight: the whole-workbook recalculation follows cell dependencies (the stress workbook's last 74 mismatches), and the five failing debug checks are fixed. Nov 11: done. Whole-workbook recalculation is the dependency-ordered pass (stress workbook 0 of 114,609 wrong, both paths); every evaluator knows its sheet. BugBash 96/96

**1.5: Start faster and Mac-native** (all done; build 10 submitted Nov 18, 2026)

Agreed with Sam on Nov 17, 2026; added to the same day and on Nov 18:

- Start screen with blank sheet, templates, and recent files. Done Nov 17 (#92): shown when Spark Grid opens with no file and from File > New from Template; ten templates in Personal, Business and Planning, with real previews and an info button
- Template sheets, bundled in the app. Done Nov 17 (#92): ten, built in code (Monthly Budget, Expense Report, Loan Calculator, To-Do List, Invoice, Sales Pipeline, Timesheet, Inventory, Project Tracker, Weekly Schedule)
- Finder Quick Look preview. Done Nov 17 (#93): the preview (every sheet, simple edits and Save, since 1.0) now looks like the grid and calculates formulas a file saved no results for
- Numbers import. Done Nov 17 (#94, #95, #97) and Nov 18 (#101): values, formats and every table open, formulas come in as formulas (references across tables and sheets included), and fills, fonts, colors, alignment, headers, sizes, merged cells, wrapping, vertical alignment and borders come in
- Empty formula arguments such as =IF(A2>1,,2). Done Nov 17 (#96)
- Warning when another app removed what Spark Grid keeps in a file. Done Nov 17 (#98)
- Multiple windows, one per workbook. Done Nov 17 (#99)
- The share sheet (File > Share) and Shortcuts actions (open, get cell, set cell, export). Done Nov 18 (#103)
- AppleScript (open, workbook names, cell value, put value, save, export). Done Nov 18 (#109)
- More functions after batch 2: LET, TEXTSPLIT, VSTACK, HSTACK, TAKE, DROP, CHOOSECOLS, CHOOSEROWS, WRAPROWS, WRAPCOLS, TOCOL, TOROW, RANDARRAY (Nov 18, #102); typed lists such as {1,2,3} and batch 3, 68 more (Nov 18, #106); INDIRECT and ADDRESS (Nov 18, #115); OFFSET, LOOKUP and YEARFRAC (Nov 18, #119). 259 functions in all
- Correct answers, checked against Excel 16.115: TEXT and number formats (480 cells), long chains in linear time (Nov 18, #108); about 800 formulas typed into Excel and Spark Grid by script, with the differences fixed (Nov 18, #110–#122): array maths, sorted lookups, comparisons, empty-cell answers, ranges that spill, typed times and money
- Polish: draggable overlay scroll bars, with Settings for always-shown bars and their length. Done Nov 18 (#104, #105)
- Polish: cells pop in while scrolling fast; tiles now fade in over the empty-grid placeholder. Done Nov 18 (#107)
- Polish: after a resize the grid repainted on the main thread; a resize now keeps the tiles. Done Nov 18 (#107)
- Fix: a window shrunk from full width pushed the grid off to the right (in 1.4). Done Nov 18 (#120)
- Speed: every edit on a big sheet spent seconds looking for spilling formulas (2.3 s on the stress workbook's Orders sheet). Done Nov 18 (#118): 0.063 s for every sheet

**Next, agreed Nov 18, 2026** (in this order)

1. Text that looks like a number keeps being text: codes and ZIP codes such as 007 and 02134 from a file, Excel's quote-prefix mark, and `'007` typed with the apostrophe hidden. Spark Grid stores a cell's contents as text and reads anything number-like back as a number, so it cannot tell text "1" from 1 (found by the 1.5 release check)
2. Formula bar without Excel's `_xlfn.` prefixes (started Nov 17 on `claude/relaxed-morse-961203`, not pushed). Nov 18: brought onto main as PR #126
3. Excel's automatic number formats: a DATE result shows as a date, PMT and the other money functions as currency. Nov 18: done on `claude/1.6-auto-formats` (35 formulas match Excel)
4. The rest of the Nov 18 Excel check: ISREF, ISFORMULA, CELL, PERCENTILE.EXC; the intersection operator (`B1:B3 B2:B5`); `INDIRECT("B1"):INDIRECT("B3")`. Nov 18: done on `claude/1.6-references`, plus ranges ending at INDEX (`B1:INDEX(B:B,5)`); CELL's width and format and the comma union are left (docs/gaps.md)
5. Release timing of edits on the stress workbook, and the spill's first cell that shows blank for a moment after an edit

**From the Reddit thread, Nov 19, 2026** (Sam: "add all of the not added requested features")

- Done Nov 19 on `claude/1.6-reddit`: Edit › Go To (Control-G, into the name box); Edit › Select Blank Cells; Find › Regular Expression with $1 groups in Replace; Help › Spark Grid Help (offline guide); Save As keeps a CSV a CSV; formula completion adds `(` when a function is picked from the list, and Backspace no longer brings the name back; Copy and Save Chart as Image; one Series checklist in the chart editor; open markers on line charts and a marker shape per series; a function Spark Grid does not have shows the file's saved result instead of #NAME?. Mouse wheels move two rows a notch (#131); trackpad direction (#129)
- Also done Nov 19: open .ods files (values, text, dates, times, true/false, formulas with saved results, merged cells; formatting not yet); every installed font in the font menu.
- Also done Nov 19: error bars on bar and line charts with one series, from a column of plus-or-minus amounts; saved as the chart's own error bars, which Excel 16.115 reads.
- Also done Nov 19 (Sam: "why not add them"): SEM, MEAN, MEAN.ARITH, MEAN.GEOM and MEAN.HARM. Files store the formula other apps calculate (SEM as STDEV.S/SQRT(COUNT), MEAN as AVERAGE); what was typed is kept in xl/sparkGrid/formulasN.json and shown again on open. Checked in Excel 16.115

**Ideas for 1.6 and later** (Sam, Nov 18, 2026; not ordered yet)

- Live collaboration over iCloud (CloudKit `CKShare`). Sam chose this on Nov 18: no Spark Grid accounts and no server; people share a workbook by Apple ID, as Notes and Numbers do, and edits go across as cell changes within a second or two, with each person's selection in a color. The app works without it, as now. Using iCloud is a change to "the app never uses the network": the privacy policy and App Store privacy answers need updating with it. Likely a release of its own (2.0)
- AI connectors: let assistants such as Claude, Cursor and ChatGPT read and change an open workbook through a local MCP server. It runs on the Mac and talks only to apps on it. One way that keeps the sandboxed app off the network: a small helper the assistant starts, which drives the app through AppleScript; the AppleScript commands grow to cover sheets, ranges, formulas and formats. Starting points: `SparkGrid.sdef`, the `spark-grid-cli` commands and the engine's command list (Sam, Nov 11 and Nov 18). Nov 18: `spark-grid-mcp` built (ten tools: list, read values and formulas, write cells, used range, add sheet, save, open, export) with six new AppleScript commands; see `docs/mcp.md`. Sam chose to ship it inside the app (Nov 18): Contents/Helpers, its own sandbox (Apple Events to Spark Grid only, files in Downloads only), and Settings › AI with copy buttons for Claude Desktop, Cursor and Claude Code
- A local language model in the app for formula help ("total sales for the West region", "explain this formula"), scripting help, and building a sheet from a description. Decided with Sam on Nov 18:
  - Built in: Apple's on-device model (Foundation Models framework) for everyday formula help. Free, nothing to download, private, and able to call Spark Grid's own commands as tools. Needs macOS 26 on an Apple Intelligence Mac, and is a small model, so not enough for power users on its own
  - For power users: connect a model they already run on the Mac (Ollama, LM Studio). Covers heavier sheet building and scripting, and Macs that cannot run Apple's model
  - No bundled model: it would not run well on every Mac, and would be a new dependency and a 1–2 GB download
  - Talking to a local model means connecting to `localhost`, which a sandboxed app needs the outgoing-connections entitlement for. Privacy policy and App Store answers: "connects only to a model running on your own Mac, if you set one up". Do this in the same privacy pass as iCloud collaboration
- Version history: local snapshots while you work, Revert To and Browse All Versions
- iPad version: the engine and file code are already a separate package
- Sparklines and more chart types (waterfall, combo)
- Data cleanup tools: trim spaces, split names, turn text-numbers into numbers, remove blank rows
- Better CSV import: preview, delimiter, encoding and column types; paste tables straight from web pages
- Find and Replace across every sheet, and Go To Special (formulas, errors; blanks done Nov 19)
- Pivot table calculated fields
- VoiceOver and keyboard accessibility pass

**Website (sparkgridapp.com)**

- Accounts live on the website, not in the app. The app stays account-free and never uses the network.
- Community template gallery and uploads, for signed-in users
- Paid template packs: the plan for making money. The app stays free.
- Templates download as ordinary .xlsx files that the app opens
- 1.5 pages ready on `claude/web-1.5` (Nov 18); date and deploy when 1.5 is live

**Back burner**

- Spark Suite bundle, if other Spark apps get paid tiers
