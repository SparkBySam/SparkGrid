# Observed reference behavior

Unit tests in `FunctionCoverageTests` use small inputs and the evaluator's own results. That is not ground truth. The ground-truth column in `docs/function-parity.md` stays `no` until a saved Excel, Google Sheets, or Numbers result is cleared and recalculated.

No live Excel, Google Sheets, or Numbers session was run for this note. Nothing below is an observation of those apps. Public documentation and the Spark Grid implementation are the only sources.

## Not observed

- Excel's 1900 leap-year bug. Spark Grid's serials ignore it (`ExcelDate`).
- `TEXT` format codes beyond the patterns the evaluator already implements (`0`, `0.0`, `0.00`, `0%`, and a few date patterns).
- Saved results from the private KPI workbook. Those are checked by `CorpusAnswerCheck` when `SPARK_GRID_CORPUS` is set. They are not copied into this file.

## From public documentation, not from a session here

- `ABS` returns the absolute value.
- `SUM` adds numbers.
- `TRUE()` returns the boolean TRUE.
- A malformed formula's saved `#ERROR!` is a parse failure, not a calculated value.
