# Status

Updated: 2026-11-23. Commit this file in the same commit as the work it describes.

## App icon, on `claude/1.7-app-icon`

- The Dock icon looked oversized next to other Mac icons, with no transparent edge (Ludovic by email, djaysan on r/macapps). The artwork filled the whole 1024 canvas with opaque light-amber corners. It now follows Apple's macOS grid: an 824×824 shape centered on the 1024 canvas (100 px of transparent margin), with continuous corners (radius 185.4) and the template drop shadow (0, 10, blur 10, 30% black). The amber grid and bolt are the old artwork, scaled with the shape. Every size in `AppIcon.appiconset` is made from that 1024 image.
- Source: `design/app-icon/glyph-1024.png` (the grid and bolt on transparency) and `design/app-icon/render-icon.swift` (`swift render-icon.swift glyph-1024.png out.png`); the smaller sizes are Lanczos downscales of the result.
- Checked: the Release build's AppIcon.icns has the new art, and side by side with Calculator and Notes the shape is the same size.

## Build 14, on `claude/1.7-build-14` (Nov 23)

Sam, Nov 23, after 1.6 cleared review: 1.7 goes out as build 14 with the icon fix and these four.
- Unlocked cells imported as locked from files that write cell styles as self-closing tags (openpyxl and others), so a protected sheet refused them; text rotation and clip went to the wrong cells for the same reason. `XLSXCodec.xfElementPattern` reads both forms (`StyleIndexScanTests`; with `SPARK_GRID_FIXTURES` it checks the stress workbook too). Found on the iPad branch.
- A link within the workbook saved as an outside address starting with `#` (`#'Orders'!A1`, as openpyxl writes it) did nothing on Command-click. `CellHyperlink.place` / `.outsideTarget` read it as the place it is; the tooltip too (`LinkPlaceTests`).
- Settings › General › Readable text on filled cells (Sam's idea, so people aren't confused by text changing color), on by default as before: off, text keeps its own color on fills and conditional fills. Only the screen and printing change. `SparkTheme.readableTextOnFills`, `ConditionalFormatEvaluator.resolvedPaint(readableText:)` (`ReadableTextSettingTests`).
- REGEXTEST, REGEXEXTRACT and REGEXREPLACE (`FormulaEvaluator+Regex.swift`), 99 formulas against Excel 16.115 (`ExcelRegexTests`): case options, every match and the groups across a row, replacements with `$1`, `${name}`, `$$` and `\n`, errors where Excel gives them, letters like é for `\w`. Foundation's regular expressions differ from Excel's in one place: after an empty match Excel also tries a longer one there, so `a*?` finds more matches in Excel. In What's New and Help.
- Checked in the Mac app with BugBash (`build14Additions`, 130/130): REGEXEXTRACT spills 12, 2026, 11, 23 on the grid, a dark conditional fill's text is light with the setting on and its own color off, and `#'Orders'!B2` selects Orders B2. Not clicked through by hand: the Debug build shares Sam's app's ID and settings while his copy was open.
- Nov 24, the archived Release app (1.7 (14)) checked by hand on a copy of the stress workbook, dark mode, with Sam's copy closed: regex formulas through AppleScript spill and draw (H22:I22 41,362,409 and 15,000; groups A, 17; a shorter result clears the old spill cells; Edit › Undo brings it back); errors red; Insert Function lists the three; Settings › Readable text on filled cells turns the Total row's text white at once and back; Protected 1.4 takes 77 in unlocked B6 and keeps D6's formula; the saved file has `_xlfn.REGEX…` and spilling array formulas; What's New lists both new items.
- Fixed from that check: the Link dialog (Insert › Link…) read a `#'Orders'!A1` link as a web address; it now opens it as a place, as Command-click does (`LinkSheet` uses `place` / `outsideTarget`).
- Noted, not changed: AppleScript `put value` into a locked cell is refused without an error.

## 1.7, on `claude/1.7-polish`

- "i" buttons on Conditional Formatting's rule type (one explanation per type) and on Settings › General › Bar length, Keep earlier versions and the formulas warning.
- What's New: Formula Help's line mentions charts from a description; "Save as .ods" became "More ways to save" (.ods, tab-separated text, web page); new "Your own shortcuts". Help › Files describes .tsv and .html; Help › Charts mentions Describe it and the ⓘ on chart types.
- Bug test: five new checks (`BugBashRunner+Nov21.swift`): Remove Table restores filled headers, every command has its own default shortcut and none is reserved (38 actions; change and reset), Clear Formats keeps values, the .tsv and .html exports, and LAMBDA in place, criteria arrays and a missing sheet typed into the grid. 129/129 pass.
- Checked in the Debug app (background), with Apple Intelligence on this Mac: Formula Help on bt.csv gave =SUM(C2:C9) = 11,836 for "total of column C"; Insert Chart › Describe it with "units by month as a line with a trend" chose Line, Units, a linear trendline and the title; the ⓘ popovers; Settings › Shortcuts (F2 and ⌥↓ shown) and › AI ("Ready on this Mac").

## 1.7, on `claude/1.7-lambda-call`

