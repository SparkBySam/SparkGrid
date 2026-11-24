# Spark Grid 1.5 release notes

Drafts for App Store Connect. Review before pasting. Text for the App Store must not name other companies' products, and App Store Connect rejects "<" in What's New (".numbers documents" and "other spreadsheet apps" instead). What's New must stay under 4,000 characters.

## What's New in This Version

A start screen with templates, .numbers documents, a window for each workbook, Share and Shortcuts, AppleScript, and answers that match other spreadsheet apps in hundreds more cases.

New
• A start screen with ten templates and your recent files.
• Open .numbers documents, with their formulas, formats, merged cells and borders.
• Each workbook opens in its own window.
• File > Share sends the workbook to Mail, Messages, AirDrop and more, unsaved changes included.
• Shortcuts actions: open a workbook, read or set a cell, and export a PDF or CSV.
• AppleScript can open workbooks, read and write cells, save, and export.
• Quick Look shows a workbook as it looks in the grid, with its results worked out.
• Scroll bars you can drag, with settings for when they show.
• 98 more functions, including LET, TEXTSPLIT, VSTACK, HSTACK, TAKE, DROP, TRANSPOSE, RANDARRAY, INDIRECT, OFFSET, ADDRESS, LOOKUP, YEARFRAC, and trigonometry, statistics and finance.
• Lists of values typed straight into a formula.
• A range or a function given a range, typed in a cell on its own, fills the cells below: =A1:A10, =B1:B8*10, =LEN(D1:D8).
• Formulas such as SUM(LEN(A1:A8)) work through the range, one value at a time.

Improved
• Typing 10:30, $1,234.50, 1,234 or (5) stores a time, money, a grouped number or a negative number.
• TEXT and cell formats follow the format code in every detail checked, including dates before March 1900.
• Lookups find the last number or the last text the way other apps do, and exact lookups accept * and ? wildcards.
• Long chains of formulas calculate in a fraction of the time.
• Editing a large workbook is quicker.
• Print preview stays sharp when zoomed, and sharing a saved workbook is faster.
• When another app removes something Spark Grid keeps in a file, Spark Grid says what was removed.

Fixed
• A window made narrower no longer pushes the grid off to the right.
• A change on one sheet followed at once by a change on another no longer loses the first.
• Totals of a range ignore TRUE, FALSE and text, as other apps do.
• Comparisons such as 1=TRUE give the same answers as other apps.
• A formula that points at an empty cell shows 0.
• Formulas typed after a workbook opens update when the sheets they read change.
• Readers of a formula's spilled results, such as =SUM(C1#), update when the results change.

## Promotional Text (170 characters max)

Start from a template, open .numbers documents, share in a click, and get the same answers as other spreadsheet apps, with 98 more functions.

## Before submitting

- Version 1.5, build 10 (build 9 has a comparison bug; do not submit it).
- App Store screenshots: the 1.3 set still shows the app correctly; a start-screen shot would show what is new.
- App Review notes: Shortcuts actions and AppleScript need no account or setup.

## Website and press, on release day

- `web/changelog/index.html`: the 1.5 entry's date (`RELEASE_DATE_1_5`).
- `web/press/index.html`: "Current version" date.
- `web/what-works`: date at the top.
- `web/sitemap.xml`: `RELEASE_DATE_1_5_ISO`.
- Deploy `web/` with the Vercel CLI from a fresh worktree of main.
