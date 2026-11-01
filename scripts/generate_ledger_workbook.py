#!/usr/bin/env python3
"""Deterministic large workbook, different in shape from the reference file.

One 50,000-row ledger, a VLOOKUP sheet, an INDEX/MATCH sheet, a SUMIFS
summary by category and month, a long single-column dependency chain, and
cross-sheet references in both directions. The ledger carries conditional
formatting over the full amount and note columns, and the note column is
wrapped text.

No randomness. The same invocation always writes the same bytes.
"""

from __future__ import annotations

import argparse
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

LEDGER_ROWS = 50_000
LOOKUP_ROWS = 500
# The evaluator recurses once per link and overflows the main thread stack
# near 1,800 frames. 500 links is still a long chain and stays paintable.
CHAIN_ROWS = 500
CATEGORIES = (
    "Tools",
    "Travel",
    "Payroll",
    "Software",
    "Rent",
    "Meals",
    "Shipping",
    "Hardware",
    "Services",
    "Taxes",
    "Utilities",
    "Supplies",
)

NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS_PKG = "http://schemas.openxmlformats.org/package/2006/relationships"
NS_CT = "http://schemas.openxmlformats.org/package/2006/content-types"


def amount_for(index: int) -> int:
    """1-based ledger row index. Stable integer so sums do not depend on binary floats."""
    return ((index * 17) % 4000) + (index % 13)


def category_for(index: int) -> str:
    return CATEGORIES[(index - 1) % len(CATEGORIES)]


def month_for(index: int) -> int:
    return ((index - 1) % 12) + 1


def note_for(index: int) -> str:
    category = category_for(index)
    month = month_for(index)
    return (
        f"Note {index} {category} month {month}. "
        "This text is wrapped across the column so the row is taller than one line."
    )


def inline(cell_ref: str, text: str, style: int | None = None) -> str:
    style_attr = f' s="{style}"' if style else ""
    return f'<c r="{cell_ref}"{style_attr} t="inlineStr"><is><t>{escape(text)}</t></is></c>'


def number(cell_ref: str, value: int) -> str:
    return f'<c r="{cell_ref}"><v>{value}</v></c>'


def formula(cell_ref: str, body: str) -> str:
    return f'<c r="{cell_ref}"><f>{escape(body)}</f></c>'


