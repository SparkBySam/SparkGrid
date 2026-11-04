# App Store screenshots

For App Store Connect → your Mac app version → **Screenshots**. Made for 1.3 (November 2026).

## Apple requirements (met)

| Requirement | Status |
|-------------|--------|
| Size | **2880 × 1800** (accepted Mac size) |
| Aspect | **16:10** |
| Format | JPEG, quality 95, full color (4:4:4), **RGB, no alpha**. Under 1 MB each, the repo's limit. Lossless PNG masters are kept outside the repo. |
| Count | 1–10 (we have **9**) |

## Upload these (in order)

1. `01-pipeline` — a formatted pipeline sheet: money and percents, data bars, a highlight rule, dropdowns, a comment, a formula in the formula bar
2. `02-charts` — color scale heat map and two charts from the file
3. `03-edit-chart` — Edit Chart
4. `04-duplicate-highlights` — Find Duplicates, repeated rows shaded
5. `05-table` — a styled table with traffic-light icons
6. `06-settings` — Settings → Shortcuts
7. `07-pipeline-light` — the pipeline sheet in light mode
8. `08-charts-light` — the charts sheet in light mode
9. `09-chart-panel-light` — a selected chart with its handles, and the Charts panel

## How they are made

Everything in them is made up. `source/make_showcase_workbook.py` builds the workbook (run with an interpreter that has openpyxl). Each window is captured without its shadow (`screencapture -x -o -l WINDOW_ID`) from a test build with its own bundle ID, opened with `open -g -n`, at a 1476 × 900 point window.

- `source/compose.py RAW.png OUT.png` puts a capture on the dark backdrop at 2880 × 1800 with a soft shadow (saved as PNG; convert to JPEG quality 95 with 4:4:4 color for the repo). The test window is behind other windows while it is captured, so its close, minimize and zoom buttons are grey; the script draws them in their normal colors. `--keep-buttons` leaves them grey (for a window behind Settings).
- `source/overlay.py MAIN.png PANEL.png DX DY OUT.png` lays a second window (Settings) over the main capture.

## Do not upload

- Website images under `web/images/` (wrong size / have alpha)
