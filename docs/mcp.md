# AI assistants (MCP)

`spark-grid-mcp` lets an AI assistant on your Mac, such as Claude Desktop or Cursor, read and change workbooks open in Spark Grid. It speaks the Model Context Protocol over standard input and output, and does its work through Spark Grid's AppleScript commands (`Spark Grid/SparkGrid.sdef`). Nothing goes over the network; the app itself still never uses it.

## Where it lives

The app carries it at `Spark Grid.app/Contents/Helpers/spark-grid-mcp`. The Xcode build phase "Embed MCP Helper" (`scripts/embed-mcp-helper.sh`) compiles it with `swiftc` for each architecture and signs it with its own entitlements (`MCP Helper/`): an assistant starts it, not the app, so it cannot inherit the app's sandbox. It may send Apple Events only to the app it ships in, and read and write only in Downloads. Settings › AI copies the lines below with the real path filled in.

Because of its sandbox, it sends Spark Grid's commands as raw Apple Events by their codes; it cannot read the app's scripting dictionary, which compiling AppleScript text needs.

For development, `cd Packages/SparkGridCore && swift build --product spark-grid-mcp` builds an unsandboxed copy with no Downloads limit.

## Connect an assistant

Claude Desktop (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{ "mcpServers": { "spark-grid": { "command": "/Applications/Spark Grid.app/Contents/Helpers/spark-grid-mcp" } } }
```

Claude Code: `claude mcp add spark-grid "/Applications/Spark Grid.app/Contents/Helpers/spark-grid-mcp"`. Cursor and others take the same command.

The first time a tool runs, macOS asks whether the assistant may control Spark Grid. If that was refused, turn it on in System Settings > Privacy & Security > Automation.

`SPARK_GRID_APP_ID` points the helper at another copy of the app, for example `com.sparkbysam.SparkGrid.scripttest` for the test build.

## Tools

| Tool | Does |
|---|---|
| `list_workbooks` | Open workbooks, front first |
| `list_sheets` | A workbook's sheets in tab order |
| `used_range` | The range holding everything on a sheet |
| `read_range` | Values row by row, as shown or plain |
| `read_formulas` | What is typed in each cell |
| `write_cells` | Rows of values or formulas from a start cell; one Undo |
| `add_sheet` | A new sheet at the end |
| `save_workbook` | Save a workbook that has a file |
| `open_workbook` | Open a file |
| `export_workbook` | PDF or CSV to a file |

The helper inside the app opens and exports files in `~/Downloads` only; for a file elsewhere, open it in Spark Grid and every other tool works on it.

Every tool takes an optional `workbook` (its window name); without it, the front window. Ranges are A1-style, with `'Sheet Name'!A1:C9` for another sheet. Reads and writes stop at 200,000 cells.

## AppleScript added for it (Nov 18, 2026)

`sheet names`, `range values` (reading shown or plain), `range formulas`, `put values … into cell`, `used range`, `add sheet`.
