// spark-grid-mcp: a Model Context Protocol server that lets an AI assistant on this Mac (Claude
// Desktop, Cursor and others) read and change workbooks open in Spark Grid.
//
// It speaks MCP over standard input and output, one JSON-RPC message per line, and does its
// work by sending Spark Grid's AppleScript commands (SparkGrid.sdef) as Apple Events. Nothing goes over the
// network. The first time, macOS asks whether the assistant may control Spark Grid.
//
// It drives the app it ships in (SparkGridAppID in its embedded Info.plist), or the App Store
// app when built on its own. SPARK_GRID_APP_ID picks another copy.

import Foundation

let appID =
  ProcessInfo.processInfo.environment["SPARK_GRID_APP_ID"]
  ?? Bundle.main.object(forInfoDictionaryKey: "SparkGridAppID") as? String
  ?? "com.sparkbysam.SparkGrid"
let serverVersion = "1.0"

// MARK: - Apple Events

// The helper sends Spark Grid's commands as Apple Events by their codes (SparkGrid.sdef) rather
// than as AppleScript text: inside its sandbox it cannot read the app's scripting dictionary,
// which compiling AppleScript needs.

struct ScriptError: Error { let message: String }

func fourCharCode(_ text: String) -> FourCharCode {
  text.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) }
}

func textDescriptor(_ text: String) -> NSAppleEventDescriptor {
  NSAppleEventDescriptor(string: text)
}

/// A JSON value as the text a cell is typed with: numbers as numbers, true/false as TRUE/FALSE.
func cellText(_ value: Any) -> String {
  switch value {
  case let number as NSNumber:
    if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "TRUE" : "FALSE" }
    return number.stringValue
  case let text as String: return text
  case is NSNull: return ""
  default: return "\(value)"
  }
}

func listDescriptor(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
  let list = NSAppleEventDescriptor.list()
  for (index, item) in items.enumerated() { list.insert(item, at: index + 1) }
  return list
}

/// Sends `command` (an 8-letter sdef code) with its direct parameter and named parameters, and
/// gives back the result as JSON-ready values.
func send(
  _ command: String, direct: NSAppleEventDescriptor? = nil,
  _ parameters: [String: NSAppleEventDescriptor] = [:], workbook: [String: Any] = [:]
) throws -> Any {
  let event = NSAppleEventDescriptor(
    eventClass: fourCharCode(String(command.prefix(4))),
    eventID: fourCharCode(String(command.dropFirst(4))),
    targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: appID),
    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
  if let direct { event.setParam(direct, forKeyword: keyDirectObject) }
  var all = parameters
  if let name = workbook["workbook"] as? String, !name.isEmpty {
    all["SGwb"] = textDescriptor(name)
  }
  for (code, value) in all { event.setParam(value, forKeyword: fourCharCode(code)) }

  let reply: NSAppleEventDescriptor
  do {
    reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 120)
  } catch let error as NSError {
    throw ScriptError(message: describe(error.code, nil))
  }
  if let number = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, number != 0 {
    throw ScriptError(
      message: describe(Int(number), reply.paramDescriptor(forKeyword: keyErrorString)?.stringValue)
    )
  }
  return reply.paramDescriptor(forKeyword: keyDirectObject).map(plain) ?? NSNull()
}

func describe(_ number: Int, _ text: String?) -> String {
  switch number {
  case -1743:
    return "macOS has not let this assistant control Spark Grid. Turn it on in System Settings > "
      + "Privacy & Security > Automation."
  case -600, -609, -10661:
    return "Spark Grid is not open. Open it, then try again."
  case -1712:
    return "Spark Grid did not answer in time."
  default:
    return text ?? "Spark Grid could not do that (error \(number))."
  }
}

func plain(_ descriptor: NSAppleEventDescriptor) -> Any {
  if descriptor.descriptorType == typeAEList {
    guard descriptor.numberOfItems > 0 else { return [Any]() }
    return (1...descriptor.numberOfItems).map { descriptor.atIndex($0).map(plain) ?? NSNull() }
  }
  if descriptor.descriptorType == typeNull || descriptor.descriptorType == typeType
    || descriptor.descriptorType == 0
  {
    return NSNull()
  }
  return descriptor.stringValue ?? NSNull()
}

/// Inside the app the helper is sandboxed and can hand Spark Grid only files in Downloads.
let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

/// The person's real home folder (in the sandbox, NSHomeDirectory is the helper's container).
let homeFolder: String = {
  if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir { return String(cString: dir) }
  return NSHomeDirectory()
}()

/// A full path for `text`, with ~ as the real home folder.
func fullPath(_ text: String) throws -> String {
  var path = text
  if path == "~" || path.hasPrefix("~/") { path = homeFolder + path.dropFirst() }
  guard path.hasPrefix("/") else {
    throw ScriptError(message: "Give a full path, such as ~/Downloads/Report.pdf.")
  }
  path = (path as NSString).standardizingPath
  if sandboxed, !(path + "/").hasPrefix(homeFolder + "/Downloads/") {
    throw ScriptError(
      message: "Spark Grid's assistant connection can open and save files in Downloads only, "
        + "such as ~/Downloads/\((path as NSString).lastPathComponent). For a file elsewhere, "
        + "open it in Spark Grid first; then every tool works on it.")
  }
  return path
}

