# TODO

## $id can't match qualified function name

- Example: `$id:callee($exp:arg)` does not match `@int.abs(x)`.
- Root cause: `@int.abs` parses as `LongIdent::Dot(pkg="int", id="abs")`,
  while `$id` normalization currently only accepts simple `LongIdent::Ident`
  names and returns `None` for qualified names.
- Consider extending identifier normalization to support qualified names, for
  example by normalizing `Dot(pkg, id)` to a stable string such as `@pkg.id`,
  then update matcher tests and rule docs accordingly.

## Current Limitations

- Matching is AST based and location preserving. Reported locations are exactly
  the locations supplied by the parser/tree builder.
- Rule `guard` keys are rejected in runtime AST mode.
- Taint analysis is intra-procedural. Cross-function behavior must be described
  with call models or matched directly by rule shapes.
- Unknown call handling depends on the selected `taint.UnknownCallPolicy`; YAML
  taint rules currently use a conservative no-effect policy except for explicit
  rule source, sink, and sanitizer shapes.
