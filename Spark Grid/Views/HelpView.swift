import SwiftUI

/// Help › Spark Grid Help: a short guide that works offline. Help used to be empty (a Reddit
/// note, Nov 19).
struct HelpView: View {
  @State private var topic: HelpTopic? = .gettingAround

  var body: some View {
    NavigationSplitView {
      List(HelpTopic.allCases, selection: $topic) { item in
        Label(item.title, systemImage: item.systemImage).tag(item)
      }
      .navigationSplitViewColumnWidth(min: 190, ideal: 210)
    } detail: {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let topic {
            Text(topic.title).font(.title2.weight(.semibold))
            ForEach(topic.paragraphs, id: \.self) { paragraph in
              Text(paragraph)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            }
            if topic == .moreHelp {
              HStack {
                Button("Support Page") { LegalLinks.openSupport() }
                Button("Email Support") { LegalLinks.openFeedback() }
              }
            }
          }
        }
        .padding(24)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(minWidth: 680, minHeight: 440)
  }
}

enum HelpTopic: String, CaseIterable, Identifiable {
  case gettingAround, editing, formulas, data, charts, files, assistants, shortcuts, moreHelp

  var id: String { rawValue }

  var title: String {
    switch self {
    case .gettingAround: "Getting around"
    case .editing: "Typing and editing"
    case .formulas: "Formulas"
    case .data: "Sorting and filters"
    case .charts: "Charts and pivot tables"
    case .files: "Files"
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
        "Start with an apostrophe (') to keep something as text, such as '00123 or '1-2.",
        "Edit › Select Blank Cells selects the empty cells in the selection, or in the part of the sheet that holds data when one cell is selected. Edit › Find and Replace searches every cell; Fill Down (Command-D) and Fill Right (Command-R) copy the first cell along the selection.",
        "To move cells, drag the edge of the selection to the new place; formulas that use those cells follow them. Format › Add Fonts adds font files (.ttf, .otf) to the font menu.",
        "Every change can be undone with Command-Z.",
      ]
    case .formulas:
      return [
        "Start with = to write a formula, such as =SUM(B2:B20). As you type a function name, Spark Grid suggests functions; press Tab or click one to choose it, then click or drag over cells to put their address in the formula.",
        "The fx button beside the formula bar lists every function with a short description.",
        "Spark Grid adds SEM, the standard error of the mean, and MEAN, MEAN.ARITH, MEAN.GEOM and MEAN.HARM. Files store them as formulas every spreadsheet app calculates the same way (SEM as STDEV.S divided by the square root of COUNT), and Spark Grid shows them as you typed them when it opens the file again.",
        "When a file uses a function Spark Grid does not have yet, the cell shows the result saved in the file, and the formula is saved back unchanged, so the app that wrote it calculates it again.",
      ]
    case .data:
      return [
        "Data › Sort Range sorts by one or more columns. Data › Create a Filter adds filter buttons to the header row; each button lists values to show and rules such as greater than or contains.",
        "Data › Find Duplicates, Text to Columns and Remove Duplicates help clean up data. Format › Conditional Formatting colors cells by rules, and Data › Create Table turns a range into a styled table.",
      ]
    case .charts:
      return [
        "Select data with its header row and choose Insert › Chart. Charts can be moved, resized and edited: double-click one to change its type, series, colors, title and axis titles. A bar or line chart with one series can show error bars from a column of plus-or-minus amounts, such as a standard error column. Right-click a chart to copy it or save it as an image.",
        "Data › PivotTable makes a pivot table from a range on a new sheet. Drag fields to Rows, Columns, Values and Filters; values can be summed, counted, averaged, or show the largest or smallest.",
      ]
    case .files:
      return [
        "Spark Grid opens .xlsx and .csv files, .numbers documents and .ods spreadsheets, and saves .xlsx and .csv. A .numbers or .ods file opens as a new workbook, so saving never writes over it. A CSV file is saved back as CSV; Save As offers .xlsx when you want to keep formatting, more than one sheet, charts or pivot tables.",
        "When you save an .xlsx file, what Spark Grid cannot edit yet is kept as it was: hidden rows and sheets, comments, dropdown lists, tables, charts and pivot tables among them.",
      ]
    case .assistants:
      return [
        "AI assistants on your Mac that support MCP (the Model Context Protocol) can read and change your open workbooks: list sheets, read values and formulas, write cells, add sheets, save, and export a PDF or CSV. Everything stays on your Mac.",
        "To connect one, open Settings › AI and use Copy to put the setup into your assistant's settings. The first time an assistant uses Spark Grid, macOS asks whether it may; you can change that later in System Settings › Privacy & Security › Automation.",
        "One Undo takes back everything an assistant wrote in one go. An assistant can open and export files in your Downloads folder; open other files in Spark Grid yourself first.",
      ]
    case .shortcuts:
      return [
        "Settings › Shortcuts lists the shortcuts for editing, formulas, formatting and saving, and you can change any of them there. Every other menu command shows its shortcut beside its name in the menu.",
        "Common ones: Command-F Find, Option-Command-F Find and Replace, Control-G Go To, Command-D Fill Down, Command-R Fill Right, Command-K Insert Link, F2 to edit a cell.",
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
        .keyboardShortcut("?", modifiers: .command)
      Divider()
      Button("Support Page") { LegalLinks.openSupport() }
      Button("Email Support") { LegalLinks.openFeedback() }
    }
  }
}
