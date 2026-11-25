import SwiftUI

/// Help › Spark Grid Help: a short guide that works offline. Help used to be empty (a Reddit
/// note, Nov 19).
struct HelpView: View {
  @State private var topic: HelpTopic = .gettingAround
  @State private var search = ""
  @Bindable private var settings = AppSettings.shared

  /// Topics whose title or text holds the search, or all of them.
  private var topics: [HelpTopic] {
    let query = search.trimmingCharacters(in: .whitespaces).lowercased()
    guard !query.isEmpty else { return HelpTopic.allCases }
    return HelpTopic.allCases.filter { item in
      item.title.lowercased().contains(query)
        || item.paragraphs.contains { $0.lowercased().contains(query) }
    }
  }

  // Drawn in the app's own style, as Settings is, not a system sidebar (Sam, Nov 20).
  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Rectangle().fill(SparkStyle.chromeDivider).frame(width: 1)
      detail
    }
    .frame(minWidth: 720, minHeight: 480)
    .background(SparkStyle.window)
    .preferredColorScheme(settings.appearanceMode.colorScheme)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Search help", text: $search)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          if let first = topics.first { topic = first }
        }
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(topics) { item in
            let selected = item == topic
            Button {
              topic = item
            } label: {
              HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                  .frame(width: 18)
                  .foregroundStyle(selected ? SparkStyle.accent : SparkStyle.secondaryLabel)
                Text(item.title)
                  .font(.system(size: 13, weight: selected ? .semibold : .regular))
                  .foregroundStyle(SparkStyle.label)
                Spacer(minLength: 0)
              }
              .padding(.horizontal, 8)
              .padding(.vertical, 6)
              .background(
                RoundedRectangle(cornerRadius: 6)
                  .fill(selected ? SparkStyle.accent.opacity(0.14) : Color.clear)
              )
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          if topics.isEmpty {
            Text("Nothing matches \u{201C}\(search)\u{201D}.")
              .font(.system(size: 12))
              .foregroundStyle(SparkStyle.secondaryLabel)
              .padding(8)
          }
        }
      }
    }
    .padding(12)
    .frame(width: 220)
    .background(SparkStyle.chrome)
  }

  private var detail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Image(systemName: topic.systemImage)
            .font(.system(size: 18))
            .foregroundStyle(SparkStyle.accent)
          Text(topic.title)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(SparkStyle.label)
        }
        SparkDialogGroup {
          ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { index, paragraph in
            if index > 0 { SparkDialogDivider() }
            Text(paragraph)
              .font(.system(size: 13))
              .foregroundStyle(SparkStyle.label)
              .lineSpacing(2)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
              .padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        if topic == .moreHelp {
          HStack(spacing: 8) {
            Button("Support Page") { LegalLinks.openSupport() }
            Button("Email Support") { LegalLinks.openFeedback() }
              .buttonStyle(.borderedProminent)
              .tint(SparkStyle.accent)
          }
        }
      }
      .padding(24)
      .frame(maxWidth: 640, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

enum HelpTopic: String, CaseIterable, Identifiable {
  case gettingAround, editing, formulas, data, charts, files, appleIntelligence, assistants,
    shortcuts, moreHelp

  var id: String { rawValue }

  var title: String {
    switch self {
    case .gettingAround: "Getting around"
    case .editing: "Typing and editing"
    case .formulas: "Formulas"
    case .data: "Sorting and filters"
    case .charts: "Charts and pivot tables"
    case .files: "Files"
    case .appleIntelligence: "Apple Intelligence"
    case .assistants: "AI assistants"
    case .shortcuts: "Keyboard shortcuts"
    case .moreHelp: "More help"
    }
  }

  var systemImage: String {
    switch self {
    case .gettingAround: "arrow.up.and.down.and.arrow.left.and.right"
    case .editing: "character.cursor.ibeam"
    case .formulas: "function"
    case .data: "line.3.horizontal.decrease.circle"
    case .charts: "chart.bar"
    case .files: "doc"
    case .appleIntelligence: "brain.head.profile"
    case .assistants: "sparkles"
    case .shortcuts: "keyboard"
    case .moreHelp: "questionmark.circle"
    }
  }

  var paragraphs: [String] {
    switch self {
    case .gettingAround:
      return [
        "Arrow keys move one cell. Command-arrow jumps to the edge of the data; add Shift to select as you go. Page Up and Page Down move a screen at a time.",
        "To jump to a cell, choose Edit › Go To (Control-G) or click the name box at the left of the formula bar, type an address such as U37, a range such as B2:D40, a cell on another sheet such as Sales!A1, or a defined name, and press Return.",
        "Scrolling follows your Mac's setting in System Settings. To turn it around for the grid only, use Settings › General › Reverse scroll direction. Drag the scroll bars at the right and bottom edges to move through a large sheet quickly.",
      ]
    case .editing:
      return [
        "Select a cell and type to replace it. Press F2, or double-click, to change what is already there. Return moves down, Tab moves right, and Escape cancels.",
        "Start with an apostrophe (') to keep something as text, such as '00123 or '1-2. Without one, 3/4 or 15-Mar is a date this year, 1 1/2 is one and a half shown as a fraction, and #N/A is the error value.",
        "Edit › Select Blank Cells selects the empty cells in the selection, or in the part of the sheet that holds data when one cell is selected. Edit › Find and Replace searches every cell; Fill Down (Command-D) and Fill Right (Command-R) copy the first cell along the selection.",
        "To move cells, drag the edge of the selection to the new place; formulas that use those cells follow them. Format › Add Fonts adds font files (.ttf, .otf) to the font menu.",
        "Every change can be undone with Command-Z.",
      ]
    case .formulas:
      return [
        "Start with = to write a formula, such as =SUM(B2:B20). As you type a function name, Spark Grid suggests functions; press Tab or click one to choose it, then click or drag over cells to put their address in the formula. To use cells on another sheet, click its tab while the formula waits for a reference (after = or a comma, say), drag over the cells, and press Return: the formula goes back to its own cell.",
        "The fx button beside the formula bar lists every function with a short description.",
        "Spark Grid adds SEM, the standard error of the mean, and MEAN, MEAN.ARITH, MEAN.GEOM and MEAN.HARM. Files store them as formulas every spreadsheet app calculates the same way (SEM as STDEV.S divided by the square root of COUNT), and Spark Grid shows them as you typed them when it opens the file again.",
        "When a file uses a function Spark Grid does not have yet, the cell shows the result saved in the file, and the formula is saved back unchanged, so the app that wrote it calculates it again.",
        "REGEXTEST, REGEXEXTRACT and REGEXREPLACE work with regular expressions: =REGEXTEST(A2,\"^\\d+$\") is TRUE when A2 is all digits, =REGEXEXTRACT(A2,\"\\d+\",1) lists every number in A2 across a row, and =REGEXREPLACE(A2,\"(\\w+) (\\w+)\",\"$2 $1\") swaps two words. A last argument of 1 ignores capitals.",
      ]
    case .data:
      return [
        "Data › Sort Range sorts by one or more columns. Data › Create a Filter adds filter buttons to the header row; each button lists values to show and rules such as greater than or contains.",
        "Data › Find Duplicates, Text to Columns and Remove Duplicates help clean up data. Format › Conditional Formatting colors cells by rules, and Data › Create Table turns a range into a styled table. Text with no color of its own turns light or dark so it reads on a cell's fill; to keep text its own color instead, turn off Settings › General › Readable text on filled cells.",
        "Data › Data Validation says what cells may hold: whole numbers or decimals in a range, dates, times, text of a given length, or a formula that must be TRUE. An entry that breaks the rule is refused, or kept after a warning, as the rule says. Data › Dropdown List gives cells a list of choices.",
        "Data › Goal Seek finds the input that gives a formula the result you want: name the formula cell, the value it should reach and the cell to change, then Keep the answer or Cancel.",
      ]
    case .charts:
      return [
        "Select data with its header row and choose Insert › Chart. Charts can be moved, resized and edited: double-click one to change its type, series, colors, title and axis titles. A bar or line chart with one series can show error bars from a column of plus-or-minus amounts, such as a standard error column. Chart types are bar, horizontal bar, stacked bar, stacked horizontal bar, line, area, stacked area, pie, doughnut and scatter. Bar, line, area and scatter charts can show a trendline (linear, exponential, logarithmic, power or moving average) with its equation and R². Right-click a chart to copy it or save it as an image. In Insert › Chart, Describe it makes the choices from a sentence such as \"units by month as a line with a trend\" (see Apple Intelligence), and the \u{24D8} on each chart type says what it is for.",
        "Insert › Sparklines puts a small line, column or win/loss chart in a cell for each row or column of data: choose the data and the cells to put them in. They redraw as the numbers change, move with inserted rows and columns, and save in .xlsx files, which other spreadsheet apps show too. Insert › Sparklines › Clear Sparklines removes those in the selected cells.",
        "Data › PivotTable makes a pivot table from a range on a new sheet. Drag fields to Rows, Columns, Values and Filters; values can be summed, counted, averaged, or show the largest or smallest.",
      ]
    case .files:
      return [
        "Spark Grid opens .xlsx and .csv files, .numbers documents and .ods spreadsheets, and saves .xlsx, .ods and .csv. A .numbers or .ods file opens as a new workbook, so saving never writes over it. Saving as .ods keeps every sheet with its values, formulas, number formats, text styles, colors, borders, merged cells and column widths; charts, pictures, comments, conditional formatting and sparklines are not saved in it yet. A CSV file is saved back as CSV; Save As offers .xlsx when you want to keep formatting, more than one sheet, charts or pivot tables.",
        "Save As also writes tab-separated text (.tsv) of the active sheet, and a web page (.html) showing every sheet as it looks, with its number formats, colors and merged cells, to read in a browser or send. A web page is a copy: the window keeps its own file, and Spark Grid doesn't open web pages.",
        "When a file uses functions Spark Grid doesn't have, it says which when the file opens: those cells show the results saved in the file and don't change until the app that made the file calculates them again. Show goes to the first cell that uses each one; Save a Copy keeps the file as it was. Settings › General turns the note off. When you save an .xlsx file, what Spark Grid cannot edit yet is kept as it was, such as pivot tables made in other apps. Comments, dropdown lists, data validation, hidden rows, columns and sheets, tables and charts can all be changed in Spark Grid.",
        "Each time you save, Spark Grid keeps the earlier version too, and while autosave is on one every ten minutes. File › Browse Versions lists them: Open a Copy shows one in a new window, and Restore puts it in place of the workbook (Edit › Undo takes that back).",
      ]
    case .assistants:
      return [
        "AI assistants on your Mac that support MCP (the Model Context Protocol) can read and change your open workbooks: list sheets, read values and formulas, write cells, add sheets, save, and export a PDF or CSV. Everything stays on your Mac.",
        "To connect one, open Settings › AI and use Copy to put the setup into your assistant's settings. The first time an assistant uses Spark Grid, macOS asks whether it may; you can change that later in System Settings › Privacy & Security › Automation.",
        "One Undo takes back everything an assistant wrote in one go. An assistant can open and export files in your Downloads folder; open other files in Spark Grid yourself first.",
        "Spark Grid's own help with formulas and charts uses Apple Intelligence instead: see Apple Intelligence.",
      ]
    case .appleIntelligence:
      return [
        "Spark Grid uses Apple Intelligence, the language model built into your Mac, in two places. Insert › Formula Help (Control-Command-H) writes a formula from a sentence, such as \"total of Sales where Region is West\", or explains the formula in the selected cell. In Insert › Chart, Describe it turns a sentence such as \"units by month as a line with a trend\" into the chart's type, columns, trendline and title.",
        "It runs on your Mac: your cells and what you type are never sent anywhere, and Spark Grid makes no network connections. It needs macOS 26 or later on a Mac that supports Apple Intelligence, with Apple Intelligence turned on in System Settings.",
        "The model is small and can be wrong. Formula Help shows the result before you insert a formula, asks again once when its first answer gives an error, and says so when an answer still doesn't work. Check a chart's preview before inserting it.",
        "To turn it off, open Settings › AI and switch off Use Apple Intelligence. Formula Help and Describe it then leave the menus and dialogs; everything else works as before.",
      ]
    case .shortcuts:
      return [
        "Every Spark Grid shortcut can be changed in Settings › Shortcuts: click one and press the new keys. Each has its own reset button, and Reset All puts them all back. Quit, Close, Hide, Minimize and Settings are the Mac's own and stay as they are; arrows, Return, Tab and Delete move and edit as usual.",
        "As they start: Command-F Find, Option-Command-F Find and Replace, Control-G Go To, Command-D Fill Down, Command-R Fill Right, Command-K Insert Link, Command-\\ Clear Formats, F2 to edit a cell, Option-Down Arrow to open a dropdown list. Menus show the shortcut you have set beside each command.",
      ]
    case .moreHelp:
      return [
        "Questions, problems or ideas are welcome. The support page has answers to common questions, and email reaches the developer directly."
      ]
    }
  }
}

/// Replaces the empty Help menu.
struct SpreadsheetHelpCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .help) {
      Button("Spark Grid Help") { openWindow(id: "help") }
        .hotkey(.help, AppSettings.shared)
      Button("Welcome to Spark Grid") { openWindow(id: "welcome") }
      Button("What's New in Spark Grid") { openWindow(id: "whatsnew") }
      Divider()
      Button("Support Page") { LegalLinks.openSupport() }
      Button("Email Support") { LegalLinks.openFeedback() }
    }
  }
}
