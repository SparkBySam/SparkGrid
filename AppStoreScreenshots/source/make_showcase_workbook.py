"""Builds the made-up workbook used for App Store screenshots and previews.

Run with an interpreter that has openpyxl:
    /usr/bin/python3 make_showcase_workbook.py OUT.xlsx

Every name, company and number here is invented.
"""

import random
import sys

from openpyxl import Workbook
from openpyxl.chart import BarChart, LineChart, Reference
from openpyxl.formatting.rule import (
    ColorScaleRule,
    DataBarRule,
    FormulaRule,
    IconSetRule,
)
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.table import Table, TableStyleInfo
from openpyxl.comments import Comment

random.seed(13)

TITLE = Font(name="Helvetica Neue", size=18, bold=True)
SUB = Font(name="Helvetica Neue", size=11, color="FF8A8F98")
HEAD = Font(name="Helvetica Neue", size=12, bold=True)
BOLD = Font(name="Helvetica Neue", size=12, bold=True)
BODY = Font(name="Helvetica Neue", size=12)
HEAD_FILL = PatternFill("solid", fgColor="FFF3E6CF")
TOTAL_FILL = PatternFill("solid", fgColor="FFEFEFEF")
RULE = Side(style="thin", color="FFB8B8B8")
MONEY = '"$"#,##0'
PCT = "0%"

wb = Workbook()

# --- Pipeline -------------------------------------------------------------
ws = wb.active
ws.title = "Pipeline"
ws.sheet_properties.tabColor = "E0A24A"
ws["A1"] = "Q3 Pipeline"
ws["A1"].font = TITLE
ws["A2"] = "Updated November 4 · All figures in USD"
ws["A2"].font = SUB
headers = ["Account", "Owner", "Stage", "ARR", "Close %", "Weighted", "Region", "Next step"]
for col, text in enumerate(headers, start=1):
    c = ws.cell(row=4, column=col, value=text)
    c.font = HEAD
    c.fill = HEAD_FILL
    c.border = Border(bottom=RULE)
deals = [
    ("Northwind Freight", "Alex Rivera", "Negotiation", 186000, 0.70, "Midwest", "Send redlines"),
    ("Harbor & Pine", "Jordan Lee", "Proposal", 92000, 0.45, "Northeast", "Finance demo"),
    ("Cedar Peak Health", "Priya Shah", "Discovery", 240000, 0.25, "West", "Security review"),
    ("Blue Ridge Outfitters", "Casey Ng", "Closed Won", 134000, 1.00, "Southeast", "Kickoff call"),
    ("Atlas Grain Co.", "Alex Rivera", "Proposal", 157500, 0.55, "Midwest", "Pricing revision"),
    ("Lumen Studio Works", "Jordan Lee", "Negotiation", 78000, 0.65, "West", "Legal review"),
    ("Pinecone Kitchens", "Casey Ng", "Discovery", 61000, 0.20, "Northeast", "Needs assessment"),
    ("Summit Ridge Labs", "Priya Shah", "Closed Won", 210000, 1.00, "West", "Onboarding"),
    ("Riverbend Credit Union", "Alex Rivera", "Proposal", 305000, 0.40, "Midwest", "Exec sponsor"),
    ("Oak & Anvil", "Jordan Lee", "Negotiation", 99000, 0.75, "Southeast", "Final quote"),
    ("Brightfield Solar", "Casey Ng", "Discovery", 88000, 0.15, "West", "Intro call"),
    ("Metro Smile Dental", "Priya Shah", "Proposal", 112000, 0.50, "Northeast", "ROI worksheet"),
    ("Granite Bay Hotels", "Alex Rivera", "Negotiation", 174000, 0.80, "West", "Contract draft"),
    ("Willow Lane Schools", "Jordan Lee", "Proposal", 66000, 0.35, "Midwest", "Board meeting"),
    ("Copperline Media", "Casey Ng", "Closed Won", 143000, 1.00, "Northeast", "Invoice sent"),
    ("Fernwood Clinics", "Priya Shah", "Discovery", 127000, 0.30, "Southeast", "Site visit"),
]
first = 5
for i, (acct, owner, stage, arr, pct, region, step) in enumerate(deals):
    r = first + i
    ws.cell(row=r, column=1, value=acct)
    ws.cell(row=r, column=2, value=owner)
    ws.cell(row=r, column=3, value=stage)
    ws.cell(row=r, column=4, value=arr).number_format = MONEY
    ws.cell(row=r, column=5, value=pct).number_format = PCT
    ws.cell(row=r, column=6, value=f"=D{r}*E{r}").number_format = MONEY
    ws.cell(row=r, column=7, value=region)
    ws.cell(row=r, column=8, value=step)
    for col in range(1, 9):
        ws.cell(row=r, column=col).font = BODY
