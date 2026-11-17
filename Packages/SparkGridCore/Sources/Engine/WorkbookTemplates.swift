import FileFormats
import Foundation
import GridCore
import Model
import NumberFormat

/// The templates on the start screen: workbooks made here, with made-up sample data, so each
/// opens as a new Untitled workbook that works at once. Dates are set from the day it opens.
public nonisolated enum WorkbookTemplate: String, CaseIterable, Identifiable, Sendable {
  case monthlyBudget, expenseReport, loanCalculator, toDoList
  case invoice, salesPipeline, timesheet, inventory
  case projectTracker, weeklySchedule

  public enum Category: String, CaseIterable, Sendable {
    case personal = "Personal"
    case business = "Business"
    case planning = "Planning"
  }

  public var id: String { rawValue }

  public var name: String {
    switch self {
    case .monthlyBudget: return "Monthly Budget"
    case .expenseReport: return "Expense Report"
    case .loanCalculator: return "Loan Calculator"
    case .toDoList: return "To-Do List"
    case .invoice: return "Invoice"
    case .salesPipeline: return "Sales Pipeline"
    case .timesheet: return "Timesheet"
    case .inventory: return "Inventory"
    case .projectTracker: return "Project Tracker"
    case .weeklySchedule: return "Weekly Schedule"
    }
  }

  /// One or two sentences for the start screen's info button.
  public var summary: String {
    switch self {
    case .monthlyBudget:
      return
        "Plan income and spending for a month, then fill in what really happened. Over-budget lines turn red."
    case .expenseReport:
      return "Log receipts by date and category. Totals show what was spent and what is owed back."
    case .loanCalculator:
      return
        "Enter an amount, rate and length to see the payment, total interest and a full payment schedule."
    case .toDoList:
      return
        "Tasks with due dates, priorities and lists. Overdue tasks show in red; finished ones fade."
    case .invoice:
      return
        "A one-page invoice with line items, tax and a total due. Add your details and the client's."
    case .salesPipeline:
      return
        "Track deals by stage. Each stage has a chance of winning, which gives a weighted pipeline."
    case .timesheet:
      return "One week of start and end times with breaks. Totals hours, overtime and pay."
    case .inventory:
      return "Stock levels, costs and reorder points. Items that need reordering are highlighted."
    case .projectTracker:
      return "Tasks with owners, status, dates and progress. Late and blocked tasks stand out."
    case .weeklySchedule:
      return "A week in half-hour slots. Change the start date and every day moves with it."
    }
  }

  public var category: Category {
    switch self {
    case .monthlyBudget, .expenseReport, .loanCalculator, .toDoList: return .personal
    case .invoice, .salesPipeline, .timesheet, .inventory: return .business
    case .projectTracker, .weeklySchedule: return .planning
    }
  }

  /// The header color, also used for the start screen's thumbnail.
  public var color: CodableColor {
    switch self {
    case .monthlyBudget, .toDoList: return TemplateBuilder.green
    case .invoice, .loanCalculator: return TemplateBuilder.blue
    case .projectTracker, .weeklySchedule: return TemplateBuilder.purple
    case .salesPipeline, .inventory: return TemplateBuilder.amber
    case .expenseReport, .timesheet: return TemplateBuilder.teal
    }
  }

  /// The workbook, with dates counted from `today`.
  public func makeWorkbook(today: Date = Date(), calendar: Calendar = .current) -> Workbook {
    var b = TemplateBuilder(name: name, color: color, today: today, calendar: calendar)
    switch self {
    case .monthlyBudget: b.monthlyBudget()
    case .expenseReport: b.expenseReport()
    case .loanCalculator: b.loanCalculator()
    case .toDoList: b.toDoList()
    case .invoice: b.invoice()
    case .salesPipeline: b.salesPipeline()
    case .timesheet: b.timesheet()
    case .inventory: b.inventory()
    case .projectTracker: b.projectTracker()
    case .weeklySchedule: b.weeklySchedule()
    }
    var sheet = b.sheet
    sheet.recomputePopulatedExtents()
    sheet.rebuildFormulaIngestIndex()
    return Workbook(sheets: [sheet])
  }
}