func fileDescriptor(_ path: String) -> NSAppleEventDescriptor {
  NSAppleEventDescriptor(fileURL: URL(fileURLWithPath: path))
}

// MARK: - Tools

struct Tool {
  let name: String
  let description: String
  let properties: [String: Any]
  let required: [String]
  let call: ([String: Any]) throws -> Any
}

let workbookProperty: [String: Any] = [
  "type": "string",
  "description":
    "The workbook's name, such as Budget.xlsx (see list_workbooks). The front window when left out.",
]

func text(_ args: [String: Any], _ key: String) throws -> String {
  guard let value = args[key] as? String, !value.isEmpty else {
    throw ScriptError(message: "\(key) is needed.")
  }
  return value
}

func optionalText(_ args: [String: Any], _ key: String) -> NSAppleEventDescriptor? {
  guard let value = args[key] as? String, !value.isEmpty else { return nil }
  return textDescriptor(value)
}

let tools: [Tool] = [
  Tool(
    name: "list_workbooks",
    description: "The names of the workbooks open in Spark Grid, front window first.",
    properties: [:], required: [],
    call: { _ in try send("SGrdWbNm") }),
  Tool(
    name: "list_sheets",
    description: "The names of a workbook's sheets, in tab order.",
    properties: ["workbook": workbookProperty], required: [],
    call: { args in try send("SGrdShNm", workbook: args) }),
  Tool(
    name: "used_range",
    description:
      "The range holding everything on a sheet, such as A1:F200; empty for an empty sheet. Use it before reading a whole sheet.",
    properties: [
      "sheet": ["type": "string", "description": "The sheet; the one showing when left out."],
      "workbook": workbookProperty,
    ], required: [],
    call: { args in
      var parameters: [String: NSAppleEventDescriptor] = [:]
      if let sheet = optionalText(args, "sheet") { parameters["SGsn"] = sheet }
      return try send("SGrdUsed", parameters, workbook: args)
    }),
  Tool(
    name: "read_range",
    description:
      "A range's values row by row, with formulas calculated. Shown as the cells show them ($1,200.50), or plain (1200.5, dates as serial numbers). Up to 200,000 cells.",
    properties: [
      "range": [
        "type": "string",
        "description":
          "Such as A1:C20, or 'Q1 Sales'!A1:C20 for another sheet (quote names with spaces).",
      ],
      "plain": ["type": "boolean", "description": "Values without their formats."],
      "workbook": workbookProperty,
    ], required: ["range"],
    call: { args in
      let reading = (args["plain"] as? Bool) == true ? "SGpl" : "SGsh"
      return try send(
        "SGrdRngV", direct: textDescriptor(try text(args, "range")),
        ["SGrc": NSAppleEventDescriptor(enumCode: fourCharCode(reading))], workbook: args)
    }),
  Tool(
    name: "read_formulas",
    description:
      "What is typed in each cell of a range, row by row: the formula, such as =SUM(B2:B9), or the value.",
    properties: [
      "range": ["type": "string", "description": "Such as A1:C20, or Sheet2!A1:C20."],
      "workbook": workbookProperty,
    ], required: ["range"],
    call: { args in
      try send("SGrdRngF", direct: textDescriptor(try text(args, "range")), workbook: args)
    }),
  Tool(
    name: "write_cells",
    description:
      "Put rows of values or formulas into cells starting at a cell, as typing them would (=SUM(B2:B9) is a formula, 10:30 a time). One Undo in Spark Grid takes them all back. Up to 200,000 cells.",
    properties: [
      "start_cell": [
        "type": "string", "description": "The top-left cell, such as A1, or Sheet2!A1.",
      ],
      "rows": [
        "type": "array",
        "description":
          "A list of rows, each a list of values: text, numbers, true/false, or formulas starting with =.",
        "items": ["type": "array", "items": [String: Any]()],
      ],
      "workbook": workbookProperty,
    ], required: ["start_cell", "rows"],
    call: { args in
      guard let rows = args["rows"] as? [Any], !rows.isEmpty else {
        throw ScriptError(message: "rows is needed: a list of rows, each a list of values.")
      }
      let block = rows.map { $0 as? [Any] ?? [$0] }
      let list = listDescriptor(
        block.map { row in listDescriptor(row.map { textDescriptor(cellText($0)) }) })
      _ = try send(
        "SGrdPutR", direct: list, ["SGcl": textDescriptor(try text(args, "start_cell"))],
        workbook: args)
      return "Wrote \(block.count) row\(block.count == 1 ? "" : "s")."
    }),
  Tool(
    name: "add_sheet",
    description: "Add a sheet at the end of a workbook and show it.",
    properties: [
      "name": [
        "type": "string", "description": "The new sheet's name; Sheet2 and so on when left out.",
      ],
      "workbook": workbookProperty,
    ], required: [],
    call: { args in try send("SGrdAddS", direct: optionalText(args, "name"), workbook: args) }),
  Tool(
    name: "save_workbook",
    description:
      "Save a workbook that already has a file. A new workbook must be saved once in Spark Grid first.",
    properties: ["workbook": workbookProperty], required: [],
    call: { args in
      _ = try send("SGrdSave", workbook: args)
      return "Saved."
    }),
  Tool(
    name: "open_workbook",
    description: "Open a spreadsheet, CSV or Numbers document in Spark Grid.",
    properties: [
      "path": [
        "type": "string",
        "description":
          "The file's full path. From the helper inside the app: a file in ~/Downloads.",
      ]
    ],
    required: ["path"],
    call: { args in
      let path = try fullPath(try text(args, "path"))
      _ = try send("aevtodoc", direct: listDescriptor([fileDescriptor(path)]))
      return "Opened \(path)."
    }),
  Tool(
    name: "export_workbook",
    description: "Save a PDF (the pages printing makes) or a CSV of one sheet to a file.",
    properties: [
      "path": [
        "type": "string",
        "description":
          "The file to write, such as ~/Downloads/Report.pdf (from the helper inside the app, Downloads only).",
      ],
      "format": ["type": "string", "enum": ["pdf", "csv"]],
      "sheet": ["type": "string", "description": "The sheet; the one showing when left out."],
      "every_sheet": ["type": "boolean", "description": "For a PDF: every sheet."],
      "workbook": workbookProperty,
    ], required: ["path", "format"],
    call: { args in
      let path = try fullPath(try text(args, "path"))
      let format = (args["format"] as? String)?.lowercased() == "csv" ? "SGcv" : "SGpd"
      var parameters: [String: NSAppleEventDescriptor] = [
        "SGto": fileDescriptor(path),
        "SGfm": NSAppleEventDescriptor(enumCode: fourCharCode(format)),
      ]
      if let sheet = optionalText(args, "sheet") { parameters["SGsn"] = sheet }
      if (args["every_sheet"] as? Bool) == true {
        parameters["SGev"] = NSAppleEventDescriptor(boolean: true)
      }
      _ = try send("SGrdExpt", parameters, workbook: args)
      return "Wrote \(path)."
    }),
]