last = first + len(deals) - 1
total = last + 1
ws.cell(row=total, column=1, value="Total").font = BOLD
ws.cell(row=total, column=4, value=f"=SUM(D{first}:D{last})").number_format = MONEY
ws.cell(row=total, column=5, value=f"=F{total}/D{total}").number_format = PCT
ws.cell(row=total, column=6, value=f"=SUM(F{first}:F{last})").number_format = MONEY
for col in range(1, 9):
    c = ws.cell(row=total, column=col)
    c.fill = TOTAL_FILL
    c.font = BOLD
    c.border = Border(top=RULE)

# Summary block to the right.
ws["J4"] = "Summary"
ws["J4"].font = HEAD
summary = [
    ("Open deals", f'=COUNTIFS(C{first}:C{last},"<>Closed Won")', "0"),
    ("Won ARR", f'=SUMIFS(D{first}:D{last},C{first}:C{last},"Closed Won")', MONEY),
    ("Weighted pipeline", f"=F{total}", MONEY),
    ("Average deal", f"=AVERAGE(D{first}:D{last})", MONEY),
    ("Largest deal", f"=MAX(D{first}:D{last})", MONEY),
    ("Top account", f"=XLOOKUP(MAX(D{first}:D{last}),D{first}:D{last},A{first}:A{last})", "General"),
]
for i, (label, formula, fmt) in enumerate(summary):
    ws.cell(row=5 + i, column=10, value=label).font = BODY
    c = ws.cell(row=5 + i, column=11, value=formula)
    c.number_format = fmt
    c.font = BOLD

ws.conditional_formatting.add(
    f"E{first}:E{last}", DataBarRule(start_type="num", start_value=0, end_type="num", end_value=1, color="E0A24A")
)
ws.conditional_formatting.add(
    f"C{first}:C{last}",
    FormulaRule(formula=[f'C{first}="Closed Won"'], fill=PatternFill("solid", bgColor="FFCDEBD0")),
)
stages = DataValidation(type="list", formula1='"Discovery,Proposal,Negotiation,Closed Won,Closed Lost"', allow_blank=True)
ws.add_data_validation(stages)
stages.add(f"C{first}:C{last}")
ws["H7"].comment = Comment("Security team wants the SOC 2 report before the call.", "Priya Shah")
ws.auto_filter.ref = f"A4:H{last}"
ws.freeze_panes = "A5"
widths = {"A": 26, "B": 14, "C": 14, "D": 12, "E": 10, "F": 12, "G": 12, "H": 20, "I": 3, "J": 18, "K": 22}
for col, w in widths.items():
    ws.column_dimensions[col].width = w

# --- Monthly --------------------------------------------------------------
mo = wb.create_sheet("Monthly")
mo.sheet_properties.tabColor = "3E7CB1"
mo["A1"] = "Revenue by region"
mo["A1"].font = TITLE
mo["A2"] = "Thousands of dollars"
mo["A2"].font = SUB
months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
regions = ["Northeast", "Southeast", "Midwest", "West"]
mo.cell(row=4, column=1, value="Region").font = HEAD
for j, m in enumerate(months):
    c = mo.cell(row=4, column=2 + j, value=m)
    c.font = HEAD
mo.cell(row=4, column=14, value="Total").font = HEAD
base = {"Northeast": 120, "Southeast": 90, "Midwest": 105, "West": 150}
for i, region in enumerate(regions):
    r = 5 + i
    mo.cell(row=r, column=1, value=region).font = BODY
    level = base[region]
    for j in range(12):
        level = level * (1 + random.uniform(-0.04, 0.09))
        mo.cell(row=r, column=2 + j, value=round(level)).font = BODY
    mo.cell(row=r, column=14, value=f"=SUM(B{r}:M{r})").font = BOLD
mo.cell(row=9, column=1, value="Total").font = BOLD
for j in range(13):
    col = chr(ord("B") + j)
    mo.cell(row=9, column=2 + j, value=f"=SUM({col}5:{col}8)").font = BOLD
mo.conditional_formatting.add(
    "B5:M8", ColorScaleRule(start_type="min", start_color="FFFFFFFF", end_type="max", end_color="FF3E7CB1")
)
mo.column_dimensions["A"].width = 14
for j in range(14):
    mo.column_dimensions[chr(ord("B") + j)].width = 8

bar = BarChart()
bar.type = "col"
bar.grouping = "clustered"
bar.title = "Revenue by region"
bar.y_axis.title = "$K"
data = Reference(mo, min_col=2, max_col=13, min_row=4, max_row=8)
bar.add_data(Reference(mo, min_col=1, max_col=13, min_row=5, max_row=8), from_rows=True, titles_from_data=True)
bar.set_categories(Reference(mo, min_col=2, max_col=13, min_row=4, max_row=4))
bar.height = 8
bar.width = 18
mo.add_chart(bar, "B12")

