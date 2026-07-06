# TODO

## Current Limitations

- Matching is AST based and location preserving. Reported locations are exactly
  the locations supplied by the parser/tree builder.
- Structural `id` and `const` guards are supported. Guards for `exp` captures,
  `pat` captures, unknown captures, and taint clauses are still rejected.
- Taint analysis is intra-procedural. Cross-function behavior must be described
  with call models or matched directly by rule shapes.
- Unknown call handling depends on the selected `taint.UnknownCallPolicy`; YAML
  taint rules currently use a conservative no-effect policy except for explicit
  rule source, sink, and sanitizer shapes.