// MARK: - JSON-RPC over standard input and output

func send(_ message: [String: Any]) {
  guard
    let data = try? JSONSerialization.data(
      withJSONObject: message, options: [.withoutEscapingSlashes]),
    let line = String(data: data, encoding: .utf8)
  else { return }
  FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func reply(_ id: Any, result: Any) { send(["jsonrpc": "2.0", "id": id, "result": result]) }

func reply(_ id: Any, error code: Int, _ message: String) {
  send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

func resultText(_ value: Any) -> String {
  if let text = value as? String { return text }
  if JSONSerialization.isValidJSONObject(value),
    let data = try? JSONSerialization.data(
      withJSONObject: value, options: [.withoutEscapingSlashes]),
    let text = String(data: data, encoding: .utf8)
  {
    return text
  }
  return "\(value)"
}

func handle(_ message: [String: Any]) {
  let method = message["method"] as? String ?? ""
  guard let id = message["id"] else { return }  // a notification: nothing to answer
  let params = message["params"] as? [String: Any] ?? [:]
  switch method {
  case "initialize":
    let version = params["protocolVersion"] as? String ?? "2025-06-18"
    reply(
      id,
      result: [
        "protocolVersion": version,
        "capabilities": ["tools": [String: Any]()],
        "serverInfo": ["name": "spark-grid", "version": serverVersion],
        "instructions":
          "Reads and changes workbooks open in Spark Grid on this Mac. Start with list_workbooks, then list_sheets and used_range before reading a whole sheet. Ranges are A1-style; quote sheet names with spaces ('Q1 Sales'!A1:C9).",
      ])
  case "ping":
    reply(id, result: [String: Any]())
  case "tools/list":
    reply(
      id,
      result: [
        "tools": tools.map { tool in
          [
            "name": tool.name, "description": tool.description,
            "inputSchema": [
              "type": "object", "properties": tool.properties, "required": tool.required,
            ],
          ] as [String: Any]
        }
      ])
  case "tools/call":
    let name = params["name"] as? String ?? ""
    let args = params["arguments"] as? [String: Any] ?? [:]
    guard let tool = tools.first(where: { $0.name == name }) else {
      reply(id, error: -32602, "No tool named \(name).")
      return
    }
    do {
      let value = try tool.call(args)
      reply(id, result: ["content": [["type": "text", "text": resultText(value)]]])
    } catch let failure as ScriptError {
      reply(id, result: ["content": [["type": "text", "text": failure.message]], "isError": true])
    } catch {
      reply(id, result: ["content": [["type": "text", "text": "\(error)"]], "isError": true])
    }
  default:
    reply(id, error: -32601, "Method not found: \(method)")
  }
}

while let line = readLine(strippingNewline: true) {
  guard !line.isEmpty, let data = line.data(using: .utf8),
    let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { continue }
  handle(message)
}
