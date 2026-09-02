# TODO

- Revisit bare metavariable kind inference. A bare name used in both an
  identifier-only position and an expression position is currently inferred as
  `id` for every occurrence. For example, `$obj = $obj + $_` looks as though
  `$obj` captures an arbitrary expression, but the assignment target makes it
  an identifier capture. This inference may be too broad. Consider requiring
  an explicit kind for cross-position reuse, improving the diagnostic, or
  adding a storage-path metavariable kind.

- Decide how YAML taint scans should handle `FixpointDidNotConverge`. Raising
  instead of returning a partial `AnalysisResult` avoids silent false negatives,
  but `rule/apply` currently rethrows the error, so one non-converging loop
  becomes an internal fatal scan error with exit status 1. Because scan output
  is streamed, findings from earlier files may already have been written. The
  YAML loop budget also increased from 6 to 64, allowing deeper convergent
  propagation but increasing the maximum iterations before failure by about
  10.7 times. Confirm whether aborting the whole scan is intended; otherwise,
  introduce a warning or incomplete-result path. Add CLI failure-path tests for
  the exit status, human and JSON stderr diagnostics, and partial stdout
  behavior.
