# TODO

## Current Limitations

- `scan --output-json` currently emits finding records only, so parse warnings
  for skipped files are silently omitted. Add a machine-readable warning record
  or a separate diagnostic channel before treating JSON output as a complete
  scan report.
- Matching is AST based and location preserving. Reported locations are exactly
  the locations supplied by the parser/tree builder.
- Structural `id` and `const` guards are supported. Guards for `exp`, `arg`,
  `pat`, and `type` captures, unknown captures, and taint clauses are rejected.
- Taint analysis is intra-procedural. Cross-function behavior must be described
  with call models or matched directly by rule shapes.
- Unknown call handling depends on the selected `taint.UnknownCallPolicy`. YAML
  taint rules currently use a conservative no-effect policy for unknown calls.
  Explicit rule source, sink, and sanitizer shapes retain their modeled effects.
