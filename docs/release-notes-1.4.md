# Spark Grid 1.4 release notes

Drafts for App Store Connect. Review before pasting. Text for the App Store must not name other companies' products.

## What's New in This Version

New
• The toolbar has Sort, AutoSum (Sum, Average, Count, Max and Min), Highlight, Chart and Table. Alignment, wrapping and rotation share one Layout menu, and the font size has arrows.
• Paste Special: paste values only, formats only, or transposed. Paste Values is Option-Shift-Command-V. A paste of cells copied in Spark Grid brings their formats too.
• Format Painter: pick up a cell's look with the brush in the toolbar, then select the cells to give it to. Escape puts it away.
• Fill Down (Command-D) and Fill Right (Command-R) copy the top row or left column across the selection.
• Option-drag the fill handle to count up from one number: 1 becomes 1, 2, 3, 4. Option-drag a series such as 1, 2 to copy it instead.
• 66 more functions, among them PMT, IPMT, FV, PV, RATE, NPV, IRR, XIRR, NETWORKDAYS, WORKDAY, DATEDIF, WEEKNUM, STDEV, VAR, PERCENTILE, QUARTILE, CORREL, FORECAST, MROUND, SWITCH, CHOOSE, TEXTBEFORE and TEXTAFTER. Insert Function has a Financial group.
• FILTER, SORT, SORTBY and UNIQUE. Their results fill the cells below and beside the formula and update as the data changes. If something is typed in the way, the formula shows #SPILL! until the cells are clear. SEQUENCE spills too. Put # after the formula's cell, as in =SUM(C1#), to use all of its results, however many there are.
• Data > Text to Columns splits one column at commas, tabs, semicolons, spaces or a character you choose, with a preview. Text in quotes stays together. Fixed width splits lined-up text at chosen character positions, and suggests them.
• Group rows or columns (Shift-Command-K) and fold them with the + and − beside the row numbers and column letters. Ungroup is Shift-Command-J. Sheet > Show Row Levels and Show Column Levels fold to a chosen depth. Groups from other apps' files show and fold too.
• Sheet > Protect Sheet, with an optional password, stops changes to locked cells, rows, columns and formatting. Format > Locked chooses which cells stay open for typing, and the Protect Sheet window can still allow formatting, inserting or deleting rows and columns, links and sorting. Protected sheets from other apps' files keep their password and what they allow.
• File > Print Area sets the cells to print. Sheet > Insert Page Break starts a new page above the selected row or left of the selected column, shown as a dashed line. Both save with the workbook.
• File > Export as PDF saves the same pages printing makes, with text you can search and copy. The Print window has a Save as PDF button too. Printing every sheet now gives each sheet its own pages.
• Insert > Link (Command-K) adds a web or email link, or a link to a sheet, cell or named range. Command-click a link to follow it; links made with the HYPERLINK function work too. Right-click a cell to edit or remove its link. In dark mode links show in a lighter blue.
• Data > PivotTable summarizes a range on a new sheet: choose fields for rows, columns, values (sum, count, average, min, max) and filters. Date fields group by year, quarter, month or day. Data > PivotChart charts a pivot table, and the chart follows the table when it grows or shrinks. GETPIVOTDATA reads a value from a pivot table and updates when it is refreshed. Refresh also recalculates pivot tables made in other apps, keeping their hidden items and filters. Data > Refresh PivotTable updates it after the data changes. Pivot tables save with the workbook as pivot tables other apps can refresh, and GETPIVOTDATA formulas work there too. Pivot tables that group dates open there as a plain table.
• Edit > Clear removes contents, formats, or both.
• In a narrow window the toolbar stays on one row: names under the buttons hide first, then the last groups fold into a » menu.

Fixed
• Cells you had just typed no longer go blank when you scroll with the trackpad.
• Workbooks saved with newer functions such as XLOOKUP, IFS or TEXTJOIN open in other spreadsheet apps without #NAME?.
• Comparing text in a formula ignores upper and lower case, as other spreadsheet apps do: "east" = "East" is TRUE.
• Results such as 186,000 × 70% show as 130200, not 130199.99999999999.
• Undoing a sort puts every formula back as it was. Before, a total row sorted into the table could come back as #REF!.
• Workbooks with cells set to clip their text open in other spreadsheet apps without a repair message.
• Print setup can leave out the column letters and row numbers.
• Printed pages end between rows and columns instead of cutting a row in half. Repeat frozen rows and columns now repeat on every page, and hidden rows and columns stay off the page.
• Print areas from other apps' files open on the right sheet, and each sheet keeps its own.
• Sort A to Z and Z to A leave a total row under the table where it is.
• Choices and the Settings tabs follow the accent color you pick in Settings.
