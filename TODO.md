# TODO

## Current Limitations

- The stable user-facing entry point is the CLI; library APIs are still
  experimental.
- Matching is AST based and location preserving. Reported locations are exactly
  the locations supplied by the parser/tree builder.
- Rule `guard` keys are rejected in runtime AST mode.
- Taint analysis is intra-procedural. Cross-function behavior must be described
  with call models or matched directly by rule shapes.
- Unknown call handling depends on the selected `taint.UnknownCallPolicy`; YAML
  taint rules currently use a conservative no-effect policy except for explicit
  rule source, sink, and sanitizer shapes.