/// Writes one template sheet. Addresses are A1 text so each template reads like the sheet.
nonisolated struct TemplateBuilder {
  static let green = CodableColor(red: 0.18, green: 0.49, blue: 0.31, alpha: 1)
  static let blue = CodableColor(red: 0.12, green: 0.37, blue: 0.66, alpha: 1)
  static let purple = CodableColor(red: 0.48, green: 0.31, blue: 0.69, alpha: 1)
  static let amber = CodableColor(red: 0.72, green: 0.47, blue: 0.12, alpha: 1)
  static let teal = CodableColor(red: 0.16, green: 0.50, blue: 0.54, alpha: 1)
  static let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
  static let muted = CodableColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
  static let lightLine = CodableColor(red: 0.80, green: 0.80, blue: 0.82, alpha: 1)
  static let red = CodableColor(red: 0.75, green: 0.11, blue: 0.11, alpha: 1)

  var sheet: Sheet
  let color: CodableColor
  let tint: CodableColor
  let todaySerial: Int
  let calendar: Calendar
  let today: Date

  init(name: String, color: CodableColor, today: Date, calendar: Calendar) {
    sheet = Sheet(name: name)
    self.color = color
    tint = CodableColor(
      red: 1 - (1 - color.red) * 0.12, green: 1 - (1 - color.green) * 0.12,
      blue: 1 - (1 - color.blue) * 0.12, alpha: 1)
    self.calendar = calendar
    self.today = calendar.startOfDay(for: today)
    todaySerial = Self.serial(of: self.today, calendar: calendar)
  }

  // MARK: Pieces

  static func serial(of date: Date, calendar: Calendar) -> Int {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let day = utc.date(from: parts),
      let base = utc.date(from: DateComponents(year: 1899, month: 12, day: 30))
    else { return 0 }
    return utc.dateComponents([.day], from: base, to: day).day ?? 0
  }

  /// Monday of this week, as a date serial.
  var mondaySerial: Int {
    let weekday = calendar.component(.weekday, from: today)  // 1 = Sunday
    return todaySerial - ((weekday + 5) % 7)
  }

  /// The templates only name valid cells; a typo lands in A1, where a test sees it.
  func address(_ a1: String) -> CellAddress {
    range(a1).start
  }

  func range(_ a1: String) -> CellRange {
    XLSXCodec.parseCellRange(a1) ?? CellRange(start: .origin, end: .origin)
  }

  mutating func put(_ a1: String, _ raw: String, _ format: CellFormat? = nil) {
    sheet.setCell(Cell(raw: raw, format: format), at: address(a1))
  }

  mutating func put(_ a1: String, _ number: Double, _ format: CellFormat? = nil) {
    put(a1, Self.text(number), format)
  }

  static func text(_ number: Double) -> String {
    number == number.rounded() && abs(number) < 1e15
      ? String(Int(number)) : String(number)
  }

  /// One row of values from a column, as text, numbers or formulas.
  mutating func row(_ a1: String, _ values: [Any?], formats: [CellFormat?] = []) {
    let start = address(a1)
    for (i, value) in values.enumerated() {
      let at = CellAddress(row: start.row, col: start.col + i)
      let format = i < formats.count ? formats[i] : nil
      switch value {
      case let text as String: sheet.setCell(Cell(raw: text, format: format), at: at)
      case let number as Double: sheet.setCell(Cell(raw: Self.text(number), format: format), at: at)
      case let number as Int: sheet.setCell(Cell(raw: String(number), format: format), at: at)
      default:
        if let format { sheet.setCell(Cell(raw: "", format: format), at: at) }
      }
    }
  }

  mutating func title(_ text: String, subtitle: String? = nil) {
    put("A1", text, CellFormat(bold: true, fontSize: 20))
    sheet.rowHeights[0] = 34
    if let subtitle {
      put("A2", subtitle, CellFormat(textColor: Self.muted))
    }
  }

  /// A header row in the template's color, with white bold text.
  mutating func header(_ a1: String, _ titles: [String], rightAligned: Set<Int> = []) {
    let start = address(a1)
    for (i, title) in titles.enumerated() {
      var f = CellFormat(bold: true, textColor: Self.white, fillColor: color)
      if rightAligned.contains(i) { f.horizontalAlign = .right }
      sheet.setCell(
        Cell(raw: title, format: f), at: CellAddress(row: start.row, col: start.col + i))
    }
    sheet.rowHeights[start.row] = 24
  }

  /// A label in bold on the template's light tint.
  mutating func label(_ a1: String, _ text: String) {
    put(a1, text, CellFormat(bold: true, fillColor: tint))
  }

  mutating func widths(_ points: [CGFloat]) {
    for (i, w) in points.enumerated() { sheet.columnWidths[i] = w }
  }

  mutating func dropdown(_ a1: String, _ items: [String]) {
    let formula = "\"" + items.joined(separator: ",") + "\""
    sheet.fileExtras.dataValidations.append(
      DataValidationRule(
        ranges: [range(a1)],
        attributes: #"type="list" allowBlank="1" showErrorMessage="1""#,
        body: "<formula1>\(XLSXCodec.escapeXML(formula))</formula1>"))
  }

  mutating func highlight(_ a1: String, formula: String, _ style: ConditionalFormatStyle) {
    sheet.conditionalFormats.append(
      ConditionalFormatRule(
        range: range(a1), stopIfTrue: false, predicate: .formula(formula), style: style))
  }

  var money: CellFormat { CellFormat(numberFormat: .currency, formatCode: "$#,##0.00") }
  var wholeMoney: CellFormat { CellFormat(numberFormat: .currency, formatCode: "$#,##0") }
  var percent: CellFormat { CellFormat(numberFormat: .percent, formatCode: "0%") }
  var date: CellFormat { CellFormat(numberFormat: .date, formatCode: "mmm d, yyyy") }
  var shortDate: CellFormat { CellFormat(numberFormat: .date, formatCode: "mmm d") }
  var time: CellFormat { CellFormat(numberFormat: .time, formatCode: "h:mm AM/PM") }
  var hours: CellFormat { CellFormat(numberFormat: .number, formatCode: "0.00") }
  var totalLabel: CellFormat {
    CellFormat(bold: true, borders: CellBorders(top: .thin(Self.lightLine)))
  }
  func total(_ base: CellFormat) -> CellFormat {
    var f = base
    f.bold = true
    f.borders = CellBorders(top: .thin(Self.lightLine))
    return f
  }

  static let overdueText = ConditionalFormatStyle(textColor: red)
  static let doneText = ConditionalFormatStyle(textColor: muted)

  // MARK: Personal

  mutating func monthlyBudget() {
    title("Monthly Budget", subtitle: "Planned against actual, for one month.")
    put("A3", "Month", CellFormat(bold: true))
    put("B3", Double(todaySerial), CellFormat(numberFormat: .date, formatCode: "mmmm yyyy"))
    header("A5", ["Income", "Planned", "Actual", "Difference"], rightAligned: [1, 2, 3])
    let income: [(String, Double, Double)] = [("Salary", 4200, 4200), ("Side work", 300, 450)]
    for (i, item) in income.enumerated() {
      let r = 6 + i
      row("A\(r)", [item.0, item.1, item.2, "=C\(r)-B\(r)"], formats: [nil, money, money, money])
    }
    row(
      "A8", ["Total income", "=SUM(B6:B7)", "=SUM(C6:C7)", "=C8-B8"],
      formats: [totalLabel, total(money), total(money), total(money)])

    header("A10", ["Expenses", "Planned", "Actual", "Difference"], rightAligned: [1, 2, 3])
    let expenses: [(String, Double, Double)] = [
      ("Rent", 1500, 1500), ("Groceries", 550, 612), ("Utilities", 180, 164),
      ("Transport", 220, 198), ("Insurance", 160, 160), ("Phone and internet", 95, 95),
      ("Eating out", 200, 265), ("Savings", 500, 500), ("Other", 150, 88),
    ]
    for (i, item) in expenses.enumerated() {
      let r = 11 + i
      row("A\(r)", [item.0, item.1, item.2, "=B\(r)-C\(r)"], formats: [nil, money, money, money])
    }
    row(
      "A20", ["Total expenses", "=SUM(B11:B19)", "=SUM(C11:C19)", "=B20-C20"],
      formats: [totalLabel, total(money), total(money), total(money)])

    row(
      "A22", ["Left over", "=B8-B20", "=C8-C20", "=C22-B22"],
      formats: [CellFormat(bold: true, fillColor: tint), total(money), total(money), total(money)])
    // Over budget shows in red.
    highlight("D6:D20", formula: "=D6<0", Self.overdueText)
    widths([170, 100, 100, 100])
  }

  mutating func expenseReport() {
    title("Expense Report", subtitle: "Receipts for one trip or month.")
    put("A3", "Name", CellFormat(bold: true))
    put("B3", "[Your name]")
    put("A4", "Purpose", CellFormat(bold: true))
    put("B4", "Client visit")
    header(
      "A6", ["Date", "Description", "Category", "Paid with", "Amount", "Reimbursable"],
      rightAligned: [4])
    let items: [(Int, String, String, String, Double, String)] = [
      (-9, "Train to the city", "Transport", "Card", 42.50, "Yes"),
      (-9, "Hotel, two nights", "Lodging", "Card", 318.00, "Yes"),
      (-8, "Lunch with client", "Meals", "Card", 64.20, "Yes"),
      (-8, "Printing for meeting", "Supplies", "Cash", 18.75, "Yes"),
      (-7, "Taxi to station", "Transport", "Cash", 23.00, "Yes"),
      (-7, "Coffee", "Meals", "Card", 4.80, "No"),
    ]
    for (i, item) in items.enumerated() {
      let r = 7 + i
      row(
        "A\(r)", [Double(todaySerial + item.0), item.1, item.2, item.3, item.4, item.5],
        formats: [date, nil, nil, nil, money, nil])
    }
    for r in 13...20 {
      row("A\(r)", [nil, nil, nil, nil, nil, nil], formats: [date, nil, nil, nil, money, nil])
    }
    dropdown("C7:C20", ["Transport", "Lodging", "Meals", "Supplies", "Other"])
    dropdown("D7:D20", ["Card", "Cash", "Other"])
    dropdown("F7:F20", ["Yes", "No"])
    row(
      "A22", ["Total", nil, nil, nil, "=SUM(E7:E20)"],
      formats: [totalLabel, totalLabel, totalLabel, totalLabel, total(money)])
    row(
      "A23", ["To be repaid", nil, nil, nil, #"=SUMIF(F7:F20,"Yes",E7:E20)"#],
      formats: [CellFormat(bold: true), nil, nil, nil, total(money)])

    header("H6", ["Category", "Spent"], rightAligned: [1])
    for (i, category) in ["Transport", "Lodging", "Meals", "Supplies", "Other"].enumerated() {
      let r = 7 + i
      row("H\(r)", [category, "=SUMIF($C$7:$C$20,H\(r),$E$7:$E$20)"], formats: [nil, money])
    }
    sheet.frozenRows = 6
    widths([100, 190, 100, 90, 90, 100, 24, 100, 90])
  }

  mutating func loanCalculator() {
    title("Loan Calculator", subtitle: "Change the amounts in the shaded cells.")
    let input = CellFormat(fillColor: tint)
    var inputMoney = money
    inputMoney.fillColor = tint
    var inputPercent = CellFormat(numberFormat: .percent, formatCode: "0.00%")
    inputPercent.fillColor = tint
    var inputDate = date
    inputDate.fillColor = tint
    let nextMonth = calendar.date(byAdding: .month, value: 1, to: today) ?? today
    let firstOfNextMonth =
      calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) ?? nextMonth

    row("A3", ["Loan amount", 25000.0], formats: [nil, inputMoney])
    row("A4", ["Yearly interest rate", 0.065], formats: [nil, inputPercent])
    row("A5", ["Length in years", 5], formats: [nil, input])
    row("A6", ["Payments a year", 12], formats: [nil, input])
    row(
      "A7", ["First payment", Double(Self.serial(of: firstOfNextMonth, calendar: calendar))],
      formats: [nil, inputDate])

    row(
      "D3", ["Payment", "=PMT(B4/B6,B5*B6,-B3)"], formats: [CellFormat(bold: true), total(money)])
    row("D4", ["Number of payments", "=B5*B6"])
    row("D5", ["Total paid", "=E3*E4"], formats: [nil, money])
    row("D6", ["Total interest", "=E5-B3"], formats: [nil, money])

    header(
      "A9",
      ["No.", "Date", "Opening balance", "Payment", "Principal", "Interest", "Closing balance"],
      rightAligned: [2, 3, 4, 5, 6])
    // 360 rows cover a 30-year monthly loan; rows past the last payment stay blank.
    for n in 1...360 {
      let r = 9 + n
      let opening = n == 1 ? "=IF(A\(r)=\"\",\"\",$B$3)" : "=IF(A\(r)=\"\",\"\",G\(r - 1))"
      row(
        "A\(r)",
        [
          n == 1
            ? "=IF($E$4>=1,1,\"\")"
            : "=IF(A\(r - 1)=\"\",\"\",IF(A\(r - 1)+1>$E$4,\"\",A\(r - 1)+1))",
          "=IF(A\(r)=\"\",\"\",EDATE($B$7,(A\(r)-1)*12/$B$6))",
          opening,
          "=IF(A\(r)=\"\",\"\",$E$3)",
          "=IF(A\(r)=\"\",\"\",PPMT($B$4/$B$6,A\(r),$E$4,-$B$3))",
          "=IF(A\(r)=\"\",\"\",IPMT($B$4/$B$6,A\(r),$E$4,-$B$3))",
          "=IF(A\(r)=\"\",\"\",ROUND(C\(r)-E\(r),2))",
        ], formats: [nil, date, money, money, money, money, money])
    }
    sheet.frozenRows = 9
    widths([150, 110, 120, 140, 100, 100, 120])
  }

  mutating func toDoList() {
    title("To-Do List", subtitle: "Choose Yes under Done when a task is finished.")
    row(
      "A3",
      [
        "Open", #"=COUNTIF(A6:A40,"No")"#, nil, "Overdue",
        #"=COUNTIFS(A6:A40,"No",C6:C40,"<"&TODAY())"#,
      ],
      formats: [CellFormat(bold: true), nil, nil, CellFormat(bold: true), nil])
    header("A5", ["Done", "Task", "Due", "Priority", "List", "Notes"])
    let tasks: [(String, String, Int, String, String, String)] = [
      ("No", "Book dentist appointment", 2, "Medium", "Home", ""),
      ("No", "Send quarterly report", 1, "High", "Work", "Numbers from finance first"),
      ("Yes", "Renew car registration", -3, "High", "Errands", ""),
      ("No", "Pick up dry cleaning", 0, "Low", "Errands", ""),
      ("No", "Plan team lunch", 6, "Medium", "Work", "Ask about dietary needs"),
      ("No", "Fix the porch light", -1, "Low", "Home", ""),
      ("Yes", "Return library books", -2, "Low", "Errands", ""),
    ]
    for (i, t) in tasks.enumerated() {
      let r = 6 + i
      row(
        "A\(r)", [t.0, t.1, Double(todaySerial + t.2), t.3, t.4, t.5],
        formats: [CellFormat(horizontalAlign: .center), nil, shortDate, nil, nil, nil])
    }
    for r in 13...40 {
      row(
        "A\(r)", [nil, nil, nil], formats: [CellFormat(horizontalAlign: .center), nil, shortDate])
    }
    dropdown("A6:A40", ["No", "Yes"])
    dropdown("D6:D40", ["High", "Medium", "Low"])
    dropdown("E6:E40", ["Home", "Work", "Errands"])
    highlight("A6:F40", formula: #"=$A6="Yes""#, Self.doneText)
    highlight("C6:C40", formula: #"=AND($A6="No",$C6<>"",$C6<TODAY())"#, Self.overdueText)
    sheet.frozenRows = 5
    widths([60, 230, 80, 80, 80, 220])
  }

  // MARK: Business

  mutating func invoice() {
    title("Invoice")
    put("A2", "[Your business name]", CellFormat(bold: true))
    put("A3", "[Street address]")
    put("A4", "[City, postcode]")
    put("A5", "[Email or phone]")
    row(
      "D2", ["Invoice no.", "INV-0001"],
      formats: [
        CellFormat(bold: true, horizontalAlign: .right), CellFormat(horizontalAlign: .right),
      ])
    row(
      "D3", ["Date", Double(todaySerial)],
      formats: [CellFormat(bold: true, horizontalAlign: .right), date])
    row("D4", ["Due", "=E3+30"], formats: [CellFormat(bold: true, horizontalAlign: .right), date])

    label("A7", "Bill to")
    put("A8", "[Client name]")
    put("A9", "[Client address]")

    header(
      "A11", ["Description", "Quantity", "Unit price", "", "Amount"], rightAligned: [1, 2, 4])
    let items: [(String, Double, Double)] = [
      ("Design consultation, hours", 4, 85), ("Website updates, hours", 6, 70),
      ("Hosting, 12 months", 1, 180),
    ]
    for r in 12...21 {
      let i = r - 12
      let item: (String, Double, Double)? = i < items.count ? items[i] : nil
      row(
        "A\(r)", [item?.0, item?.1, item?.2, nil, #"=IF(B\#(r)="","",B\#(r)*C\#(r))"#],
        formats: [nil, nil, money, nil, money])
    }
    row(
      "D23", ["Subtotal", "=SUM(E12:E21)"], formats: [CellFormat(horizontalAlign: .right), money])
    row(
      "C24", [0.08, "Tax", "=E23*C24"],
      formats: [
        CellFormat(fillColor: tint, numberFormat: .percent, formatCode: "0%"),
        CellFormat(horizontalAlign: .right), money,
      ])
    row(
      "D25", ["Total due", "=E23+E24"],
      formats: [
        CellFormat(
          bold: true, horizontalAlign: .right, borders: CellBorders(top: .thin(Self.lightLine))),
        total(money),
      ])
    put(
      "A27", "Payment is due within 30 days. Thank you for your business.",
      CellFormat(textColor: Self.muted))
    widths([230, 80, 90, 90, 110])
  }

  mutating func salesPipeline() {
    title(
      "Sales Pipeline",
      subtitle: "Weighted value is the deal value times the chance of winning at its stage.")
    row(
      "A3",
      [
        "Open pipeline", #"=SUMIFS(E7:E40,D7:D40,"<>Won",D7:D40,"<>Lost")"#, nil, "Weighted",
        "=SUM(G7:G40)", nil, "Won", #"=SUMIF(D7:D40,"Won",E7:E40)"#,
      ],
      formats: [
        CellFormat(bold: true), wholeMoney, nil, CellFormat(bold: true), wholeMoney, nil,
        CellFormat(bold: true), wholeMoney,
      ])
    header(
      "A6", ["Deal", "Company", "Owner", "Stage", "Value", "Chance", "Weighted", "Close date"],
      rightAligned: [4, 5, 6])
    let deals: [(String, String, String, String, Double, Int)] = [
      ("Website rebuild", "Harbor Lane Bakery", "Dana", "Proposal", 12000, 21),
      ("Annual support", "Bluefield Logistics", "Sam", "Negotiation", 28000, 14),
      ("Brand refresh", "Cedar and Pine Studio", "Dana", "Qualified", 8500, 35),
      ("Booking system", "Maple Street Dental", "Lee", "Won", 15000, -10),
      ("Member app", "Orbit Fitness", "Sam", "Lead", 40000, 60),
      ("Online store", "Riverbend Farms", "Lee", "Proposal", 9800, 28),
      ("Print catalog", "Summit Print Co.", "Dana", "Lost", 6200, -20),
      ("Patient portal", "Lakeside Clinic", "Lee", "Qualified", 22000, 45),
    ]
    for (i, d) in deals.enumerated() {
      let r = 7 + i
      row(
        "A\(r)",
        [
          d.0, d.1, d.2, d.3, d.4,
          #"=IF(D\#(r)="","",XLOOKUP(D\#(r),$J$7:$J$12,$K$7:$K$12,0))"#,
          #"=IF(E\#(r)="","",E\#(r)*F\#(r))"#, Double(todaySerial + d.5),
        ],
        formats: [nil, nil, nil, nil, wholeMoney, percent, wholeMoney, date])
    }
    for r in 15...40 {
      row(
        "A\(r)",
        [
          nil, nil, nil, nil, nil,
          #"=IF(D\#(r)="","",XLOOKUP(D\#(r),$J$7:$J$12,$K$7:$K$12,0))"#,
          #"=IF(E\#(r)="","",E\#(r)*F\#(r))"#, nil,
        ],
        formats: [nil, nil, nil, nil, wholeMoney, percent, wholeMoney, date])
    }
    dropdown("D7:D40", ["Lead", "Qualified", "Proposal", "Negotiation", "Won", "Lost"])
    header("J6", ["Stage", "Chance"], rightAligned: [1])
    for (i, s) in [
      ("Lead", 0.1), ("Qualified", 0.25), ("Proposal", 0.5), ("Negotiation", 0.75), ("Won", 1.0),
      ("Lost", 0.0),
    ].enumerated() {
      row(
        "J\(7 + i)", [s.0, s.1],
        formats: [nil, CellFormat(fillColor: tint, numberFormat: .percent, formatCode: "0%")])
    }
    highlight("A7:H40", formula: #"=$D7="Won""#, .greenFill)
    highlight("A7:H40", formula: #"=$D7="Lost""#, Self.doneText)
    sheet.frozenRows = 6
    widths([140, 170, 70, 100, 90, 70, 90, 100, 24, 100, 70])
  }

  mutating func timesheet() {
    title("Timesheet", subtitle: "One week. Hours over 40 are paid at time and a half.")
    row("A3", ["Employee", "[Name]"], formats: [CellFormat(bold: true), nil])
    var weekFormat = date
    weekFormat.fillColor = tint
    row(
      "A4", ["Week starting", Double(mondaySerial)], formats: [CellFormat(bold: true), weekFormat])
    var rate = money
    rate.fillColor = tint
    row("A5", ["Hourly rate", 22.0], formats: [CellFormat(bold: true), rate])

    header(
      "A7", ["Day", "Date", "Start", "End", "Break (minutes)", "Hours"], rightAligned: [2, 3, 4, 5])
    let days: [(Double?, Double?, Double?)] = [
      (9.0 / 24, 17.5 / 24, 30), (8.5 / 24, 17.0 / 24, 30), (9.0 / 24, 18.0 / 24, 45),
      (9.0 / 24, 17.5 / 24, 30), (8.0 / 24, 16.0 / 24, 30), (nil, nil, nil), (nil, nil, nil),
    ]
    for (i, d) in days.enumerated() {
      let r = 8 + i
      let dateFormula = i == 0 ? "=B4" : "=B\(r - 1)+1"
      row(
        "A\(r)",
        [
          #"=TEXT(B\#(r),"dddd")"#, dateFormula, d.0, d.1, d.2,
          #"=IF(OR(C\#(r)="",D\#(r)=""),0,(D\#(r)-C\#(r))*24-E\#(r)/60)"#,
        ],
        formats: [nil, shortDate, time, time, nil, hours])
    }
    row(
      "A16", ["Total hours", nil, nil, nil, nil, "=SUM(F8:F14)"],
      formats: [totalLabel, totalLabel, totalLabel, totalLabel, totalLabel, total(hours)])
    row(
      "A17", ["Regular hours", nil, nil, nil, nil, "=MIN(F16,40)"],
      formats: [nil, nil, nil, nil, nil, hours])
    row(
      "A18", ["Overtime hours", nil, nil, nil, nil, "=MAX(F16-40,0)"],
      formats: [nil, nil, nil, nil, nil, hours])
    row(
      "A19", ["Pay", nil, nil, nil, nil, "=F17*B5+F18*B5*1.5"],
      formats: [CellFormat(bold: true), nil, nil, nil, nil, total(money)])
    widths([110, 110, 90, 90, 110, 80])
  }

  mutating func inventory() {
    title("Inventory", subtitle: "Items at or below their reorder level show in orange.")
    row(
      "A3",
      [
        "Items", "=COUNTA(B7:B60)", nil, "Stock value", "=SUM(H7:H60)", nil, "To reorder",
        #"=COUNTIF(I7:I60,"Reorder")"#,
      ],
      formats: [
        CellFormat(bold: true), nil, nil, CellFormat(bold: true), wholeMoney, nil,
        CellFormat(bold: true), nil,
      ])
    header(
      "A6",
      [
        "SKU", "Item", "Category", "In stock", "Reorder at", "Reorder qty", "Unit cost",
        "Stock value", "Status",
      ],
      rightAligned: [3, 4, 5, 6, 7])
    let items: [(String, String, String, Double, Double, Double, Double)] = [
      ("MUG-001", "Stoneware mug, white", "Kitchen", 48, 20, 60, 3.20),
      ("MUG-002", "Stoneware mug, blue", "Kitchen", 12, 20, 60, 3.20),
      ("TEA-010", "Loose leaf tea, 100 g", "Pantry", 85, 30, 100, 2.75),
      ("CND-004", "Soy candle, cedar", "Home", 9, 15, 40, 4.10),
      ("BAG-002", "Canvas tote", "Accessories", 64, 25, 50, 2.40),
      ("NTB-007", "Dot grid notebook", "Stationery", 30, 30, 80, 1.95),
      ("PEN-003", "Brass pen", "Stationery", 22, 10, 30, 6.50),
      ("TWL-001", "Linen tea towel", "Kitchen", 40, 15, 40, 3.60),
    ]
    for (i, it) in items.enumerated() {
      let r = 7 + i
      row(
        "A\(r)",
        [
          it.0, it.1, it.2, it.3, it.4, it.5, it.6, #"=IF(D\#(r)="","",D\#(r)*G\#(r))"#,
          #"=IF(B\#(r)="","",IF(D\#(r)<=E\#(r),"Reorder","OK"))"#,
        ],
        formats: [nil, nil, nil, nil, nil, nil, money, money, nil])
    }
    for r in 15...60 {
      row(
        "A\(r)",
        [
          nil, nil, nil, nil, nil, nil, nil, #"=IF(D\#(r)="","",D\#(r)*G\#(r))"#,
          #"=IF(B\#(r)="","",IF(D\#(r)<=E\#(r),"Reorder","OK"))"#,
        ],
        formats: [nil, nil, nil, nil, nil, nil, money, money, nil])
    }
    highlight("A7:I60", formula: #"=$I7="Reorder""#, .orangeFill)
    sheet.frozenRows = 6
    widths([80, 170, 100, 70, 80, 80, 80, 90, 80])
  }

  // MARK: Planning

  mutating func projectTracker() {
    title("Project Tracker", subtitle: "Late tasks show in red. Finished ones fade.")
    row(
      "A3",
      [
        "Tasks", "=COUNTA(A7:A50)", nil, "Done", #"=COUNTIF(C7:C50,"Done")"#, nil, "Complete",
        "=IF(B3=0,0,AVERAGE(G7:G50))",
      ],
      formats: [
        CellFormat(bold: true), nil, nil, CellFormat(bold: true), nil, nil, CellFormat(bold: true),
        percent,
      ])
    header(
      "A6", ["Task", "Owner", "Status", "Priority", "Start", "Due", "Progress", "Notes"],
      rightAligned: [6])
    let tasks: [(String, String, String, String, Int, Int, Double, String)] = [
      ("Agree scope and budget", "Dana", "Done", "High", -14, -10, 1, ""),
      ("Gather requirements", "Lee", "Done", "High", -10, -5, 1, ""),
      ("First design draft", "Sam", "In progress", "High", -5, 2, 0.6, "Review on Thursday"),
      ("Set up project site", "Lee", "In progress", "Medium", -3, -1, 0.8, ""),
      ("Write content", "Dana", "Not started", "Medium", 1, 8, 0, ""),
      ("Supplier quotes", "Sam", "Blocked", "Medium", -2, 4, 0.2, "Waiting on two replies"),
      ("Testing", "Lee", "Not started", "High", 8, 14, 0, ""),
      ("Launch", "Dana", "Not started", "High", 15, 15, 0, ""),
    ]
    for (i, t) in tasks.enumerated() {
      let r = 7 + i
      row(
        "A\(r)",
        [t.0, t.1, t.2, t.3, Double(todaySerial + t.4), Double(todaySerial + t.5), t.6, t.7],
        formats: [nil, nil, nil, nil, shortDate, shortDate, percent, nil])
    }
    for r in 15...50 {
      row(
        "A\(r)", [nil, nil, nil, nil, nil, nil, nil],
        formats: [nil, nil, nil, nil, shortDate, shortDate, percent])
    }
    dropdown("C7:C50", ["Not started", "In progress", "Blocked", "Done"])
    dropdown("D7:D50", ["High", "Medium", "Low"])
    highlight("A7:H50", formula: #"=$C7="Done""#, Self.doneText)
    highlight("C7:C50", formula: #"=$C7="Blocked""#, .redFill)
    highlight("F7:F50", formula: #"=AND($C7<>"Done",$F7<>"",$F7<TODAY())"#, Self.overdueText)
    sheet.frozenRows = 6
    widths([190, 70, 100, 70, 70, 70, 70, 200])
  }

  mutating func weeklySchedule() {
    title("Weekly Schedule", subtitle: "Change the week's start date to move the whole week.")
    var weekFormat = date
    weekFormat.fillColor = tint
    row(
      "A3", ["Week starting", Double(mondaySerial)], formats: [CellFormat(bold: true), weekFormat])
    header("A5", ["Time", "", "", "", "", "", "", ""])
    let dateHeader = CellFormat(
      bold: true, horizontalAlign: .center, textColor: Self.white,
      fillColor: color, numberFormat: .date, formatCode: "ddd mmm d")
    for d in 0..<7 {
      let col = A1Notation.columnLabel(for: 1 + d)
      put("\(col)5", d == 0 ? "=B3" : "=\(A1Notation.columnLabel(for: d))5+1", dateHeader)
    }
    var slot = 7.0
    var r = 6
    while slot < 21 {
      put(
        "A\(r)", slot / 24,
        CellFormat(textColor: Self.muted, numberFormat: .time, formatCode: "h:mm AM/PM"))
      slot += 0.5
      r += 1
    }
    let entry = CellFormat(fillColor: tint, wrapText: true)
    func slotRow(_ hour: Double) -> Int { 6 + Int((hour - 7) * 2) }
    for d in 0..<5 {
      put("\(A1Notation.columnLabel(for: 1 + d))\(slotRow(9))", "Team check-in", entry)
    }
    put("C\(slotRow(18))", "Gym", entry)
    put("E\(slotRow(18))", "Gym", entry)
    put("D\(slotRow(12.5))", "Lunch with Alex", entry)
    put("G\(slotRow(10))", "Grocery run", entry)
    put("H\(slotRow(11))", "Call family", entry)
    put("F\(slotRow(16))", "Plan next week", entry)
    sheet.frozenRows = 5
    widths([110, 110, 110, 110, 110, 110, 110, 110])
  }
}
