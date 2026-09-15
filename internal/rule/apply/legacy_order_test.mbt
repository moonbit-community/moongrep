///|
test "inside publication preserves the full visitor's completion order" {
  let rule = "id: legacy\ndescription: Legacy publication.\ninside-toplevel:\n  - shape: fn sample { __TARGET__ }\npatterns:\n  - shape: $(name:id)\n    guard:\n      $name: '^target$'\n"
  let bodies = [
    "let item = target()", "target(target())", "let f = fn(x) { target(x) }; finish()",
    "if cond() { target() } else { target() }", "if cond() { target() }", "for i = 0; i < 3; i = i + 1 { target() }",
    "try other() catch { _ => target() }", "letrec f = fn(x) { target(x) }; finish()",
  ]
  let signatures : Array[Array[String]] = []
  for body in bodies {
    signatures.push(
      apply_structural_rule_findings("fn sample { " + body + " }", rule).map(
        finding_signature,
      ),
    )
  }
  debug_inspect(
    signatures,
    content=(
      #|[
      #|  ["sample.mbt|legacy|0|1:24-1:30", "sample.mbt|legacy|0|1:24-1:30"],
      #|  [
      #|    "sample.mbt|legacy|0|1:13-1:19",
      #|    "sample.mbt|legacy|0|1:20-1:26",
      #|    "sample.mbt|legacy|0|1:20-1:26",
      #|  ],
      #|  [
      #|    "sample.mbt|legacy|0|1:29-1:35",
      #|    "sample.mbt|legacy|0|1:29-1:35",
      #|    "sample.mbt|legacy|0|1:29-1:35",
      #|    "sample.mbt|legacy|0|1:29-1:35",
      #|  ],
      #|  [
      #|    "sample.mbt|legacy|0|1:25-1:31",
      #|    "sample.mbt|legacy|0|1:25-1:31",
      #|    "sample.mbt|legacy|0|1:25-1:31",
      #|    "sample.mbt|legacy|0|1:43-1:49",
      #|    "sample.mbt|legacy|0|1:43-1:49",
      #|    "sample.mbt|legacy|0|1:43-1:49",
      #|  ],
      #|  [
      #|    "sample.mbt|legacy|0|1:25-1:31",
      #|    "sample.mbt|legacy|0|1:25-1:31",
      #|    "sample.mbt|legacy|0|1:25-1:31",
      #|  ],
      #|  [
      #|    "sample.mbt|legacy|0|1:43-1:49",
      #|    "sample.mbt|legacy|0|1:43-1:49",
      #|    "sample.mbt|legacy|0|1:43-1:49",
      #|  ],
      #|  ["sample.mbt|legacy|0|1:38-1:44", "sample.mbt|legacy|0|1:38-1:44"],
      #|  ["sample.mbt|legacy|0|1:32-1:38"],
      #|]
    ),
  )
}
