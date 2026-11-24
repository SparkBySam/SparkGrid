# Spark Grid 1.4 release notes

Drafts for App Store Connect. Review before pasting. Text for the App Store must not name other companies' products. What's New must stay under 4,000 characters.

## What's New in This Version

Pivot tables, links, printing and PDFs, grouping, sheet protection and 70 more functions, plus a toolbar that fits on one row.

New
• Data > PivotTable summarizes a range on a new sheet with rows, columns, values and filters. Dates group by year, quarter, month or day. PivotChart charts it, and GETPIVOTDATA reads from it. Pivot tables save as pivot tables other apps can refresh.
• FILTER, SORT, SORTBY, UNIQUE and SEQUENCE fill the cells below and beside the formula. =SUM(C1#) uses all of C1's results.
• 66 more functions, including PMT, FV, NPV, IRR, XIRR, NETWORKDAYS, WORKDAY, DATEDIF, STDEV, PERCENTILE, FORECAST, SWITCH, TEXTBEFORE and TEXTAFTER.
• Paste Special: values only, formats only, or transposed (Paste Values is Option-Shift-Command-V).
• Format Painter, Fill Down (Command-D), Fill Right (Command-R), and Edit > Clear for contents, formats or both.
• Data > Text to Columns splits text at commas, tabs or any character, or at fixed widths, with a preview.
• Group rows or columns (Shift-Command-K) and fold them with + and −. Groups in your files fold too.
• Sheet > Protect Sheet, with an optional password, choosing which cells stay open and what is still allowed. Allow Edit Ranges keeps chosen ranges editable, and Lock Range locks a range on its own.
• Print areas and page breaks, saved with the workbook. File > Export as PDF makes the same pages as printing, with text you can search.
• Insert > Link (Command-K) links a cell to a web page, an email address, or a place in the workbook. Command-click to follow it.
• Sort, AutoSum, Highlight, Chart and Table are in the toolbar, and in a narrow window it folds into a » menu instead of wrapping.

Improved
• Deleting rows and columns on a large workbook is faster.
• Arrow keys, Return and Tab stay quick in a half-width window.
• Option-drag the fill handle to count up from one number.
• Print setup can leave out the column letters and row numbers.
• Workbooks are checked for size as they open, so a damaged or oversized file stops with a message instead of filling memory.

Fixed
• Typing over a cell no longer shows a suggested word over your letters.
• Coloring cells while a filter is on leaves the hidden rows alone.
• Undo can no longer undo a sheet's protection.
• Printed pages end between rows, and frozen rows repeat on every page, including when the print area starts further down.
• Cells you had just typed no longer go blank when you scroll with the trackpad.
• Workbooks with newer functions such as XLOOKUP, IFS or TEXTJOIN open in other spreadsheet apps without #NAME?.
• Grouped columns, clipped text and print areas open correctly in other spreadsheet apps.
• Comparing text in a formula ignores upper and lower case.
• Results such as 186,000 × 70% show as 130200, not 130199.99999999999.
• Undoing a sort puts every formula back as it was.
• Sorting leaves a total row under the table where it is.
• Choices and the Settings tabs follow the accent color you pick.

## Promotional Text (170 characters max)

Pivot tables, links, print areas and PDF export, grouping, sheet protection and 70 more functions, with a toolbar that fits on one row.

## Before submitting

- App Store screenshots: still to make for 1.4 (pivot table, Paste Special or Format Painter, grouping, protection, PDF export).
- App preview videos: optional for 1.4; the 1.3 previews still show the app correctly.

## Website and press, on release day

- `web/changelog/index.html`: add a 1.4 entry with the release date.
- `web/press/index.html`: set "Current version" to 1.4 and its release date.
- `web/what-works`: pivot tables, links, printing, protection and grouping now work.
- Deploy `web/` with the Vercel CLI from the repo root.