- From Sam's hand test of the 1.7 stress workbook (Nov 20). A LAMBDA called where it is written, `=LAMBDA(x,x*3)(7)`, gives 21 (it was #ERROR!: the parser stopped at the second brackets). It parses as `SG.CALL(LAMBDA(...), 7)` (`FormulaExpr.lambdaCallFunction`), also for a LAMBDA that gives a LAMBDA (`(3)(4)`); it spills when the LAMBDA's body does, and .ods writes it back as typed. LET calls a LAMBDA it names, `=LET(f,LAMBDA(x,x+1),f(9))` = 10 (was #NAME?), and no longer works a LAMBDA out early. `LambdaCalledInPlaceTests`.
- A range or list where SUMIF, SUMIFS, COUNTIF, COUNTIFS, AVERAGEIF(S) and MAXIFS/MINIFS take criteria gives one answer per criterion, and spills: `=SUMIFS(H12:H15,A12:A15,B12:B15)` was #VALUE! (Formula Help wrote it). `criteriaSlots` / `criteriaLifted`. The #VALUE! hint for several values in one cell no longer mentions ARRAYFORMULA (not an Excel function). `CriteriaArrayTests`.

## 1.7, on `claude/1.7-ui-fixes`

From Sam's hand test of the 1.7 stress workbook (Nov 20).
- Shortcuts: every Spark Grid command can be remapped in Settings › Shortcuts, 38 in all, in eight groups: New, Open, Save As, Print, Find, Find and Replace, Find Next/Previous, Go To, Select All, Edit Cell (F2), Open Dropdown List (⌥↓), Insert Link, Formula Help, Group/Ungroup, Zoom, Help and the new Clear Formats (⌘\\), with those before. Menus read them with `.hotkey(_:_:)`; the grid reads Edit Cell and Open Dropdown List. A function key alone can be recorded. Only Quit, Close, Hide, Minimize and Settings stay fixed. Every row has its reset button, greyed out at the default; Reset All stays.
- Cut, Copy and Paste act on a text field that has the keyboard (a dialog's field, the formula bar, a cell being edited), as Select All did: pasting into Formula Help's question pasted into the cell (`FocusedText`).
- Clear Formats: ⌘\\, in the Format menu and the cell's right-click menu (with Clear Contents), as well as Edit › Clear and the toolbar's More.
- Remove Table puts back header cells it filled ("Column 1"…) that nobody changed (`SheetTable.filledHeaders`, by column within the table).
- Goal Seek: Return in a field is Find (then Keep); the spinner and "Finding…" show before the search starts; Find and Keep run once.
- Formula Help: describes the block of data around or above the selected cell, not the top of the sheet; asks again once when its formula gives an error, and says so when it still does.
- Apple Intelligence: Settings › AI › Use Apple Intelligence (on by default, `AppSettings.usesAppleIntelligence`) with its status; off, Formula Help leaves the Insert menu and Describe it leaves Insert Chart. Help has an Apple Intelligence topic.
- Insert Chart › Describe it: a sentence becomes the chart kind, columns, trendline and title (`ChartHelper`, the model on the Mac; only kinds and columns that exist are taken).
- "i" buttons (`SparkInfoButton`): each chart kind, trendlines, sparkline types, validation alert styles, Describe it. The sparkline type picker is the app's own.
- Toolbar drop-downs are popovers in the app's look (`ToolbarMenuButton.Style`): rows highlighted in amber that close after a choice. Layout is a panel: alignment as icons, Overflow/Wrap/Clip, and rotation as tiles showing "Ab" at each angle. The narrow-window overflow menu stays a system menu (it has submenus).
- Help is drawn in the app's style with a search field; the Shortcuts topic says every shortcut can be changed.
- The autosave pop-up uses the app's rows and switch.
- Show in the unsupported-functions note scrolls to the cell.
- Save As adds Tab-Separated Text (.tsv) and Web Page (.html: every visible sheet as it looks, `HTMLExporter` over `PreviewPresentation`). After saving a web page the window keeps its own file, keeps no version and doesn't list it in Open Recent. `WebPageAndTSVExportTests`.
- Not reproduced: after rotating text and resizing rows, Sam's grid showed a row number twice and clicks landing between cells (stale drawing). Resizing rows, even to almost nothing, redrew correctly here.

## 1.7, on `claude/1.7-popup-design`

- From Sam's hand test (Nov 20). The data validation alert and the note about functions Spark Grid can't calculate were system alerts (blue buttons, app icon); both are now `SparkDialog` sheets like Goal Seek's. `ValidationAlertSheet`: the rule's title and message (or plain defaults), the typed entry and cell under the title, a stop, warning or info symbol; Stop has OK only, Warning Keep / Don't Keep, Information OK / Cancel; closing it any other way refuses the entry. It opens after the edit ends, on the workbook's window (`WorkbookWindows.window(showing:)`): opened while no window was key it came up as a loose window, and once crashed in a loop of size changes. `UncalculatedFormulasSheet`: a row per function with its cells, first cell and a Show button; text that fits the file (an .xlsx keeps saved results; an .ods or Numbers file isn't changed; a CSV has no results, so the cells show #NAME?); Save a Copy… on the left, opening beside the file; "Don't tell me about this again". `SparkDialog` takes no Cancel button (`cancelTitle: nil`) and `SparkDialogPresenter.present` an `onEnd`.
- Formula Help leaves sheet names out of what it doesn't need them in: `SheetPrefixes.keepingOnly` (Formula) takes the name off references to this sheet and to sheets the workbook doesn't have, in the formula and its explanation; other sheets keep theirs. Its model had written `=SUMIF(Sheet1!B2:B5,1200)` and "Sheet1!B2:B5" for a sheet named Report. The instructions say so too, with a plain total as an example (it had made up a condition for "total of column B"). `SheetPrefixesTests`.
- Goal Seek shows its answer to six decimals (it showed 26495.3531619636); Keep still writes the full value.
- Checked in the Debug app in the background: both sheets, Show, the Stop alert on the window. Not yet: Warning and Information alerts, Save a Copy from the new note, Formula Help after the change.

## 1.7, on `claude/1.7-missing-sheet-ifs`

- SUMIF, SUMIFS, COUNTIF, COUNTIFS, AVERAGEIF(S), MAXIFS/MINIFS and COUNTBLANK over a sheet the workbook doesn't have give #REF!, as `=Nope!A1` and `=SUM(Nope!A1:A3)` already did; they gave 0, because every cell of the missing sheet reads #REF! and these functions skip error cells. Found in the Nov 20 hand test: Formula Help's model wrote `=SUMIF(Sheet1!B2:B5,1200)` on a sheet named Report and the preview and cell said 0. `missingSheetError` in `FormulaEvaluator+Everyday.swift` (reads the sheet's last cell, blank on a real sheet). `MissingSheetCriteriaTests` (8 cases fail without the fix).

## 1.7, on `claude/1.7-chart-excel-fixes`

- Charts saved by Spark Grid, opened in Excel 16 (Nov 20): the axes had no labels, because the axis parts left out `<c:delete val="0"/>` (true of every chart saved since 1.3). Axes now write it with tick marks and labels. Horizontal bars put the first category on top (category axis `maxMin`, value axis crossing at `max`), as Spark Grid draws them. With more than one series the first takes its header as its name, not the chart title. Pie and doughnut series write no color, so each slice gets its own. `ChartTrendlineTests.testChartPartsDrawTheSameElsewhere`.

## 1.7, on `claude/1.7-whats-new`

- What's New for 1.7 (`ReleaseNotes.all["1.7"]`) adds new charts and trendlines, sparklines, Goal Seek, saving as .ods and the note about functions Spark Grid can't calculate (#152–#156, all merged Nov 20).

## 1.7, on `claude/1.7-unsupported-warning`

- Opening a file whose formulas call functions Spark Grid doesn't have shows a note on the window (from a Reddit comment, Nov 20): each function with its cell count and first cell, what that means (the saved results show and don't update; the formulas are saved back unchanged), and OK, Show First Cell, Save a Copy… (copies the file as it is on disk; not offered for an .ods or Numbers file, which is never written over), and "Don't tell me about this again". Settings › General › Saving, "Warn about formulas it can't calculate" (on by default). The scan (`UnknownFunctions.uses`) runs off the main thread after the file opens, and leaves out names the workbook defines and LET and LAMBDA names. Not shown in the bug test, benchmarks or unit tests. `UnknownFunctionUsesTests`. Checked in the Debug app.

## 1.7, on `claude/1.7-ods-save`

- Save and Save As offer OpenDocument (.ods) beside .xlsx and CSV, with the panel's File Format menu shown (macOS 15+). `ODSExporter` (FileFormats) writes every sheet: values, formulas in OpenFormula (`OpenFormulaPrinter`, from the parsed formula, with brackets, `;`, `TRUE()`, `COM.MICROSOFT.` for newer functions) with their results, number formats, bold/italic/underline/strikethrough, colors, fonts, alignment, wrapping, rotation, borders, merged cells, column widths, row heights, hidden rows and columns, hidden sheets and named ranges. `mimetype` first and stored. Not written: charts, pictures, comments, conditional formatting, data validation, filters, sparklines, spilled array formulas as arrays (their values are written). An .ods still opens as a new workbook, so Save never writes over one it did not just write. `ODSExporterTests`: formula printing, OpenFormula read back, a two-sheet round trip through `ODSImporter`; the XML passes xmllint. Not opened in LibreOffice (not installed here).

## 1.7, on `claude/1.7-sparklines`

- Sparklines (`SparklineGroup` in Model, kept in `SheetFileExtras.sparklines`): line, column and win/loss, one per row or column of the data (`SparklineGroup.layout`), with a color, markers and high/low points. Read from and written to the worksheet's `<extLst>` as `<x14:sparklineGroups>` (`XLSXCodec+Sparklines.swift`), so files from other apps keep theirs; data on another sheet works. They move with inserted and deleted rows and columns (`SheetStructureMutation`). Drawn by `SparklineLayerView` in the grid's chart layer, under charts; Insert › Sparklines… (`SparklinesSheet`) and Clear Sparklines, each one undo step. `SparklineTests`. Checked in the Debug app (insert, replace, undo). Not yet: sparklines in printing and PDF export, and in cells under frozen rows or columns (the frozen pane covers them), axis and first/last point options, editing a group after it is made.

## 1.7, on `claude/1.7-charts`

- New chart kinds in `SheetChart.Kind`: horizontal bar, stacked bar, stacked horizontal bar, stacked area, doughnut. They draw in the series plot (`ImportedChartPlot`) and save as `barChart` (`barDir`, stacked grouping with overlap 100), stacked `areaChart` and `doughnutChart` (hole 50).
- Trendlines (`ChartTrendline` in Model): linear, exponential, logarithmic, power, moving average, with the equation and R² above the plot. On bar, line, area and scatter charts of values; category charts fit against x = 1…n as other apps do. Saved as `<c:trendline>`; trendlines in charts from other apps are read and drawn (not polynomial). `ChartTrendlineTests`. Checked in the Debug app with a demo of every new kind. Not checked in Excel by hand. Not added: radar, histogram, waterfall, box.

## 1.7, on `claude/1.7-goal-seek`

- Data › Goal Seek (`GoalSeek` in Calc, `GoalSeekSheet`): the formula cell, the value it should reach and the input cell; the search (secant steps, at most a thousandfold jump, 100 tries) runs on its own engine over a copy of the workbook, across sheets too, and the answer is shown before Keep writes it as one undo step. No exact answer reports the closest. `GoalSeekTests`: a loan amount for a 500 payment (25,862.78), a square across sheets, a negative square (not found), refusals. Checked in the Debug app.

## 1.7, on `claude/1.7-welcome-versions`

- Version 1.7 (13). Build 14 (Nov 23) is the same 1.7 with the app icon on Apple's macOS grid (#165); 13 was archived before it and never uploaded.
- Settings › General › Saving › Keep earlier versions, on by default (Sam, Nov 20): off, saves keep no versions; File › Browse Versions still shows those already kept.
- Welcome and What's New (`LaunchIntro`, `WelcomeView`, `WhatsNewView`): the first time Spark Grid opens it says thanks and shows what it does; the first time a new version opens, What's New lists `ReleaseNotes` for that version. Someone who used a version before 1.7 (recent files, or a file opened before) gets What's New, not the welcome. Help › Welcome to Spark Grid and Help › What's New show them again. Not shown under BugBash, benchmarks or tests; a Debug build launched with SPARK_GRID_RESET_INTRO=1 forgets the version seen. Checked in the Debug app.

## 1.7, on `claude/1.7-functions-d` (on top of `-c`)

- Functions batch 7 (`FormulaEvaluator+Batch7.swift`), 61 functions: the coupon functions, PRICE, YIELD, DURATION, MDURATION, ACCRINT (period by period), ACCRINTM, DISC, INTRATE, RECEIVED, PRICEDISC, YIELDDISC, PRICEMAT, YIELDMAT, the T-bill functions, VDB, AMORLINC, AMORDEGRC, FVSCHEDULE, DOLLARDE, DOLLARFR, PDURATION, RRI; CONVERT with every unit, prefix and temperature Excel has (its factors read from Excel itself); COMPLEX and the 25 IM functions; BESSELJ, Y, I and K. 195 formulas (`ExcelBatch7Tests`) and 354 conversions (`ExcelConvertTests`) match Excel 16.115. Excel's Bessel answers are only good to about 1e-5 of themselves; Spark Grid's are exact, and the test allows the difference. Excel's day counts were found by trying each candidate against its answers: PRICE and DURATION take the days to the next coupon as the period less the days gone, one-coupon YIELD at basis 2 the period's actual length, VDB leaves out LibreOffice's mid-life adjustment.
- Not written: the four ODD coupon functions, the ETS forecasts, cube, web and RTD functions, STOCKHISTORY, IMAGE, INFO, PHONETIC.

## 1.7, on `claude/1.7-functions-c` (on top of `-b`)

- Functions batch 6 (`FormulaEvaluator+Batch6.swift`): LAMBDA (#CALC! on its own, as in Excel), MAP, REDUCE, SCAN, BYROW, BYCOL, MAKEARRAY, ISOMITTED, EXPAND, GROUPBY and PIVOTBY (headers, totals at the top or bottom, sort, filter, a LAMBDA or a function by name; PIVOTBY one row field, one column field and one value column). A function name given bare (`BYROW(A1:B2,SUM)`) works and saves as `_xlfn._xleta.SUM`; LAMBDA parameters save as `_xlpm.` names. 67 formulas typed into Excel 16.115 match (`ExcelBatch6Tests`).
- Defined names that are formulas, not ranges, now calculate (`NamedFormulas`): constants such as `Tax = 0.07`, moving ranges built with OFFSET, and LAMBDAs called by name (`=Hyp(3,4)`, recursive ones too). Before 1.7 they were #NAME?. Their cells are not in the dependency graph, so a formula reading such a name is not recalculated by an edit to the cells the name reads (docs/gaps.md item 9).

## 1.7, on `claude/1.7-functions-b` (on top of `-a`)

- Functions batch 5 (`FormulaEvaluator+Batch5.swift`), 69 functions: every probability distribution and inverse Excel has except the ETS forecasts (beta, binomial and its range and inverse, chi-squared, exponential, F, gamma, hypergeometric, lognormal, negative binomial, Poisson, t, Weibull, with their pre-2010 names), CHISQ.TEST, F.TEST, T.TEST (all three types), Z.TEST, CONFIDENCE.NORM and .T, PROB, STEYX, MDETERM, and the spilling FREQUENCY, MODE.MULT, LINEST and LOGEST (with stats, several x columns, no constant), TREND, GROWTH, MMULT, MINVERSE and MUNIT. 157 formulas typed into Excel 16.115 give the same answers to nine digits (`ExcelBatch5Tests`; array results read one value at a time through INDEX). The incomplete beta and gamma functions are continued fractions; inverses are found by bisection.

## 1.7, on `claude/1.7-functions-a`

- Functions batch 4 (`FormulaEvaluator+Batch4.swift`), 87 functions: SUBTOTAL and AGGREGATE (all 19 functions and 8 options, the array form for LARGE, SMALL and the percentiles), the 12 database functions (D-criteria: plain text matches text starting with it), NETWORKDAYS.INTL and WORKDAY.INTL, SHEET, SHEETS, FORMULATEXT, AREAS, COT/CSC/SEC and their hyperbolic and inverse forms, CEILING.PRECISE, ISO.CEILING, FLOOR.PRECISE, COMBINA, PERMUTATIONA, FACTDOUBLE, MULTINOMIAL, SERIESSUM, SUMX2MY2, SUMX2PY2, SUMXMY2, GAMMA, GAMMALN(.PRECISE), GAUSS, PHI, ROMAN (all five forms), ARABIC, BASE, DECIMAL, the twelve BIN/OCT/DEC/HEX conversions, BITAND/OR/XOR/LSHIFT/RSHIFT, DELTA, GESTEP, ERF, ERFC and their .PRECISE forms, the B text functions, ASC, DBCS, VALUETOTEXT, ARRAYTOTEXT, BAHTTEXT and ENCODEURL. 257 formulas typed into Excel 16.115 by script give the same answers (`ExcelBatch4Tests`). Excel for Mac has no ENCODEURL and answers #N/A for PHONETIC, which stays unwritten so a file's saved result shows.
- SUBTOTAL leaves out rows a filter hides, and 101 to 111 rows hidden by hand, as AGGREGATE does with its options (`SubtotalHiddenRowTests`). The filter's rows reach the engine as `SheetFileExtras.filteredRows` (not saved), set by `syncFilteredRowsForFormulas` when the filter changes.
## 1.7, on `claude/1.7-version-history`

- Version history (`WorkbookVersions`, `VersionsSheet`): each Save keeps a version in the Mac's own version store (`NSFileVersion`, as document apps do), an autosave at most one every ten minutes, and the first save after opening also keeps the file as it was opened unless that is already kept. File › Browse Versions lists them newest first. Open a Copy opens one in a new window as a new workbook (from a temporary copy: the version is readable only inside the file's access); Restore swaps it in as one undoable step. Checked in the sandboxed Debug app on a copy of a fixture: three versions after two saves, Restore and Undo, Open a Copy.
## 1.7, on `claude/1.7-edit-kept`

- Data validation: rules files carry were kept but did nothing. Now a typed entry is checked against the cell's rule (whole number, decimal, date, time, text length, a list, or a custom formula that must be TRUE, checked with the entry standing in for the cell so `=COUNTIF($A:$A,A1)=1` works) when the rule shows an alert: Stop refuses it, Warning asks, Information tells and keeps it unless Cancel. The rule's input message shows when pointing at the cell. Data › Data Validation makes, changes and clears rules (`DataValidationSheet`), saved as other apps write them (`DataValidationRule.Parts`, `DataValidationPartsTests`). Pasting and clearing are not checked, as in other apps. Checked in the Debug app: 500 refused with the rule's message, 50 kept, the saved `<dataValidation>` as Excel writes it.
- Comments, dropdown lists and hiding rows, columns and sheets were already editable (since 1.2 and 1.4); Help said otherwise and is corrected.
- Alerts asked while another app is in front (Move Cells' replace question, validation) sit on the workbook's window rather than floating.
## 1.7, on `claude/1.7-big-file-save`

- Big workbooks keep their formula results after a sort, a moved block, an inserted row or an Undo of a whole step (docs/gaps.md item 8): above `FormulaCacheWriter.recalculateOnSaveLimit` (40,000 formulas) the engine calculates the whole workbook in the background two seconds after the step (`scheduleStaleResultsCalculation`); an edit before it finishes starts it again. When it lands, the next save writes every result, as below the limit (`StaleResultsBackgroundTests`). A save before it lands still leaves the results out, as before.
- While Close or Quit waits for a save to finish writing, the window shows "Saving “name”…" (`SavingBeforeClosingBadge`) instead of looking stuck.
- Checked in the Debug app on a copy of the stress workbook: after an inserted row, a save once the background calculation had landed wrote results for all 114,814 formulas, the same as the original file's apart from the RANDARRAY cell; a save before then wrote none, as before. Quit during a save shows the badge until the file is written.
## 1.7, on `claude/1.7-typing-polish`

- Typed short dates and fractions as Excel 16.115 reads them (asked by AppleScript, Nov 20): `3/4`, `15-Mar`, `Mar 15`, `Mar-15`, `March 15`, `1-2` are dates this year shown `d-mmm`; a day too big for the month makes a year (`2/30` is February 1930, `mmm-yy`); `13/1` and `31/12` stay text. `1 1/2`, `-1 1/2`, `0 1/2` are numbers shown `# ?/?` (`# ??/??` for `3 10/16`); `1 1/0` stays text (`TypedEntry.shortDate`, `TypedEntry.fraction`, `ShortDateFractionErrorTests`).
- A typed error code (`#N/A`, `#n/a`, `#DIV/0!` and the other five) is the error value, saved as an error cell (`t="e"`) and opened as one; text "#N/A" from a file stays text.
- Text pasted from another app, by Text to Columns or Paste Special text, or put by a script or an AI assistant (`put values`, the helper's write_cells) reads as typing reads it: dates, money, times, fractions, error codes (`edit.paste` with `typed`, `PastedTextReadsAsTypedTests`). It stayed text, found in the 1.7 bug test through the helper. Cells copied in Spark Grid and pivot tables are left as they are.
- Pointing at another sheet while typing a formula: clicking a sheet tab while the formula waits for a reference (after `=`, `(`, a comma or an operator) shows that sheet with the formula open in the formula bar (`formulaHome`); clicked cells go in as `'Q3 Data'!B2:B4`; Return writes the formula into its own cell back on its own sheet, Escape goes back without it (BugBash "formula points at another sheet"). Not yet driven by hand: background automation could not type into the formula bar, and full-screen control was not answered.
## 1.7, on `claude/1.7-formula-help`

- Formula help with the model built into the Mac (`FormulaHelper`, `FormulaHelpSheet`; Insert › Formula Help…, Control-Command-H): Write a formula turns a sentence into a formula for the selected cell, given the sheet's name, the other sheets, and each column's header with a few values (`formulaHelpContext`); the model answers with the formula line then a sentence, after worked examples of SUMIFS, COUNTIFS, AVERAGEIFS and XLOOKUP argument order (without them it summed the wrong column, and guided generation took 152 s; plain answers take about a second), checked with the parser and shown with the result it would give, and any function Spark Grid lacks is named before Insert. Explain this formula explains the selected cell's formula. It runs on the Mac (FoundationModels, macOS 26 and Apple Intelligence; weak-linked, so the app still opens on macOS 14 and 15, where the sheet says what it needs). Nothing goes over the network, so the privacy answers stay as they are.

- Automatic number formats (`FormulaAutoFormat`, on `claude/1.6-auto-formats`): a formula typed into a General cell takes the format Excel 16.115 gives it. DATE and TODAY a date (m/d/yy), NOW a date and time, TIME a time; PMT, PPMT, IPMT, FV, PV, NPV, SLN, SYD, DDB and DB money with red negatives; RATE a percent; =A1 and + or - with a formatted cell that cell's format (two dates added stay General); SUM and ROUND the format of the cells they read. Everything else stays General, as in Excel (EDATE, EOMONTH, WORKDAY, DATEVALUE, MAX, IF, * and /). A cell with its own format keeps it. 35 formulas match Excel (`FormulaAutoFormatTests`); checked in the app by script.

## After 1.5, on `claude/1.6-text-cells`

- Text that reads like a number stays text (`Cell.isText`, an optional field, so nothing else about saved state changes): a file's text cells that look like numbers or TRUE/FALSE (02134, 007, "1", a 20-digit ID) open marked, read as text in formulas (LEN 3, ISTEXT TRUE, left out of SUM, counted by COUNTIF "*"), and save as text; `'007` typed keeps 007 as text and the formula bar shows `'007`; typing a number over it makes it a number again. Every engine read of a literal now goes through `Cell.literalValue`. Excel 16.115 gives the same answers on a file of such cells. The stop-gap in build 10 (number-like text compared with numbers as numbers) is removed: text is never equal to a number, as in Excel. The 1.5 stress workbook recalculates to every saved result except RANDARRAY's, and its text "1" survives a save (`TextCellTests`). BugBash 119/119.

- Scrolling follows the Mac (`claude/1.6-scroll-direction`): trackpad and mouse scrolling went the opposite way to System Settings, on both axes, because the grid added the scroll amounts instead of taking them away; it felt right only with Natural Scrolling off (a Reddit review of 1.4). Settings › General has a Scrolling section: Scroll bars, Bar length, and Reverse scroll direction (the setting that was there without a switch, now for both axes). BugBash "scroll follows the Mac" sends the grid a real scroll event. 120/120.

## 1.5 (version 1.5, build 10)

Everything agreed for 1.5 is merged, with the Nov 18 script bug bash and Excel checks (#92–#120). Version 1.5, build 10. Build 9 was uploaded on Nov 18 but compares text that reads as a number with a number as unequal (fixed in #122); do not submit it. Release notes, promotional text and release-day steps are in `docs/release-notes-1.5.md` (What's New 2,360 characters). Sam's manual pass is `Claude outputs/1.5 manual test list.md`. Upload, screenshots and submitting wait for Sam.

- Start screen (Sam, Nov 17; mockup https://claude.ai/artifact/CZePYnBz1nX6vJ5Xd4aBdw): Spark Grid opens to it when it opens with no file (Settings > General can turn that off, as can its own checkbox), and File > New from Template (Shift-Command-N) shows it as a sheet over an open workbook, with Cancel. Blank Workbook and ten templates in three categories (Personal: Monthly Budget, Expense Report, Loan Calculator, To-Do List; Business: Invoice, Sales Pipeline, Timesheet, Inventory; Planning: Project Tracker, Weekly Schedule), each with an info button and a preview drawn from its real cells in the window's light or dark look (`TemplatePreview`). Recent lists Open Recent's files. A template opens as a new Untitled workbook, dates counted from today. Templates are built in code with made-up data (`WorkbookTemplate`, Engine): dropdowns, highlight rules, frozen headers and formulas such as PMT/PPMT/IPMT, XLOOKUP, SUMIFS and EDATE. `WorkbookTemplateTests`: every formula calculates without an error, sample totals, and each saves and opens again; BugBash "start screen opens templates". 110/110.
- Finder Quick Look preview looks like the grid: the file's fills, bold and italic, sizes, text colors, column widths and row heights; numbers on the right; error values in red; and in dark mode automatic text on a light fill is black, as the grid draws it. Formulas a file saved no result for (such as a template saved before anything recalculated) are calculated in the background for workbooks up to 60,000 formulas; past that the preview says to open the file in Spark Grid. Logic in `PreviewPresentation` (Rendering), tested by `PreviewPresentationTests`. Release, the stress workbook (114,524 formulas, all saved): import 0.46 s, preview 0.05 s.
- Numbers documents open (File > Open, Open With, drop on the icon). Their look comes too (`NumbersStyles`): each cell's fill, text color, bold, italic, font, size and alignment (cell styles 6004 and text styles 2022 in the table's style list); the table's bold, gray header rows and columns across the whole table; column widths (every column at the table's width, so it lays out as in Numbers), row heights, and hidden rows and columns; a row with large text gets room for it, as Numbers fits it without saving a height. Colors are sRGB, rounded down as Numbers' own export does, and match it (`NumbersStyleTests`, `Fixtures/numbers-styles.numbers`). The body keeps Spark Grid's font rather than Numbers' 10 point. Merged cells come from the calculation engine's merge owners (kind 5, matched to the table by its UID); wrapping and vertical alignment come from the cell style, and in rows Numbers gave a height its own defaults show (top, wrapped), as Numbers draws them. Borders come from the table's stroke sidecar (model field 49): top, bottom, left and right layers of runs, each a stroke with a color, width (over 2 pt thick, over 1 medium) and pattern; a later order wins. Gridlines are not strokes, so they do not become borders (`NumbersLayoutTests`, `Fixtures/numbers-layout.numbers`, `Fixtures/numbers-borders.numbers`). Dashed and dotted strokes are read from the dash lengths but no sample has one yet. Every table becomes a sheet ("Sheet - Table" when a sheet has more than one), with text, numbers, dates, durations, currency, percent and true/false, the number, currency, percent and date formats, and frozen header rows and columns. Formulas come in as Spark Grid formulas showing the results Numbers saved (`NumbersFormula`): Numbers keeps them as postfix nodes, references relative to the cell or absolute, ranges, other tables and sheets (named by the table's UID block, the last three parts), and functions by number; the 139 numbers for Spark Grid's functions were read from a file Numbers saved with one formula each (20, such as IFNA and TEXT, are not Numbers functions). A whole row or column becomes the table's body without its header rows or columns, as Numbers means it and as its export writes it. A formula error keeps no saved result, so Spark Grid works out the error. A formula with a function Spark Grid lacks keeps its value. Spark Grid recalculates every formula in `numbers-formulas.numbers` and `numbers-references.numbers` to the result Numbers saved (`NumbersFormulaTests`). That check found postfix `%` missing from the formula engine; it now works everywhere (`PercentOperatorTests`). Empty arguments, such as `=IF(A2>1,,2)` and VLOOKUP's trailing comma for an exact match, now parse and read as other apps read them (`EmptyArgumentTests`). The workbook opens with the file's name and no file of its own, so Save asks where to save it as .xlsx and never writes over the Numbers file. Reader written here, no new dependency: `NumbersArchive` (Snappy, IWA chunks, protobuf objects) and `NumbersImporter` (document > sheets > tables > 256-row tiles > version 5 cell storage, decimal128 numbers). Checked against Numbers 15.4's own Excel export on two files made with its AppleScript (`Fixtures/numbers-values.numbers`, `Fixtures/numbers-tables.numbers`): every value matches. `NumbersImporterTests`. Numbers is declared as Viewer, Alternate, so it stays the default app for its files. Not tried: a package-folder `.numbers` from an old Numbers version.
- A file Spark Grid saved, then saved again by another app, says what that app removed. Spark Grid notes what it keeps in its own parts (`xl/sparkGrid/`: pivot table settings, range locks, chart settings) as a custom document property, `SparkGridExtras` in `docProps/custom.xml`, written with the file's own custom properties (those used to be dropped on save). Other apps drop parts they do not know but keep custom properties: Excel 16.115 saved a file with a range lock and kept the note while dropping the lock (`Fixtures/excel-dropped-extras.xlsx`, saved path and author name replaced). On open, extras the note names that the file no longer has show in a banner over the grid until closed, saying the data is all still there and, for range locks, that those ranges are unlocked now (`SparkGridNoteTests`). Saving again writes a note of what the workbook holds now.
- More than one workbook open at once, each in its own window (`WindowGroup` of window ids; `WorkbookWindows` keeps each window's `SpreadsheetDocumentStore`). New Spreadsheet (Command-N) opens a new window; New from Template shows the templates in place in a blank window, else in a new one. A file opened from Finder, Open, Recent or the start screen goes into the front window when that is an unused blank one, brings forward the window that already has it, and otherwise opens a new window; several files at once each get one. Menus act on the front window (the File menu through a focused `documentStore`). Quitting asks each window with unsaved changes in turn, Cancel in any stops it, and saves still being written are all waited for. Windows are not restored at launch (`isRestorable = false`): a restored window could not reopen its file without it being chosen again. SwiftUI builds a window's view more than once, for windows it never shows; only stores with a window count. Found while testing: an edit still being typed when the store first looked at the window's view model was taken as the starting point, so quitting did not ask and lost it; the store now counts from when the window registers its view model, and asking to save commits typing in the workbook's own window, not the front one (BugBash "edit before first look is asked about", fails without the fix). Crash recovery still keeps one copy, of the workbook edited last.
- Checkboxes (start screen, Filter, Protect Sheet, Find Duplicates) follow the accent color through `SparkCheckboxToggleStyle`; the system checkbox always took the macOS accent.

## 1.4 (version 1.4, build 8), in App Review (Nov 17)

Every item on the 1.4 list in `Future Features.md` is merged (main `e4c7c02`). Version 1.4, build 8. Release notes, promotional text and the release-day steps are in `docs/release-notes-1.4.md` (What's New 3,030 characters). Sam is doing the manual pass from `Claude outputs/1.4 manual test list.md`. Upload, screenshots and submitting wait for Sam.

- Formulas opened from a file no longer show Excel's `_xlfn.` / `_xlfn._xlws.` prefixes (`=XLOOKUP(...)`, not `=_xlfn.XLOOKUP(...)`), and `_xlfn.ANCHORARRAY(G1)` reads `G1#`. Only names the save adds back are changed, so a save writes the file's text again; prefixed functions Spark Grid does not have keep their prefix. Applies to cells, shared formulas, conditional-format formulas and defined names; the last two now also get the prefixes on save, which they did not before (`ExcelFutureFunctions.unprefixed`, `FutureFunctionPrefixTests`; on branch `claude/relaxed-morse-961203`, not yet merged).
- Deleting rows or columns at the edge of a range shrinks the range (`=SUM(A2:A10)` with row 2 deleted is `=SUM(A2:A9)`). It used to become `#REF!` whenever a deleted row was the range's first or last one. A range is `#REF!` only when all of its rows (or columns) are deleted. This covers ranges on other sheets, whole-column and whole-row ranges, and named ranges (`FormulaRewriter.shiftRange`, `StructureShiftRangeTests`).
- Correct answers, part 1 (1.5). Number formats, for TEXT and for cells: a new renderer (`ExcelFormatRender.swift`) reads sections and conditions (`[>=1000]`, `[<0]`), digits spread across literals (`000-00-0000`, overflow to the first placeholder), grouping and scaling commas, `?` and `#` placeholders, scientific and engineering notation (`##0.0E+0`), fractions (`# ?/?`, `?/8`), `_` padding, doubled quotes, and dates and times in Excel's 1900 calendar (serial 1 is 1 Jan 1900, 60 is 29 Feb 1900, 0 is 0 Jan 1900; serials 1-60 showed a day early), `mmmmm`, fractional seconds and elapsed `[h]`, `[mm]`, `[ss]`. A date before 1900 or past 9999 is #VALUE! in TEXT, as is a fraction with a set denominator and no whole part whose numerator passes 32,767 (Excel keeps it in 16 bits; asked of Excel directly). Checked against Excel 16.115: TEXT of 9 inputs under 48 codes, recalculated and saved by Excel (`Fixtures/excel-text-formats.xlsx`), matches in all 480 cells (`ExcelSavedTextTests`); it had 143 differences. Two BugBash expectations recorded the old behaviour and were corrected to Excel's: `0\\;0` with 5 is `0;5`, and `[h]:mm "sec"` keeps "sec". Long chains of formulas: the calculation order searched a list for each cell, and adding a formula copied its column's index, both in time that grew with the square of the length. A 10,000-cell chain took 11.6 s to calculate and 3 s per edit in a debug build; 20,000 cells now take 0.7 s and 0.3 s (`LongChainTests`). Ranges over calculated cells read their calculated values (the same test sums the chain).
- Fast scrolling: a tile drawn in the background now fades in over the empty-grid placeholder in 0.15 s instead of popping in a frame. A window resize keeps the pre-drawn tiles, lays them out for the new size and draws the newly shown part in the background, painting only the headers on the main thread; it used to drop every tile and the tile cache, so every frame after a resize painted the cells on the main thread until the next scroll (BugBash "resize keeps scroll tiles", which fails with the old code). Both were on the Polish list in `Future Features.md`.
- Settings › General › Scroll bars (Sam, Nov 18): Show is Automatic (as System Settings › Appearance › Show scroll bars says, and follows it when it changes), Always (classic bars: on screen, wide, with tracks) or When scrolling; Length is Rows in use (the default: rows and columns in use and half a screen more) or Whole grid (every row, as before). Always bars still sit over the cells rather than taking room from them (BugBash "scroll bar settings").
- Scroll bars no longer flicker mid-window when scrolling fast (Sam, Nov 18; from 1.4, not in 1.3). Drawing a scroll tile or picture moves the grid to it and back with the drawing area set to the tile's, and each move placed the bars, against the tile's edges. The bars are now placed after the frame, and only when the scroll really changed (BugBash "scroll bars stay at the edges", which failed before the fix). They also track the sheet as other apps' do: sized to the rows and columns in use and half a screen more, or as far as the sheet has been scrolled. The whole 1,000-row grid made the thumb tiny on a short sheet, and it hardly moved.
- The print and PDF preview draws each page at the size it is shown, with the view that prints it, so text and lines stay sharp when zoomed in (Sam, Nov 18). It was a picture of the page at twice the paper size, which went soft past 100%. A page drawn at 3x checked by eye.
- The grid's overlay scroll bars can be used now (1.5, `GridScrollIndicatorView`): moving the pointer to the right or bottom edge brings the bar back, wider and with a faint track, and keeps it while the pointer is there; dragging the thumb scrolls with it; a click in the track moves 90% of a screen toward the click, or jumps to the spot when System Settings › Appearance says "Jump to the spot that's clicked" (Option does the other); the pointer is an arrow over a bar, and a click on one leaves typing alone. Clicks elsewhere are still cell clicks (BugBash "scroll bars drag and page").
- AppleScript (1.5, `SparkGrid.sdef`, `SparkGridScripting.swift`; `NSAppleScriptEnabled` and `OSAScriptingDefinition` in the Info.plist): `open`, `workbook names`, `cell value "B2"` (or `"Sales!B2"`, `reading plain`), `put value "=SUM(B2:B9)" into cell "B10"`, `save workbook`, `export workbook to POSIX file "…" format PDF|CSV` (`sheet`, `every sheet`), each with an optional `in workbook "Budget"` (the front window otherwise); errors come back in words. A file named in a script can be written from the sandbox. Checked by hand with osascript on a separately named Debug build (Nov 18): reads, writes, formulas, both exports, the three errors, save, open in the background and by name, launch with a file, and quit. Adding a dictionary hands the open-documents event to Cocoa scripting, which took Finder's opens too: `open` has its own command class that sends files where they went before (a second file opened from Finder made no window until it did). `quit` is left out of the dictionary so the system's handler keeps it; with Cocoa's `NSQuitCommand` the app did not quit.
- File ▸ Share (1.5): Mail, Messages, AirDrop and the rest send the workbook as it is when a way to share is picked, unsaved edits included, as `<name>.xlsx`; a CSV document goes as CSV; a Numbers document as .xlsx; greyed out for a new empty window (`SharedWorkbook`, `SpreadsheetDocumentStore.shareCopy`; BugBash "share sends unsaved edits"). The copy is written to the app's temporary folder; copies older than a day go at the next share. A document saved and unchanged is shared as a copy of its file rather than written again: Sam's first share of the 114,735-formula stress workbook took about 30 s to reach Messages in the Debug build, all of it spent writing the workbook. Shortcuts actions (1.5, `SparkGridShortcuts.swift`, App Intents in the app, no extension): Open Workbook (opens the file in a window; needs the file's location, which Files and Finder give); Get Cell from Workbook (`B2` on the sheet the file opens to, or `Sales!B2`; as shown or as a plain value, formulas calculated, including ones the file saved no result for); Set Cell in Workbook (as typing it, gives back the changed workbook with saved results, for Save File; a Numbers document comes back as .xlsx); Export Workbook (PDF with the pages printing makes, one sheet or every sheet; CSV of one sheet as shown). BugBash "shortcuts actions" runs each on a made-up workbook. Not tried yet: running them from the Shortcuts app itself, and whether a Shortcut that only reads a cell brings up a Spark Grid window when the app was not running.
- Script bug bash (1.5, Nov 18, `claude/1.5-bug-bash`): AppleScript drove a separately named Debug build. Typed into cells and compared with Excel 16.115's answers for the same formulas: 117 scalar formulas, 7 spills (29 cells) and 432 TEXT formulas all match. Edits on a test sheet and on the stress workbook found four bugs, now fixed (docs/BUGS.md): an edit on another sheet straight after one on Config lost Config's reach to the Dashboard and Orders; a formula typed after opening, reading another sheet that reads its own sheet back, never updated; readers of a spill (`SUM(C1#)`) kept the old answer when the spill changed; TEXTJOIN and SUMPRODUCT read one value of a typed list or spilling result. Odd input held up: leading zeros, an unclosed formula (#ERROR!), the last cell XFD1048576, emoji and quotes. Seen, not fixed: a spill's first cell is blank for a moment after an edit, and edits on the stress workbook take minutes to settle in the Debug build (not yet timed in Release).
- OFFSET, LOOKUP and YEARFRAC (1.5, `FormulaEvaluator+References`). OFFSET gives a reference that works wherever a range does, and like INDIRECT watches every cell, so any edit updates it. LOOKUP uses Excel's sorted search in its vector and array forms, so `LOOKUP(2,1/(B1:B8>40),D1:D8)` finds the last row that holds. YEARFRAC has all five bases, including Excel's month-end order for US 30/360 and its average year for actual/actual over several years. 97 formulas match answers typed into Excel 16.115 by script (`ExcelEdgeCaseTests`). The Excel edge-case batches now stand at 171/176 and 114/126; what is left is in docs/gaps.md.
- Ranges spill (1.5, `RangeSpillTests`): typed on its own in a cell, a range (`=A1:A3`), arithmetic on one (`=B1:B8*10`), a one-value function given one (`=LEN(D1:D8)`, `=IF(B1:B8>25,"big","small")`) and ROW or COLUMN of one spill a value for each cell, as in Excel 16.115 (56 cells typed into both by script match). A formula a file saved the pre-spill way (no array mark) that reads a range opens marked `Cell.opensAsOneValue` and does not spill, as other apps read such files; typing it again clears the mark. Saved, these spills open as spills, and a blocked one is saved as a one-cell array formula. Looking for spilling formulas after each edit read every formula through `uppercased()` and thirty name searches: 2.3 s for the stress workbook's Orders sheet in Release on every edit. One pass over each formula's bytes takes 0.063 s for all sixteen sheets (`SpillLayout.spillHint`).
- A formula whose answer is an empty cell (1.5): `=A3` with A3 empty, an IF or lookup that picks an empty cell, and an empty cell inside a spill (FILTER, SORT) give 0, as in Excel 16.115; formulas reading them see 0 (`ISBLANK` is FALSE). An empty string chosen on purpose (`IF(…,"",…)`) stays empty. Every result the engine keeps goes through `storeValue`; the background update and other-sheet reads use `FormulaEvaluator.cellResult` (`CrossSheetSequenceTests`).
- Approximate lookups (1.5, `sortedSearch`): MATCH with 1 or left out, VLOOKUP and HLOOKUP with TRUE or left out search as Excel does, a binary search over values of the needle's kind (numbers, text or TRUE/FALSE; blanks and errors passed over). Sorted data gives the same answers as before; `MATCH(9.99E+307,B:B)` now finds the last number, `MATCH("zzz",D:D)` the last text, `MATCH(2,1/(B1:B8>40))` the last row that holds, and text needles work (they found nothing). MATCH with -1 reads from the top as Excel does. Text compares in Excel's order everywhere a comparison is made: punctuation, then digits, then letters, accents beside their letters. 37 lookups match answers typed into Excel 16.115 by script (`ExcelEdgeCaseTests`).
- INDIRECT and ADDRESS (1.5, `FormulaEvaluator+Indirect`). INDIRECT reads `"B2"`, `"B1:B3"`, `"Sheet2!A1"`, `"'My Sheet'!A:A"`, a defined name, or with FALSE `"R2C2"` and `"R[1]C[-1]"` counted from its cell; it works wherever a range does (SUM, COUNTIF, VLOOKUP, INDEX, MATCH, ROWS, SUMPRODUCT(LEN(…))). Its target is known only when it runs, so it watches every cell of every sheet: any edit updates it, as other apps recalculate it on every change (`CrossSheetSequenceTests`). ADDRESS gives `$C$2` to `C2` and `R2C3` to `R[2]C[3]`, with the sheet quoted as other apps quote it. 36 formulas match answers typed into Excel 16.115 by script (`ExcelEdgeCaseTests`); checked live in the app by script as well.
- Array maths (1.5, `liftedFunctionNames`): a function that takes one value in each argument (IF, LEN, LEFT, ROUND, ISNUMBER, SEARCH, YEAR and 75 more) given a range or a list works value by value inside anything that reads arrays: `SUM(LEN(A1:A8))`, `MAX(IF(B1:B8<50,B1:B8))`, `SUMPRODUCT((LEFT(D1:D8,1)="a")*B1:B8)`, `FILTER(D1:D8,ISNUMBER(SEARCH("a",D1:D8)))`, `TEXTJOIN(",",TRUE,UPPER(D1:D3))`. ROW and COLUMN of a range give their numbers there. 44 such formulas typed into Excel 16.115 and Spark Grid by script all match (`ExcelEdgeCaseTests`); before, they were #VALUE!.
- Edge-case formulas against Excel 16.115 (1.5, Nov 18, `ExcelEdgeCaseTests`): 176 formulas on mixed types, blanks, errors, rounding, text, dates, wildcards and lookups, typed into both by script; 166 match (148 before the fixes in docs/BUGS.md). SUM, AVERAGE, COUNT, MIN and MAX skip TRUE, FALSE and text in ranges and read them when typed into the call; comparisons order numbers, text, then TRUE/FALSE, and numbers equal to 15 digits are equal; odd roots of negatives work and overflow is #NUM!; YEAR, MONTH and DAY follow the 1900 calendar; exact lookups take wildcards and never match an empty cell; XLOOKUP reads its search direction. The rest: docs/gaps.md item 3.
- Typed numbers and times (1.5, `TypedEntry`): `1,234` and `1,234.5` are numbers shown with grouping, `$1,234.50` and `$1234` currency, `(5)` and `($1,234.50)` negative, `10:30`, `10:30:15`, `9:05 am`, `10:30 PM` times and `25:00` 25 hours, each with the value and format code Excel 16.115 gives the same typing (`TypedEntryTests`). A time edits as typed. Commas count only between groups of three, so `1,23` and `12,34,567` are text, everywhere a number is read from text. Still different from Excel: docs/gaps.md item 2.
- Typed lists in formulas (1.5): `{1,2,3}` is a row, `{1;2;3}` a column, `{1,2;3,4}` a grid, of numbers, text, TRUE/FALSE or errors. On its own a list spills; functions read it as an array (`SUM({1,2,3})`, `CHOOSECOLS(A1:D9,{1,3})`, `TEXTSPLIT(A1,{",",";"})`, `MATCH("c",{"a","b","c"},0)`). MATCH, VLOOKUP and the other lookups now also read a spilling result as their list. Rows of different lengths, references and formulas inside a list do not parse, as in other apps.
- Functions batch 3 (1.5, `FormulaEvaluator+Batch3`), 68: trigonometry (SIN through ATANH, ATAN2, DEGREES, RADIANS, SQRTPI), COMBIN, PERMUT, QUOTIENT, RAND, RANDBETWEEN; AVERAGEA, MAXA, MINA, STDEVA, STDEVPA, VARA, VARPA, GEOMEAN, HARMEAN, DEVSQ, AVEDEV, SKEW, SKEW.P, KURT, TRIMMEAN, STANDARDIZE, FISHER, FISHERINV, COVARIANCE.S/.P, COVAR, PEARSON, RSQ, RANK.AVG, PERCENTRANK(.INC/.EXC); NORM.DIST, NORM.S.DIST, NORM.INV, NORM.S.INV and their old names; REPLACE, FIXED, DOLLAR, T, NUMBERVALUE; TIME, TIMEVALUE, DATEVALUE, DAYS360; N, ISNONTEXT, TYPE, ERROR.TYPE; SLN, SYD, DDB, DB, EFFECT, NOMINAL, ISPMT, CUMIPMT, CUMPRINC, MIRR; and TRANSPOSE, which spills. Checked against Excel 16.115: a Spark Grid file with all of them and typed lists, recalculated and saved by Excel (`Fixtures/excel-functions-batch3.xlsx`, saved path and author replaced), matches Spark Grid in all 146 cells (`ExcelSavedBatch3Tests`). That check found MATCH could not look through a typed list and TYPE of a several-cell range is 16, not 64. SUBTOTAL is left out: it must skip other SUBTOTALs in its range, and the calculation sees values, not formulas.
- New functions (1.5): LET, TEXTSPLIT, VSTACK, HSTACK, TAKE, DROP, CHOOSECOLS, CHOOSEROWS, WRAPROWS, WRAPCOLS, TOCOL, TOROW and RANDARRAY (`FormulaEvaluator+Shape`). All but LET spill; LET spills when what it works out does. LET puts each value in place of its name before calculating; a value that is one plain value (not a reference, not an array) is worked out once. Names are compared without regard to case, and an inner LET hides an outer name of the same spelling. Saving writes `_xlfn.` before each function and `_xlpm.` before each LET name and its uses inside that LET, as Excel stores them; opening reads both. Checked against Excel 16.115: a Spark Grid file with all of them opened in Excel with no `#NAME?`, Excel recalculated and saved it (`Fixtures/excel-array-shapes.xlsx`, saved path and author name replaced), every one of its 91 cells matches Spark Grid recalculated, and all 16 spills open as spills (`ExcelSavedShapesTests`; hand-worked cases in `ArrayShapeTests`). That check found TAKE of zero rows is `#VALUE!` in Excel, not `#CALC!`. Typed in, they spill, a LET recalculates when a cell it reads changes, and RANDARRAY draws new numbers after any edit, as in Excel, and keeps them while nothing is edited (BugBash "new array functions when typed"). Array constants such as `{1,2}` still do not parse, so a list of TEXTSPLIT delimiters comes from a range.
- Saved spills now open in Excel without a repair prompt (checked in Excel 16.115 on Nov 12). Two things made Excel call the file damaged and drop formulas: a blocked spill's `#SPILL!` saved as an error value (only the ECMA-376 error codes may be; `#SPILL!` and `#CALC!` are now saved as text), and a `G1#` reference saved as typed (now `_xlfn.ANCHORARRAY(G1)`). A formula that can spill but fills one cell, or is blocked, is now saved as a one-cell dynamic array as Excel saves it, and `xl/metadata.xml` is written whenever any formula is (`SpillFileTests`). In licensed Excel all 38 spilled values matched Spark Grid's. Excel saved the same file back (`Fixtures/excel-dynamic-arrays.xlsx`, saved path and author name replaced) in the same form, except that Excel stores a blocked spill as `#VALUE!` plus a rich-value part saying `#SPILL!`; Spark Grid opens it with every spill as a spill and, recalculated, gets Excel's values and the blocked spill (`ExcelSavedSpillTests`).
- Spill references: `C1#` is every cell C1's results spill into, and `_xlfn.ANCHORARRAY(C1)` from a saved file reads the same. It is a range taken from the spill's current size, so COUNTIF, INDEX and the rest read it; `#REF!` when nothing spills from C1 or its spill is blocked; `=C1#*2` spills itself; it is shown and saved back as `C1#`. Formulas reading it are recalculated by the background update, not on the edit itself: recalculated on the edit, they read C1's old results and the background update kept them. Two engine fixes came with it: a background update that replaces one not yet applied now carries that one's cells (laying out a spill makes two updates in a row, and the first one's formulas kept old results; two quick edits did the same), and a spilling formula about to recalculate drops the range snapshots over its cell. Also `#N/A` and `#DIV/0!` typed in a formula now parse (`/` ended the error name). The Excel fixture's `ROWS(G1#)` gives Excel's 3 (`SpillReferenceTests`, `ExcelSavedSpillTests`, BugBash "spill references follow the spill").

- Checked the other 1.4 file features in Excel 16.115 (Nov 13): a file made with Spark Grid's own commands (two pivot tables, a pivot chart, GETPIVOTDATA, print area, page breaks, row and column groups, links, a protected sheet) opens with no repair prompt; Excel keeps the print area, breaks, groups, links and the protection (password `spark` and its allowances), and the pivot values match. One bug fixed: grouped columns opened zero wide (hidden) in Excel, because a `<col>` without a width reads as width 0; every `<col>` now carries a width, and the default one is not kept as a set width on open. Excel's save is `Fixtures/excel-1.4-features.xlsx` (`ExcelSavedFeaturesTests`). Spark Grid's pivot tables are now also saved as real pivot tables (next entry).

- Size limit on opening files (Sam agreed Nov 13): 2 GB unpacked in all, and no part over 200 MB. Bytes are counted as they unpack, not taken from the sizes the file declares, so a small file that unpacks to far more stops early with "This workbook is too large to open…" instead of filling memory (`ZipPackage.Limits`, `ZipLimitTests`). The other two places that unpack parts use the same per-part cap.

- Sam's 1.3 reports (Nov 13): (1) typing over a value showed the new letter over the old word (the typed letter drawn over a predicted word) while typing. The cell editor had macOS inline word predictions on, drawn a few points off the typed letters; predictions and automatic completion are now off in the cell editor and formula bar (`EditorSpellCheck`). (2) Coloring filtered rows also colored the rows the filter hid; formatting now skips filter-hidden rows, as Delete already did (`applyFormat`). Both in BugBash ("typing over a value hides the old text", "fill skips filtered rows"; each fails without its fix). Open: a fill that shows two shades split partway through a row, not yet reproduced (needs Sam's steps).

- Print setup has a "Row and column headings" switch (Sam, Nov 13), on by default as before. Off, the printout leaves out the column letters and row numbers and pages reserve no room for them, so more rows fit. Like Gridlines it is chosen at print time, not saved in the file (BugBash "print without headings").

- Spark Grid's pivot tables save as real pivot tables (Sam, Nov 13): a pivot cache over the source cells (shared items for row, column and filter fields, in Spark Grid's order; `refreshOnLoad`) and a pivot table definition at the drawn table (rows, columns, filters with hidden items, sum/count/average/min/max value fields named as Spark Grid names them), marked with the Spark Grid pivot's id (`ExcelPivotWriter`). In Excel 16.115 they open with no repair prompt and Excel rebuilds them on open: the tables match, a filter shows with its hidden item, and `GETPIVOTDATA` gives Spark Grid's answer (it waits while Excel's window is hidden). Spark Grid drops the parts it wrote when it reopens its own file and writes them again on save; a save from Excel drops Spark Grid's settings and the tables open as Excel's (`Fixtures/excel-pivots.xlsx`, `ExcelPivotWriterTests`). Not written yet: pivots that group dates (they stay values), and a pivot that redraws a file's table keeps that table.

- Sam's manual test (Nov 13): (1) ⌘Z undid Protect Sheet, so protection came off with no password. Protecting and unprotecting now empty Undo and Redo once the command's event ends, as other apps do (BugBash "undo cannot unprotect"). (2) Row and column deletes lagged on big sheets: every formula on the changed sheet was parsed to shift it, 0.68 s in Release for one row of the stress workbook's Orders sheet (105,000 formulas). References are now moved in the formula's bytes (`FormulaRewriter.fastShiftForStructure`), falling back to the parser for anything it does not handle; 0.43 s, the rest is copying and moving the sheet's cells. A formula with nothing to move keeps its text as written. `FastShiftDifferentialTests` checks it against the parser (0 differences over 864,000 stress-workbook cases). (3) Arrow, Return and Tab lag in a half-screen window (stress workbook, half of the laptop screen): the toolbar's ViewThatFits measured up to five whole toolbars again on every selection change once the first did not fit, creating new font-size fields each time; 3.3 s of window layout in 10 s of arrow presses in Release. The toolbar now measures each variant's width once, hidden, and shows the widest that fits; 0.37 s in the same test, and full width still shows the captioned toolbar.

- Protected ranges, both kinds (Sam, Nov 13). Allow Edit Ranges (Sheet > Allow Edit Ranges…): ranges a protected sheet still lets people edit, each with an optional password, opened for the session with Sheet > Unlock Edit Range…; set up only while the sheet is unprotected, as in other apps; saved as `<protectedRanges>` (Excel 16.115 opened one and kept both ranges and the password; Spark Grid used to drop them from other apps' files). Range locks (Sheet > Lock Range… / Remove Range Lock…): a range locked on its own, protected sheet or not, with an optional password; typing, formatting, clearing, sorting and deleting rows or columns through it are refused, inserting moves it; saved in `xl/sparkGrid/locksN.json`, so other apps open those cells unlocked. Locking empties Undo, as protecting does. Both move with inserted and deleted rows and columns (`RangeProtectionFileTests`, BugBash "range locks and editable ranges").

- Printing a range that starts below the frozen rows (or right of the frozen columns), such as a selection or print area further down, printed no header at all. The range now reaches back to take in the frozen rows and columns, with those between left off the page, so the header heads page 1 and repeats on the rest, as other apps print titles (BugBash "frozen titles repeat for a later range"). Sam's report of half rows and no repeated header (Nov 14) matched the 1.3 build: printed to PDF through the same print operation, 1.4 breaks Orders' 268 pages between rows and repeats its header on each.

## 1.3 (version 1.3, build 7), not yet submitted

1.2 (build 6) is in App Review. 1.3 is on `claude/1.3` (Spark-Grid#79, SparkGrid#3). Release notes are in `docs/release-notes-1.3.md`; `docs/BUGS.md` lists the fixes.

- Charts from files (`ForeignChart`) are read by `ImportedChartReader` and drawn by `ImportedChartView`, live from their cells. Move, resize, duplicate, reorder and delete edit the kept anchor (`DrawingAnchorXML`); Edit Chart rewrites the kept chart part with `ImportedChartWriter` (XMLDocument), changing only what was edited.
- Saving numbers every object in a drawing, and the drawing part is valid XML again (`</xdr:xfrm>`; since Oct 15 it closed with `</a:xfrm>`).
- Highlight styles write both `fgColor` and `bgColor` for a solid fill.
- Duplicates (`SpreadsheetViewModel+Duplicates`), tables (`SpreadsheetViewModel+Tables`, `SheetTable+Style`), tab colors (`SheetFileExtras+TabColor`), icon thresholds, selection stats and AutoSum, and tabbed Settings.
- Row insert: formulas on other sheets that don't name the changed sheet are skipped by a byte scan, and the rest are shifted in parallel.
- Checked: an edited stress workbook opens in Excel with no repair prompt and imports into Numbers; a table from the app's template opens in Excel as a styled table.
- Still to check by hand: Remove Duplicates, Undo, save; a changed shortcut after a relaunch. Still to make: App Store screenshots and a preview video.

1.1.1 shipped on 2026-10-29. 1.2 follows `Future Features.md`: compatibility first. The bug bash (PR #77) is merged; `docs/BUGS.md` lists what is open. Release notes are in `docs/release-notes-1.2.md`.

- A save keeps what the file had: hidden rows, columns and sheets, grouped rows and columns, tab color, sheet protection, page setup and headers, dropdown rules, comments, links, tables, charts the app does not draw, and pivot tables. These live in `Sheet.fileExtras` and `Workbook.pivotCaches` and move with inserted, deleted and sorted rows. The Oct 29 audit workbook keeps every item, and a saved copy opens in Excel with no repair prompt.
- Hidden rows and columns are hidden in the grid. Hide and Unhide are on the header menus and the Sheet menu; hidden sheets leave the tab bar and come back from the tab menu.
- Dropdown lists show a button and a menu (Option-Down opens it). Comments show a corner mark and a tooltip. Links have Open Link.
- The fill handle continues numbers, dates, numbered text, and month and day names; Option-drag copies.
- Tables: a column inserted inside a table joins its column list (named Column1, Column2, and so on, written into the header row) and a deleted one leaves it; filter columns follow. Kept charts declare each namespace once; a file saved by the first 1.2 build with namespaces declared twice is cleaned on the next save. Excel opened the stress workbook with both table edits and no repair prompt. A formula whose reference becomes #REF! after a delete drops its saved result, so the file asks to be calculated on open. Highlight rules of the kind "cell value equals some text" were read as `=A1="""text"""`, which pointed at the wrong cell and never matched, in the grid or after a save; they now read as `=N2="text"` for the rule's first cell.
- Large format changes (alternating row colors, fill, bold, borders on thousands of cells) are one pass over one sheet copy with one undo step. Alternating colors on the stress workbook's Orders sheet (15,000 rows) used to copy the sheet once per row and register an undo per cell; it now applies in about a second in a Debug build, and Undo and Redo are one step each.
- Every visible cell with a dropdown list shows a faint chevron; the selected one shows the full button.
- Release timings, 1.1.1 (`6465903`) vs 1.2 (`4478523`), this Mac, best of three: KPI open 0.39 vs 0.39 s, slowest first screen 0.036 vs 0.035 s, edit to pixels 0.003 vs 0.003 s, export 0.18 vs 0.185 s, worst scroll 0.026 vs 0.019 s. 50,000-row ledger: open 2.75 vs 2.70 s, export 0.45 vs 0.43 s, memory 1682 vs 1754 MB. The benchmark's own answer check flags every formula on both builds alike; `spark-grid-cli check` is the answer check that counts (0 mismatches).
- Functions batch 1: 37 functions and the `#NUM!` error (`FormulaEvaluator+Batch1.swift`, `evalExtremeIFS` for MAXIFS and MINIFS).
- `data.sort` takes `then` levels. Sort, Format Cells, Conditional Formatting, Insert Chart and Print use the shared `SparkDialog` layout.
- Import of the KPI file: debug `testFullWorkbookImportWallClock` 2.80 s on this branch, 2.77 s on `main` (row attributes are read in one pass).

## Phase

Phase D and Phase E are done. A file saved after an edit stores a result on every formula. Reopening that file shows those results and does not recalculate. On the KPI file, Release export is 0.159 s and the saved file is 1,199,509 bytes. Full recalculation orders sheets from the dependency graph. The name-based sheet rank and the legacy strip planners are gone. The rules grep over `Packages/SparkGridCore/Sources`, `Spark Grid/State`, and `Spark Grid/Grid` prints nothing. Paint, shuffled, edits, and full recalculation are at 0 mismatches except `YTD Summary!R5`. Ledger ground truth: 1,646 formulas, 0 mismatches.

## Next task

Stop. Do not start another phase from this status alone.

## Open to the first grid (2026-10-22)

Release, this Mac, the KPI reference file. The clock stops when the opened sheet has been painted. The other sheets finish after that. Before is `bdac6a2`. After is this change. The first scroll is one viewport on the opened sheet. 48,191 formulas, all cached.

| Path | Before | After |
|---|---|---|
| Open to the first painted grid | 0.576 s | 0.256 s |
| First scroll of the opened sheet | 0.017 s | 0.017 s |
| First switch to the heavy sheet | 0.025 s | 0.028 s |
| First scroll of that sheet | 0.023 s | 0.024 s |

The opened sheet is drawn from the values stored in the file. Shared formulas on the other sheets are expanded after that paint. The tiles that cover the first screen are rasterized before the scroll. Rows that were not on that screen are not. A scroll onto those rows still paints cells, and that scroll did not get slower.

The workbook is imported in full before the first paint. Stored formula results are what the grid draws, so open does not recalculate. Tiles for the screen already in view are rastered from that sheet's own column and row offsets.

A file saved without formula results used to calculate those formulas inside the first grid draw, on the main thread, so a click was not accepted until the draw returned. Debug File → Open of that file, from the start of load until the first grid draw returned: 2.2 s (import 2.0 s, draw 0.03 s). The uncached formulas are calculated after that draw, off the main thread. Column letters are drawn from the sheet's widths. The column-header tile placeholder, one 512 pt tile at the default column width, is not shown over them.

## Last gate result

2026-10-16, after W8. `scripts/ci.sh` printed `PASS (215.3s)`. Lint, format, package, xcodebuild, layers, privacy-assets, ledger, and fuzz passed. KPI skipped because `SPARK_GRID_CORPUS` was unset. That skip is not a local pass anymore. `scripts/ci.sh` sets `SPARK_GRID_CORPUS` when the manifest file is in `~/Downloads` or `~/SparkGridCorpus`, and a skipped KPI stage fails the local gate. Hosted CI still skips KPI. Ledger ground truth the same day: 1646 formulas, 0 mismatches. Fuzz smoke: seed 1, 20 steps, pass.

The real KPI baseline is the display path, not full recalculation. On 2026-10-16, against the original saved results with caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 9,915 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 32,833 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 9,915 | 1 |
| Full recalculation | 367 | 1 |

Paint order differs in 9,916 formulas. That count is the 9,915 mismatches plus the one exempt cell, `YTD Summary!R5`. Record 9,916 as the baseline. The check still fails until every path is 0 mismatches except that cell. Do not weaken it. An earlier unseeded random walk differed in 32,571; the gate uses seed 1. Full recalculation differed in 368, which is 367 plus the exempt cell. The scalar check on `2958120` was 11,894 mismatches and is not ground truth.

Range reads now calculate formula cells in the range before the range is assembled. Same day, Release, same machine, caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 896 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 2,118 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 896 | 1 |
| Full recalculation | 367 | 1 |

Full recalculation was unchanged at 367 plus the exempt cell. Paint order and the edit path dropped from 9,915. The shuffled path dropped from 32,833.

`TEXT` now uses `ExcelFormatCode` for date, time, and number codes. Same day, Release, caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 531 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 1,753 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 531 | 1 |
| Full recalculation | 2 | 1 |

The 365 `TEXT` formulas that were wrong on every path now match. The check still fails until every path is 0 mismatches except `YTD Summary!R5`.

Unqualified ranges are cached on the sheet that owns the formula. A summary that adds two sheets' `COUNTIF` results no longer reuses the first sheet's column. Same day, Release package test, caches cleared, 48,191 formulas. Release timings were not re-run for this commit.

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 2 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 1,224 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 2 | 1 |
| Full recalculation | 2 | 1 |

Paint, edits, and full recalculation miss `YTD Summary!R62` and `YTD Summary!R63`. The shuffled path still misses 1,224.

A cached aggregate range is now dropped when a cell inside it is calculated later. `testDayWindowCountsMatchWhenTheRowTotalIsVisitedFirst` passed. The four paths above were not re-run. Release timings were not re-run.

`AVERAGE` and `AVERAGEIFS` return an error that sits in the averaged cells. `IFERROR` then shows its fallback. Same day, Release package test, caches cleared, 48,191 formulas. Release timings were not re-run.

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 0 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 1,222 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 0 | 1 |
| Full recalculation | 0 | 1 |

Paint, edits, and full recalculation match except `YTD Summary!R5`. The shuffled path dropped from 1,224 to 1,222.

`eval()` restores the outer origin, and `calculateWithPrecedents` calculates a same-sheet precedent. Same day, Release package test, caches cleared, 48,191 formulas. Ledger ground truth the same day: 1,646 formulas, 0 mismatches.

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 0 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 0 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 0 | 1 |
| Full recalculation | 0 | 1 |

Phase C does not change calculation. The same Release check, run again at the end of Phase C on 2026-10-20, is still 0 mismatches on all four paths except the one exempt cell. Ledger ground truth was not re-run: Phase B measured 1,646 formulas and 0 mismatches, and this phase does not touch Calc or Engine.

Phase E removes the name rank and the legacy strip planners. Same day, Release `spark-grid-cli check`, caches cleared, 48,191 formulas:

| Path | Mismatches | Exempt |
|---|---|---|
| `sheetDisplayValue`, paint order | 0 | 1 |
| `sheetDisplayValue`, shuffled, seed 1 | 0 | 1 |
| `sheetDisplayValue` after edits and cross-sheet catch-up | 0 | 1 |
| Full recalculation | 0 | 1 |

Open, edit, scroll, and save were not re-timed. Those paths do not call the removed planners.

## Latest Release numbers

Date: 2026-10-21. Binary: Release build on `cursor/phase-d-save-c95e`. Machine: this Mac. Edit to pixels starts at `commitEdit` and stops when that display pass returns. The painted count is cells drawn in that pass. The benchmark loads a copy of the workbook.

Phase D does not change the grid. The 120 Hz fling below is the Phase C measurement and was not re-run. Scroll frames are a scripted trackpad fling at 120 Hz in a 1280×800 window, 252 frames. Fill is the slowest tile from the moment it enters the clip until its bitmap is installed.

| Sheet | p50 | p95 | max | dropped | over 16 ms | fill |
|---|---|---|---|---|---|---|
| June | 1.289 ms | 2.099 ms | 2.601 ms | 0 | 0 | 0.003 ms |
| YTD Summary | 1.662 ms | 2.583 ms | 3.583 ms | 0 | 0 | 0.002 ms |
| Ledger | 0.867 ms | 1.461 ms | 2.470 ms | 0 | 0 | 0.003 ms |

Before the tile change, the same fling was June p95 43.894 ms (1,100 dropped, 252 frames over 16 ms), YTD Summary p95 29.012 ms (537 dropped, 252 over 16 ms), Ledger p95 48.380 ms (107 dropped, 21 over 16 ms).

On 2026-10-21, before Phase D, the same machine measured export at 2.243 s (KPI) and 0.836 s (ledger). A save after an edit wrote no formula caches, so reopening calculated. The KPI edit-save was 13,968,826 bytes. The ledger edit-save was 18,120,889 bytes.

KPI reference file, after Phase D:

| Path | Release |
|---|---|
| Import | 0.367 s |
| Fingerprint | 3.762 s |
| Export | 0.159 s |
| Autosave on the main thread | 0.000 s |
| Autosave in the background | 0.187 s |
| Open | 0.585 s |
| Unsaved-changes check | 0.000 s |
| Slowest first screen | 0.032 s (YTD Summary) |
| Tab switch | 0.000 s |
| One edit commit | 0.003 s (January) |
| Edit to pixels | 0.003 s, 1 cell painted |
| Save on the main thread | 0.000 s |
| Save in the background | 0.572 s |
| Saved file after an edit | 1,199,509 bytes, 48,191 of 48,191 formulas cached |
| Reopen display, no recalculation | 0.074 s, 1 mismatch (the exempt cell) |
| Worst scroll screen | 0.025 s (Config, 17 ticks) |
| Dependency-graph builds on that edit and the following save | 0 |
| Resident memory | ~305 MB |

Synthetic ledger, after Phase D:

| Path | Release |
|---|---|
| Import | 0.518 s |
| Fingerprint | 0.419 s |
| Export | 0.437 s |
| Autosave on the main thread | 0.000 s |
| Autosave in the background | 73.055 s (the file has no caches, so the save calculates them) |
| Open | 3.497 s |
| Slowest first screen | 1.102 s (IndexMatch) |
| Tab switch | 0.000 s |
| One edit commit | 0.001 s (VLOOKUP) |
| Edit to pixels | 0.001 s, 1 cell painted |
| Save on the main thread | 0.000 s |
| Save in the background | 72.490 s |
| Saved file after an edit | 1,863,568 bytes, 1,646 of 1,646 formulas cached |
| Reopen display, no recalculation | 0.040 s |
| Worst scroll screen | 0.611 s (Ledger, 7 ticks) |
| Dependency-graph builds on that edit and the following save | 0 |
| Resident memory | ~2462 MB |

The original KPI file is 1,119,816 bytes. A Spark Grid save of it is 1,199,509 bytes.

Previous Release run, 2026-10-20, on `cursor/phase-b-edit-pixels-c95e`: KPI import 0.334 s, fingerprint 3.897 s, export 2.249 s, open 0.552 s, slowest first screen 0.062 s (July), June scroll worst 0.017 s (13 ticks), tab 0.000 s, edit to pixels 0.005 s (1 cell) and 0.002 s on YTD Summary (1 cell). Ledger import 0.535 s, fingerprint 0.444 s, export 0.886 s, open 3.596 s, slowest first screen 1.116 s (IndexMatch), scroll worst 0.598 s (7 ticks), edit to pixels 0.150 s (1 cell).

Previous Release run, 2026-10-16, on `cursor/workflow-gates`: KPI import 0.369 s, fingerprint 3.808 s, export 2.226 s, open 0.669 s, slowest first screen 0.056 s (May), June scroll worst 0.127 s (13 ticks), tab 0.000 s, edit to pixels 0.046 s (1452 cells). Ledger import 0.532 s, fingerprint 0.423 s, export 0.832 s, open 3.783 s, slowest first screen 1.124 s (IndexMatch), scroll worst 0.684 s (7 ticks), edit to pixels 3.510 s (92 cells). Older baseline (2026-10-11) is in `.cursor/rules/performance.mdc`. Use the table above when a commit needs before/after numbers, and replace it when a new Release run finishes.
