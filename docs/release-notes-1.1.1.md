# Spark Grid 1.1.1 release notes

Drafts for App Store Connect. Review before pasting. Text for the App Store must not name other companies' products.

## What's New in This Version

Filters you can work in, tabs you can drag, and fixes that keep your files exactly as you left them.

New
• A filter panel on every column: search its values, see how many rows hold each one, and sort A to Z or Z to A. Click the same sort again to put the rows back.
• The tab bar shows how many rows a filter is showing, with one click to clear it. Filter changes can be undone.
• Drag a sheet tab to move it. The new order saves with the file.
• Command-arrow jumps to the edge of your data. Scroll bars appear while you scroll.
• Command-click or Command-drag removes cells, rows, or columns from a selection.

Fixed
• Formatting comes back when you reopen a file that has conditional formatting.
• Sorting, filling, and pasting formulas keep their brackets, so the results stay right.
• Undo works after you open a file.
• Copy, cut, and delete skip rows a filter hides.
• Saving after a sort is quick, and quitting no longer waits on a save.
• ROUND rounds exact half cents correctly. XLOOKUP, XMATCH, IFS, TEXTJOIN, and CONCAT now calculate in files from other spreadsheet apps. INDEX across one row works.
• Large sheets stay smooth after you resize rows or columns, and the grid no longer stretches after you resize the window.
• Closing a large workbook no longer hangs.

Please check: in 1.1, sorting, filling, or pasting a formula with brackets, such as =A2*(1-B2), could save it without them and change its result. If you did that in a file and saved it, check those formulas and totals.

## Promotional Text (170 characters max)

Filters with search, counts, and sort. Drag tabs to reorder. Formatting and formulas stay exactly as you saved them.

## Website and press, on release day

- `web/changelog/index.html`: replace the `RELEASE DATE` comment and "November 2026" with the release date.
- `web/press/index.html`: add the 1.1.1 release date to "Current version".
- Deploy `web/` with the Vercel CLI from the repo root (see the website notes in the deploy memory). The What Works and press pages are in this branch now.
