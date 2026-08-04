# TODO

- Revisit bare metavariable kind inference. A bare name used in both an
  identifier-only position and an expression position is currently inferred as
  `id` for every occurrence. For example, `$obj = $obj + $_` looks as though
  `$obj` captures an arbitrary expression, but the assignment target makes it
  an identifier capture. This inference may be too broad. Consider requiring
  an explicit kind for cross-position reuse, improving the diagnostic, or
  adding a storage-path metavariable kind.

- Clarify constant matching in the RuleSpec overview. Constants are compared
  using the parser AST constant kind and preserved source spelling, so
  equivalent values such as `1000` and `1_000` do not necessarily match.
  Update the English and Chinese summaries so they do not imply that all
  formatting is ignored.

- Make the Chinese rule documentation available through the `docs` command,
  or document that only English documents are embedded. `docs/export.mbt`
  currently registers only `RuleSpec` and `WritingRules`; consider adding
  `RuleSpec_CN` and `WritingRules_CN`, or linking to accessible Chinese
  documents from `SKILL_CN.md`.