def content_types() -> str:
    overrides = [
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
        '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>',
    ]
    for index in range(1, 6):
        overrides.append(
            f'<Override PartName="/xl/worksheets/sheet{index}.xml" '
            'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        )
    body = "\n".join(overrides)
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="{NS_CT}">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
{body}
</Types>
"""


def root_rels() -> str:
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="{NS_PKG}">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
"""


def workbook_xml() -> str:
    names = ("Ledger", "VLOOKUP", "IndexMatch", "Summary", "Chain")
    sheets = "".join(
        f'<sheet name="{name}" sheetId="{index}" r:id="rId{index}"/>'
        for index, name in enumerate(names, start=1)
    )
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="{NS_MAIN}" xmlns:r="{NS_REL}">
<sheets>{sheets}</sheets>
</workbook>
"""


def workbook_rels() -> str:
    rels = []
    for index in range(1, 6):
        rels.append(
            f'<Relationship Id="rId{index}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            f'Target="worksheets/sheet{index}.xml"/>'
        )
    rels.append(
        '<Relationship Id="rId6" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    )
    rels.append(
        '<Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
    )
    body = "".join(rels)
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="{NS_PKG}">
{body}
</Relationships>
"""


def styles_xml() -> str:
    # Match the app exporter's stylesheet shape. A dxf without numFmtId/fontId
    # makes CoreXLSX reject the whole stylesheet, and then no cell style loads.
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="{NS_MAIN}">
<numFmts count="0"></numFmts>
<fonts count="2">
<font><sz val="12"/><name val="Helvetica Neue"/></font>
<font><sz val="12"/><name val="Helvetica Neue"/></font>
</fonts>
<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellStyleXfs>
<cellXfs count="2">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="0" applyAlignment="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyFill="1" applyBorder="0" applyAlignment="1" applyNumberFormat="1"><alignment wrapText="1"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
<dxfs count="1"><dxf numFmtId="0" fontId="0" fillId="0" borderId="0"><fill><patternFill patternType="solid"><fgColor rgb="FFFFC7CE"/><bgColor indexed="64"/></patternFill></fill></dxf></dxfs>
<tableStyles count="0" defaultTableStyle="TableStyleMedium9" defaultPivotStyle="PivotStyleLight16"/>
</styleSheet>
"""


def shared_strings_xml() -> str:
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="{NS_MAIN}" count="0" uniqueCount="0"/>
"""


def worksheet_shell(body: str, cols: str = "", extra: str = "") -> str:
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="{NS_MAIN}" xmlns:r="{NS_REL}">
{cols}<sheetData>
{body}</sheetData>
{extra}</worksheet>
"""


def ledger_sheet() -> str:
    rows = ['<row r="1">' + "".join([
        inline("A1", "ID"),
        inline("B1", "Category"),
        inline("C1", "Month"),
        inline("D1", "Amount"),
        inline("E1", "Note"),
        inline("F1", "Status"),
        inline("G1", "Backref"),
    ]) + "</row>"]
    last = LEDGER_ROWS + 1
    for index in range(1, LEDGER_ROWS + 1):
        excel_row = index + 1
        height = ' ht="36" customHeight="1"' if index <= 3 else ""
        cells = [
            inline(f"A{excel_row}", f"L{index:06d}"),
            inline(f"B{excel_row}", category_for(index)),
            number(f"C{excel_row}", month_for(index)),
            number(f"D{excel_row}", amount_for(index)),
            inline(f"E{excel_row}", note_for(index), style=1),
            inline(f"F{excel_row}", "Closed" if index % 5 == 0 else "Open"),
        ]
        if index == 1:
            cells.append(formula(f"G{excel_row}", "Summary!B2"))
        rows.append(f'<row r="{excel_row}"{height}>{"".join(cells)}</row>')
    cols = '<cols><col min="5" max="5" width="18" customWidth="1"/></cols>'
    extra = f"""<conditionalFormatting sqref="D2:D{last}">
<cfRule type="cellIs" dxfId="0" priority="1" operator="greaterThan"><formula>2500</formula></cfRule>
<cfRule type="colorScale" priority="2"><colorScale><cfvo type="min"/><cfvo type="max"/><color rgb="FFF8696B"/><color rgb="FF63BE7B"/></colorScale></cfRule>
</conditionalFormatting>
<conditionalFormatting sqref="E2:E{last}">
<cfRule type="containsText" dxfId="0" priority="3" operator="containsText" text="wrapped"><formula>NOT(ISERROR(SEARCH("wrapped",E2)))</formula></cfRule>
</conditionalFormatting>
"""
    return worksheet_shell("\n".join(rows) + "\n", cols=cols, extra=extra)


def lookup_sheet(function_name: str, formula_body) -> str:
    rows = ['<row r="1">' + inline("A1", "Key") + inline("B1", "Amount") + "</row>"]
    for slot in range(LOOKUP_ROWS):
        index = 1 + slot * (LEDGER_ROWS // LOOKUP_ROWS)
        excel_row = slot + 2
        rows.append(
            f'<row r="{excel_row}">'
            + inline(f"A{excel_row}", f"L{index:06d}")
            + formula(f"B{excel_row}", formula_body(excel_row))
            + "</row>"
        )
    return worksheet_shell("\n".join(rows) + "\n")


def vlookup_formula(excel_row: int) -> str:
    return f"VLOOKUP(A{excel_row},Ledger!$A$2:$D${LEDGER_ROWS + 1},4,FALSE)"


def index_match_formula(excel_row: int) -> str:
    last = LEDGER_ROWS + 1
    return (
        f"INDEX(Ledger!$D$2:$D${last},MATCH(A{excel_row},Ledger!$A$2:$A${last},0))"
    )


def summary_sheet() -> str:
    header = [inline("A1", "Category")]
    for month in range(1, 13):
        column = chr(ord("A") + month)
        header.append(number(f"{column}1", month))
    rows = ['<row r="1">' + "".join(header) + "</row>"]
    last = LEDGER_ROWS + 1
    for index, category in enumerate(CATEGORIES):
        excel_row = index + 2
        cells = [inline(f"A{excel_row}", category)]
        for month in range(1, 13):
            column = chr(ord("A") + month)
            body = (
                f"SUMIFS(Ledger!$D$2:$D${last},Ledger!$B$2:$B${last},$A{excel_row},"
                f"Ledger!$C$2:$C${last},{column}$1)"
            )
            cells.append(formula(f"{column}{excel_row}", body))
        rows.append(f'<row r="{excel_row}">{"".join(cells)}</row>')
    rows.append('<row r="20">' + formula("A20", f"Chain!A{CHAIN_ROWS}") + "</row>")
    return worksheet_shell("\n".join(rows) + "\n")


def chain_sheet() -> str:
    rows = ['<row r="1">' + number("A1", 1) + formula("B1", "Ledger!D2") + "</row>"]
    for excel_row in range(2, CHAIN_ROWS + 1):
        rows.append(
            f'<row r="{excel_row}">' + formula(f"A{excel_row}", f"A{excel_row - 1}+1") + "</row>"
        )
    return worksheet_shell("\n".join(rows) + "\n")


def category_sums() -> list[int]:
    """SUMIFS totals for each category. Category and month are lockstep, so only one month is nonzero."""
    totals = [0] * len(CATEGORIES)
    for index in range(1, LEDGER_ROWS + 1):
        totals[(index - 1) % len(CATEGORIES)] += amount_for(index)
    return totals


def write_answers(path: Path) -> None:
    """Python-computed formula results. These are the ledger ground truth, not engine output."""
    totals = category_sums()
    lines = [
        "# Python-computed formula results for the synthetic ledger.",
        "# Not Spark Grid output. Tokens: n:<number> s:<text> b:TRUE e:#N/A blank",
    ]
    lines.append(f"Ledger!G2\tn:{totals[0]}")
    for slot in range(LOOKUP_ROWS):
        index = 1 + slot * (LEDGER_ROWS // LOOKUP_ROWS)
        excel_row = slot + 2
        amount = amount_for(index)
        lines.append(f"VLOOKUP!B{excel_row}\tn:{amount}")
        lines.append(f"IndexMatch!B{excel_row}\tn:{amount}")
    for index in range(len(CATEGORIES)):
        excel_row = index + 2
        for month in range(1, 13):
            column = chr(ord("A") + month)
            value = totals[index] if month == index + 1 else 0
            lines.append(f"Summary!{column}{excel_row}\tn:{value}")
    lines.append(f"Summary!A20\tn:{CHAIN_ROWS}")
    lines.append(f"Chain!B1\tn:{amount_for(1)}")
    for excel_row in range(2, CHAIN_ROWS + 1):
        lines.append(f"Chain!A{excel_row}\tn:{excel_row}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_workbook(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sheets = {
        "xl/worksheets/sheet1.xml": ledger_sheet(),
        "xl/worksheets/sheet2.xml": lookup_sheet("VLOOKUP", vlookup_formula),
        "xl/worksheets/sheet3.xml": lookup_sheet("INDEX", index_match_formula),
        "xl/worksheets/sheet4.xml": summary_sheet(),
        "xl/worksheets/sheet5.xml": chain_sheet(),
    }
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", content_types())
        archive.writestr("_rels/.rels", root_rels())
        archive.writestr("xl/workbook.xml", workbook_xml())
        archive.writestr("xl/_rels/workbook.xml.rels", workbook_rels())
        archive.writestr("xl/styles.xml", styles_xml())
        archive.writestr("xl/sharedStrings.xml", shared_strings_xml())
        for name, xml in sheets.items():
            archive.writestr(name, xml)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-o", "--output", required=True, type=Path)
    parser.add_argument(
        "--answers",
        type=Path,
        help="Write Python-computed formula results. Do not point this at the repo.",
    )
    args = parser.parse_args()
    write_workbook(args.output)
    if args.answers is not None:
        write_answers(args.answers)
    print(
        f"wrote {args.output} ledger_rows={LEDGER_ROWS} "
        f"lookups={LOOKUP_ROWS} chain={CHAIN_ROWS}"
    )


if __name__ == "__main__":
    main()
