# Gaps

Pick the top item that belongs to the current phase in `docs/STATUS.md`. Do not start a later phase early.

## This phase

Workflow gates W1–W8 are done. Correct answers is the next phase and is not started.

## Later, in order

1. Correct answers. Range reads must use calculated precedents. `TEXT` must follow the format code. Long formula chains must evaluate iteratively. Nov 18 (1.5): TEXT and cell formats match Excel in 480 cells, and long chains calculate in linear time; see `docs/STATUS.md`. The only known saved-result exception today is the malformed formula recorded in `corpus/known-differences.md`. Do not special-case that cell in the engine.
2. Typed entries other apps read differently (found by script, Nov 18; checked against Excel 16.115): `'007` should keep the text 007 and hide the apostrophe (Excel saves it as a quote prefix); `3/4` and `15-Mar` become dates in the current year; `1 1/2` becomes 1.5 shown as a fraction; a typed `#N/A` is an error value, not text; `=SUM(N1:N3)` over times shows as a time. Spark Grid keeps the first four as text and shows the SUM as a plain number.
3. From the Nov 18 edge-case check against Excel 16.115: 
4. From the second Nov 18 batch against Excel 16.115, in rough order of how often workbooks need them:
6. Left from the Nov 18 reference work: CELL's "width", "format", "color", "parentheses" and "protect" are #VALUE!; the comma union operator (`SUM((B1:B3,B5:B6))`) does not parse; ISFORMULA of a range should spill.
7. LEN, LEFT, MID and RIGHT count letters as people see them; Excel counts UTF-16 units, so a Thai word with tone marks (ห้าบาทถ้วน) is 8 in Spark Grid and 10 in Excel, and an emoji is 1, not 2 (found Nov 19).
8. Saved results after a step that makes them all stale (a sort, a moved block, an Undo or Redo of a paste, fill or an assistant's write). Fixed Nov 19 for workbooks of up to 40,000 formulas: the save calculates every formula (about 3 s in Release). Above that (the 115k-formula stress workbook takes 8.7 s, and Quit waits on a save) the results are still left out; nothing is lost, as the formulas are saved and Excel and Spark Grid recalculate on open, but Quick Look shows blanks. Next: after such a step, recalculate only what the step changed.
