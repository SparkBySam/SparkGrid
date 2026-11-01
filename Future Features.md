### Future Features

Compatibility first: never lose what is in a file, then let people edit it. Each big feature ships in two halves: keep it (show it and save it back unchanged), then edit it.

**Shipped**

- 1.1: large workbooks open fast, saving never freezes the window, and formula cells show their results with the formula in the formula bar
- 1.1.1: filter panel (search, counts, sort and unsort, undo), drag tabs to reorder, Command-arrow, overlay scroll bars, Command-click and Command-drag to deselect
- 1.1.1: fixed fill drag jumping near the bottom of the screen, Delete Rows removing only one row, formula brackets lost on sort, formatting lost on open, Undo after opening a file, saves stuck after a sort

**1.2: Nothing gets lost**

Built on `claude/1.2` (Oct 29, 2026), not yet released:

- Done: keep everything a save dropped in the Oct 29 audit: hidden rows, columns and sheets; sheet protection; dropdown lists, comments, links and tables; charts the app does not draw yet; pivot tables; grouped rows and columns, page setup, headers and footers, and tab colors. A saved copy opens in Excel with no repair prompt.
- Done: hidden rows and columns stay hidden in the grid, with Hide and Unhide for rows, columns and sheets
- Done: dropdown lists work (pick from the list); comments show a mark and appear on hover; links open
- Done: functions batch 1 (37 functions, including MEDIAN, MOD, INT, PRODUCT, LARGE, SMALL, RANK, MAXIFS, MINIFS, FIND, SEARCH, PROPER, VALUE, the IS functions, WEEKDAY, EDATE and EOMONTH) and the #NUM! error
- Done: fill series: the fill handle continues numbers, dates, numbered text, and month and day names; Option-drag copies
- Done: sort by more than one column
- Done: Settings, Sort, Format Cells, Conditional Formatting, Name Manager, Insert Chart and Print use the filter panel's look
- Done: a column added or removed inside a table joins or leaves the table, and its filters follow
- Done: make and edit dropdown lists and comments; name box (go to an address, range or name) and F2 to edit; rules filters (contains, begins with, greater than, between, top and bottom N); App Store rating prompt

**1.3: Charts and lists**

- Pie and scatter charts, and charts with more than one series, from files and newly made

**1.4: Pivot tables**

- Pivot tables from files show and refresh
- Create a pivot table from a range

**1.5: Start faster and Mac-native**

- Start screen with blank sheet, templates, and recent files
- Template sheets, bundled in the app
- Finder Quick Look preview
- Numbers import

**Later**

- Shortcuts and AppleScript
- Multiple windows
- Version history (Revert To, Browse All Versions)
- PDF export and the share sheet
- More functions, including FILTER, SORT, and UNIQUE
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