line = LineChart()
line.title = "Monthly total"
line.add_data(Reference(mo, min_col=1, max_col=13, min_row=9, max_row=9), from_rows=True, titles_from_data=True)
line.set_categories(Reference(mo, min_col=2, max_col=13, min_row=4, max_row=4))
line.height = 8
line.width = 14
mo.add_chart(line, "L12")

# --- Leads (duplicates) ---------------------------------------------------
le = wb.create_sheet("Leads")
le.sheet_properties.tabColor = "6FAE47"
le["A1"] = "Event sign-ups"
le["A1"].font = TITLE
le["A2"] = "Merged from three forms"
le["A2"].font = SUB
for col, text in enumerate(["Name", "Email", "Company", "Form", "Date"], start=1):
    c = le.cell(row=4, column=col, value=text)
    c.font = HEAD
    c.fill = HEAD_FILL
people = [
    ("Maya Torres", "maya@harborpine.test", "Harbor & Pine"),
    ("Leo Fischer", "leo@atlasgrain.test", "Atlas Grain Co."),
    ("Nina Okafor", "nina@lumenworks.test", "Lumen Studio Works"),
    ("Sam Whitlock", "sam@oakanvil.test", "Oak & Anvil"),
    ("Iris Bauer", "iris@cedarpeak.test", "Cedar Peak Health"),
    ("Theo Grant", "theo@brightfield.test", "Brightfield Solar"),
    ("Ruby Chen", "ruby@copperline.test", "Copperline Media"),
    ("Omar Haddad", "omar@granitebay.test", "Granite Bay Hotels"),
    ("Ada Lindqvist", "ada@fernwood.test", "Fernwood Clinics"),
    ("Jonah Price", "jonah@willowlane.test", "Willow Lane Schools"),
]
rows = []
for p in people:
    rows.append(p + ("Web",))
for p in [people[1], people[4], people[6], people[8]]:
    rows.append(p + ("Booth",))
for p in [people[1], people[3]]:
    rows.append(p + ("Email",))
random.shuffle(rows)
for i, (name, email, company, form) in enumerate(rows):
    r = 5 + i
    le.cell(row=r, column=1, value=name).font = BODY
    le.cell(row=r, column=2, value=email).font = BODY
    le.cell(row=r, column=3, value=company).font = BODY
    le.cell(row=r, column=4, value=form).font = BODY
    c = le.cell(row=r, column=5, value=f"=DATE(2026,10,{1 + i})")
    c.number_format = "mmm d"
    c.font = BODY
for col, w in {"A": 18, "B": 26, "C": 22, "D": 10, "E": 10}.items():
    le.column_dimensions[col].width = w

# --- Budget (table) -------------------------------------------------------
bu = wb.create_sheet("Budget")
bu.sheet_properties.tabColor = "8E6BBF"
bu["A1"] = "Team budget"
bu["A1"].font = TITLE
bu["A2"] = "Fiscal year 2027"
bu["A2"].font = SUB
cols = ["Line item", "Category", "Q1", "Q2", "Q3", "Q4", "Year", "Status"]
for col, text in enumerate(cols, start=1):
    bu.cell(row=4, column=col, value=text).font = BODY
items = [
    ("Design tools", "Software", 1200, 1200, 1300, 1300),
    ("Cloud hosting", "Software", 4200, 4400, 4700, 5100),
    ("Conference travel", "Travel", 0, 6500, 0, 4800),
    ("Team offsite", "Events", 0, 0, 9000, 0),
    ("Laptops", "Hardware", 7800, 0, 2600, 0),
    ("Contract writing", "Services", 2500, 2500, 3000, 3000),
    ("Customer research", "Services", 1800, 0, 1800, 0),
    ("Training", "People", 900, 900, 900, 900),
    ("Office supplies", "Office", 300, 250, 300, 350),
    ("Ads", "Marketing", 3000, 3500, 4000, 5500),
]
for i, (name, cat, *qs) in enumerate(items):
    r = 5 + i
    bu.cell(row=r, column=1, value=name)
    bu.cell(row=r, column=2, value=cat)
    for j, q in enumerate(qs):
        bu.cell(row=r, column=3 + j, value=q).number_format = MONEY
    bu.cell(row=r, column=7, value=f"=SUM(C{r}:F{r})").number_format = MONEY
    bu.cell(row=r, column=8, value=f'=IF(G{r}>10000,"Review","OK")')
    for col in range(1, 9):
        bu.cell(row=r, column=col).font = BODY
end = 4 + len(items)
table = Table(displayName="Budget2027", ref=f"A4:H{end}")
table.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
bu.add_table(table)
bu.conditional_formatting.add(
    f"G5:G{end}",
    IconSetRule("3TrafficLights1", "num", [0, 5000, 10000], reverse=True),
)
for col, w in {"A": 20, "B": 12, "C": 10, "D": 10, "E": 10, "F": 10, "G": 11, "H": 10}.items():
    bu.column_dimensions[col].width = w

wb.save(sys.argv[1])
print("wrote", sys.argv[1])
