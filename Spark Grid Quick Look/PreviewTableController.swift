import AppKit
import SparkGridCore

/// Editable NSTableView backed by a `PreviewSession`.
final class PreviewTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
  NSTextFieldDelegate
{
  let tableView = NSTableView()
  var session: PreviewSession?
  var onEdit: (() -> Void)?

  private let rowHeaderIdentifier = NSUserInterfaceItemIdentifier("rowHeader")
  private let cellIdentifier = NSUserInterfaceItemIdentifier("cell")

  override init() {
    super.init()
    tableView.style = .plain
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.allowsColumnReordering = false
    tableView.allowsColumnResizing = true
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = false
    tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
    tableView.rowHeight = 22
    tableView.intercellSpacing = NSSize(width: 1, height: 1)
    tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
    tableView.dataSource = self
    tableView.delegate = self
    tableView.headerView = NSTableHeaderView()
  }

  func reload() {
    rebuildColumns()
    tableView.reloadData()
  }

  private func rebuildColumns() {
    while tableView.tableColumns.count > 0 {
      tableView.removeTableColumn(tableView.tableColumns[0])
    }

    let rowColumn = NSTableColumn(identifier: rowHeaderIdentifier)
    rowColumn.title = ""
    rowColumn.width = 48
    rowColumn.minWidth = 40
    rowColumn.maxWidth = 72
    rowColumn.resizingMask = []
    tableView.addTableColumn(rowColumn)

    let columnCount = session?.previewColumnCount ?? 1
    for col in 0..<columnCount {
      let identifier = NSUserInterfaceItemIdentifier("col-\(col)")
      let column = NSTableColumn(identifier: identifier)
      column.title = A1Notation.columnLabel(for: col)
      column.width = 96
      column.minWidth = 56
      column.resizingMask = [.autoresizingMask, .userResizingMask]
      tableView.addTableColumn(column)
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int {
    session?.previewRowCount ?? 0
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard let tableColumn, let session else { return nil }

    if tableColumn.identifier == rowHeaderIdentifier {
      let field = reusedField(in: tableView, identifier: rowHeaderIdentifier)
      field.stringValue = "\(row + 1)"
      field.alignment = .right
      field.textColor = .secondaryLabelColor
      field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
      field.isEditable = false
      field.drawsBackground = true
      field.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65)
      field.delegate = nil
      field.tag = -1
      return field
    }

    guard let col = columnIndex(from: tableColumn.identifier) else { return nil }
    let field = reusedField(in: tableView, identifier: cellIdentifier)
    field.stringValue = session.displayValue(row: row, column: col)
    field.alignment = .left
    field.textColor = .labelColor
    field.font = .systemFont(ofSize: 12)
    field.isEditable = true
    field.drawsBackground = false
    field.delegate = self
    field.tag = encode(row: row, column: col)
    return field
  }

  private func reusedField(in tableView: NSTableView, identifier: NSUserInterfaceItemIdentifier)
    -> NSTextField
  {
    if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
      return existing
    }
    let field = NSTextField(string: "")
    field.identifier = identifier
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.backgroundColor = .clear
    field.lineBreakMode = .byTruncatingTail
    field.cell?.wraps = false
    field.cell?.isScrollable = true
    field.focusRingType = .default
    field.target = self
    field.action = #selector(cellEdited(_:))
    return field
  }

  private func columnIndex(from identifier: NSUserInterfaceItemIdentifier) -> Int? {
    let raw = identifier.rawValue
    guard raw.hasPrefix("col-") else { return nil }
    return Int(raw.dropFirst(4))
  }

  private func encode(row: Int, column: Int) -> Int {
    row * 100_000 + column
  }

  private func decode(tag: Int) -> (row: Int, column: Int)? {
    guard tag >= 0 else { return nil }
    return (tag / 100_000, tag % 100_000)
  }

  @objc private func cellEdited(_ sender: NSTextField) {
    commitEdit(from: sender)
  }

  func controlTextDidEndEditing(_ obj: Notification) {
    guard let field = obj.object as? NSTextField else { return }
    commitEdit(from: field)
  }

  private func commitEdit(from field: NSTextField) {
    guard let session, let coords = decode(tag: field.tag) else { return }
    session.setRawValue(field.stringValue, row: coords.row, column: coords.column)
    field.stringValue = session.displayValue(row: coords.row, column: coords.column)
    onEdit?()
  }
}
