### Future Features

Compatibility first: never lose what is in a file, then let people edit it. Each big feature ships in two halves: keep it (show it and save it back unchanged), then edit it.

**Shipped**

- 1.1: large workbooks open fast, saving never freezes the window, and formula cells show their results with the formula in the formula bar
- 1.1.1: filter panel (search, counts, sort and unsort, undo), drag tabs to reorder, Command-arrow, overlay scroll bars, Command-click and Command-drag to deselect
- 1.1.1: fixed fill drag jumping near the bottom of the screen, Delete Rows removing only one row, formula brackets lost on sort, formatting lost on open, Undo after opening a file, saves stuck after a sort
- 1.2 (Nov 4, 2026): nothing gets lost on save (hidden rows, columns and sheets, protection, dropdown lists, comments, links, tables, charts, pivot tables, grouping, page setup, tab colors); dropdown lists and comments you can make and edit; hide and unhide; fill series; sort by more than one column; rule filters; name box and F2; 37 more functions
- 1.3 (Nov 6, 2026): charts from files drawn on the sheet, then moved, resized and edited; pie, scatter and multi-series charts; the Charts panel; Find Duplicates; tables you can make and style; tab colors; AutoSum and the selection sum; icon set thresholds; a new Settings window with shortcuts you can change

**1.4: Pivot tables, links, and the everyday tools**

Agreed with Sam on Nov 7, 2026, in this order:

1. Toolbar flow: one row, no ribbon tabs, today's symbols kept. Decimals as one control, size arrows on the size field, Strike under More, one Layout menu for Align, Vertical, Overflow and Rotate. Then Sort, Filter, AutoSum (Sum, Average, Count, Max, Min) and Highlight, then Chart, Table, Pivot and Link. Captions hide first in a narrow window, then groups fold into a » menu. Mockup: https://claude.ai/artifact/L6jYAukHF113WrJEEhK97S
2. Paste Special: values only, formats only, transpose
3. Format Painter
4. Fill Down and Fill Right (Command-D, Command-R)
5. Clear: formats only, contents only, all
6. Functions batch 2: PMT, NPV, IRR, FV, PV, RATE, NETWORKDAYS, WORKDAY, DATEDIF, DAYS, COUNTUNIQUE, FILTER, SORT, UNIQUE and more. Nov 7: 65 functions in (loans and cash flows, working days and week numbers, STDEV/VAR/PERCENTILE/QUARTILE/MODE, CORREL/SLOPE/FORECAST, MROUND/TRUNC/LOG/FACT/GCD, SWITCH/CHOOSE/XOR, TEXTBEFORE/TEXTAFTER, HYPERLINK's text). Nov 11: FILTER, SORT, SORTBY and UNIQUE in, with results that spill into the cells below and beside the formula (#SPILL! when something is in the way). They save and open as other apps' spilling formulas. Not yet checked against a file saved by another app; spills on sheets you are not looking at update when you switch to them
7. Text to Columns. Nov 7: done (delimiters, repeats as one, quoted text, preview, one undo). Nov 11: fixed width added (break positions, suggested from the gaps that line up)
8. Group and outline rows and columns (make and remove groups, fold them). Nov 7: done: Sheet menu Group/Ungroup (Shift-Command-K/J), Collapse or Expand Group, Collapse/Expand All, +/− in the headers, nested groups, saved with the outline depth other apps need. Nov 11: Sheet > Show Row Levels / Show Column Levels (1, 2, 3…) do what the level buttons do; no button strip beside the headers
9. Sheet protection on and off. Nov 7: done: Protect/Unprotect Sheet with optional password (reads SHA-512 and legacy hashes, writes legacy), Format > Locked, locked cells/rows/columns/formatting refused with an alert, unlocked cells and protection saved. Nov 11: the file's allow flags (format cells/rows/columns, insert/delete rows/columns, links, sort, filters) are honoured and can be set in Protect Sheet
10. Print area and page breaks. Nov 10: done: File > Print Area (set, clear), Sheet > Insert/Remove/Reset Page Breaks with dashed lines on the grid, both saved per sheet the way other apps read them. Printing now splits pages on row and column edges, honours breaks, repeats headers and frozen rows/columns, and leaves hidden rows and columns off. Several separate print areas on one sheet are kept but not printed
11. PDF export. Nov 10: done: File > Export as PDF and a Save as PDF button in the Print window, same pages as printing, text kept as text, each sheet paged on its own when exporting the workbook. Printing the workbook pages each sheet the same way now
12. Links: add, edit and remove hyperlinks on a cell (web and email), internal links to a sheet, cell or named range, Command-click to follow, and HYPERLINK. Nov 11: done: Insert > Link (Command-K) and the cell menu add, edit and remove links; Command-click follows web, email, sheet/cell/range and named-range links, and =HYPERLINK formulas (including "#Sheet!A1"). No toolbar button (the toolbar is full at laptop widths)
13. Pivot tables: those in files show and refresh; create one from a range; a field panel (Rows, Columns, Values, Filters; sum, count, average, min, max); date grouping; GETPIVOTDATA; pivot charts. Nov 11, part 1 done: Data > PivotTable makes one from a range on a new sheet, a field panel (Rows, Columns, Values with sum/count/average/min/max, Filters with item choices), Edit and Refresh, one undo step each. Settings save in the xlsx as xl/sparkGrid/pivotsN.json (Sam OK'd Nov 11); other apps see the values. Date grouping (year, quarter, month, day) done Nov 11. PivotChart (follows the table) done Nov 11. GETPIVOTDATA done Nov 11 (reads the drawn table; formulas on the pivot's sheet recalculate when it redraws). File pivots refresh done Nov 11: Refresh reads a file pivot's fields, hidden items and source, draws it in Spark Grid's layout where it was, links it (editable, GETPIVOTDATA), keeps the file's pivot with its area covering the drawing and refreshOnLoad set so the other app rebuilds it. Calculated fields, grouped fields, show-values-as and other summaries are left as drawn with a message. Not yet tried in Excel (unlicensed here)
14. Out of sight: the whole-workbook recalculation follows cell dependencies (the stress workbook's last 74 mismatches), and the five failing debug checks are fixed. Nov 11: done. Whole-workbook recalculation is the dependency-ordered pass (stress workbook 0 of 114,609 wrong, both paths); every evaluator knows its sheet. BugBash 96/96

**1.5: Start faster and Mac-native**

- Start screen with blank sheet, templates, and recent files
- Template sheets, bundled in the app
- Finder Quick Look preview
- Numbers import

**Later**

- Shortcuts and AppleScript
- AI connectors (Sam, Nov 11): let assistants such as Claude, Cursor and ChatGPT read and change an open workbook, for example through a local MCP server. It runs on the Mac and talks only to apps on it, so the app still never uses the network itself. Starting point: the `spark-grid-cli` commands and the engine's command list
- Multiple windows
- Version history (Revert To, Browse All Versions)
- The share sheet
- More functions after batch 2
- Polish: cells pop in while scrolling fast. Show the empty grid under tiles still being drawn and fade tiles in (check a Release build first)
- Polish: after a resize the grid repaints on the main thread instead of returning to pre-drawn tiles
- Polish: draggable overlay scroll bars

**Website (sparkgridapp.com)**

- Accounts live on the website, not in the app. The app stays account-free and never uses the network.
- Community template gallery and uploads, for signed-in users
- Paid template packs: the plan for making money. The app stays free.
- Templates download as ordinary .xlsx files that the app opens

**Back burner**

- Spark Suite bundle, if other Spark apps get paid tiers
