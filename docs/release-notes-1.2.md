# Spark Grid 1.2 release notes

Drafts for App Store Connect. Review before pasting. Text for the App Store must not name other companies' products.

## What's New in This Version

Your files come back exactly as you saved them, with dropdown lists, comments, hidden rows and sheets, and much more.

New
• Saving keeps everything a workbook had: hidden rows, columns and sheets, grouped rows, tab colors, protection, page setup, dropdown lists, comments, links, tables, charts, and pivot tables.
• Dropdown lists: pick a value from a cell's list, or make your own with Data > Dropdown List.
• Comments: rest the pointer on a cell with a red corner to read its comment. Add and edit them from the cell's menu.
• Hide and unhide rows, columns, and sheets. Small arrows in the headers mark hidden rows and columns; click one to show them again. Hide Sheet and Unhide Sheet are in the Sheet menu.
• Filter by rule: contains, begins with, greater than, between, top and bottom, and dates.
• The fill handle continues numbers, dates, numbered text, and month and day names. Option-drag copies.
• Type a cell or name into the name box to go there. F2 edits the selected cell.
• 37 more functions, including MAXIFS, MINIFS, and the #NUM! error.
• The formula bar shows percents and dates the way the cell does, and typing a date stores a date.

Improved
• Files without saved results open and calculate much faster.
• Scrolling draws cells right away instead of filling them in.
• Large format changes, such as alternating row colors on thousands of rows, apply in one step and undo in one step.
• Frozen rows and columns have a clearer edge.
• In dark mode, text on light cell colors stays readable.

Fixed
• After a sort, formula columns show the right results for their rows.
• Highlighting rules stay on after you save and reopen a file.
• Totals that add up the same range on two sheets each use their own sheet.
• Data bars keep their scale when you save.
• Typing in a cell and then switching sheets no longer copies the text to the other sheet.
• Undo after switching sheets returns you to where you were.
• Selecting a merged cell highlights all of it.
• ROUND no longer shows -0.
• Open shows only spreadsheet files.

## Promotional Text (170 characters max)

Dropdown lists, comments, hidden rows and sheets, rule filters, and a smarter fill handle. Every workbook comes back exactly as you saved it.

## Website and press, on release day

- `web/changelog/index.html`: add a 1.2 entry with the release date.
- `web/press/index.html`: set "Current version" to 1.2 and its release date.
- Deploy `web/` with the Vercel CLI from the repo root.
