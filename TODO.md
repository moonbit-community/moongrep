# TODO

## 1. Revisit bare metavariable kind inference

- **Current behavior**: When a bare metavariable appears in both an
  identifier-only position and an expression position, every occurrence is
  inferred as `id`. For example, in `$obj = $obj + $_`, `$obj` looks like an
  arbitrary expression capture, but the assignment target forces it to infer
  `id`.
- **Concern**: This cross-position inference may be too broad and surprising.
- **Options to evaluate**:
  - Require an explicit kind whenever a name spans incompatible position types.
  - Improve the diagnostic explaining why `id` was inferred.
  - Introduce a dedicated storage-path metavariable kind.

## 2. Confirm YAML taint handling for `FixpointDidNotConverge`

- **Background**:
  - Raising an error instead of returning a partial `AnalysisResult` avoids
    silent false negatives.
  - However, `internal/rule/apply` currently rethrows the error, turning one
    non-converging loop into an internal fatal scan error (exit status `1`).
  - Because scan output is streamed, findings from earlier files may already
    have been written before the failure occurs.
  - Increasing the YAML loop budget from `6` to `64` allows deeper convergent
    propagation, but raises the worst-case iteration count before failure by
    about `10.7x`.
- **Follow-up**:
  - Confirm whether aborting the whole scan is the desired behavior, or whether
    this case should emit a warning / incomplete-result path instead.
  - Add CLI failure-path tests covering exit status, human and JSON stderr
    diagnostics, and partial stdout output.
