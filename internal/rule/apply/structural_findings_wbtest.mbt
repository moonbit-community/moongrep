///|
test "structural findings preserve the first complete finding for each full key" {
  let rules = compile_scan_plan_rules([
    "id: first\ndescription: First description.\npatterns:\n  - shape: target()\n",
    "id: second\ndescription: Second rule.\npatterns:\n  - shape: target()\n",
  ])
  let loc = parse_scan_plan_single_node("fn sample { target() }").loc
  let collector = StructuralFindingCollector::new()
  collector.add("one.mbt", rules[0], 3, loc)
  collector.add(
    "one.mbt",
    { ..rules[0], description: "Later description.", },
    1,
    loc,
  )
  collector.add("one.mbt", rules[1], 0, loc)
  collector.add("two.mbt", rules[0], 2, loc)
  // A shared start or end alone does not identify a diagnostic.
  collector.add("one.mbt", rules[0], 4, {
    ..loc,
    end: { ..loc.end, cnum: loc.end.cnum + 1, },
  })
  collector.add("one.mbt", rules[0], 5, {
    ..loc,
    start: { ..loc.start, cnum: loc.start.cnum + 1, },
  })
  debug_inspect(
    collector.findings.map(hit => {
      (hit.file, hit.rule_id, hit.pattern_index, hit.description)
    }),
    content=(
      #|[
      #|  ("one.mbt", "first", 3, "First description."),
      #|  ("one.mbt", "second", 0, "Second rule."),
      #|  ("two.mbt", "first", 2, "First description."),
      #|  ("one.mbt", "first", 4, "First description."),
      #|  ("one.mbt", "first", 5, "First description."),
      #|]
    ),
  )
  inspect(collector.findings[0].loc == loc, content="true")
}

///|
test "each structural application owns its finding collector" {
  let rules = compile_scan_plan_rules([
    "id: independent\ndescription: Independent parsed blocks.\npatterns:\n  - shape: target()\n",
  ])
  let plan = ScanPlan::from_rules(rules)
  let first = parse_scan_plan_root("fn sample { target() }")
  let second = parse_scan_plan_root("fn sample { target() }")
  let first_hits = apply_structural_scan_plan_to_node("same.mbt", first, plan)
  let second_hits = apply_structural_scan_plan_to_node("same.mbt", second, plan)
  inspect(first_hits.length(), content="1")
  inspect(second_hits.length(), content="1")
  inspect(first_hits[0].loc == second_hits[0].loc, content="true")
}

///|
test "all structural execution paths retain the first published pattern index" {
  let root = parse_scan_plan_root("fn sample { target() }")
  for context in ["", "inside-toplevel:\n  - shape: fn sample { __TARGET__ }\n"] {
    let rules = compile_scan_plan_rules([
      "id: first\ndescription: First match.\n" +
      context +
      "patterns:\n  - shape: absent()\n  - shape: target()\n",
      "id: second\ndescription: Later match.\n" +
      context +
      "patterns:\n  - shape: target()\n",
      "id: recursive\ndescription: Force mixed execution.\npatterns:\n  - shape: holder(__TARGET__)\n    then:\n      patterns:\n        - shape: absent()\n",
    ])
    // The loader requires unique IDs; callers can also supply compiled entries.
    let entries = [rules[0], { ..rules[1], rule_id: rules[0].rule_id, }]
    let plain = ScanPlan::from_rules(entries)
    let mixed = ScanPlan::from_rules(entries + [rules[2]])
    for plan in [plain, force_indexed_root_entries(plain), mixed] {
      let hits = apply_structural_scan_plan_to_node("first.mbt", root, plan)
      assert_eq(hits.length(), 1)
      assert_eq(hits[0].pattern_index, 1)
      assert_eq(hits[0].description, "First match.")
    }
  }
}
