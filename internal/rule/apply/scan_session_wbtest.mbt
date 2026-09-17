///|
test "recursive failure expands each complete state once" {
  for depth in [8, 16, 32, 64] {
    let plan = ScanPlan::from_rules([recursive_bench_rule(depth, "absent()")])
    let root = parse_scan_plan_root(recursive_bench_source())
    let session = ScanSession::new(plan, root)
    let findings = apply_scan_session("sample.mbt", root, session)
    assert_true(findings.is_empty())
    assert_eq(session.candidate_expansions, session.candidates.length())
    assert_eq(session.region_expansions, session.regions.length())
    assert_true(
      session.candidate_expansions + session.region_expansions <=
      2 * plan.groups.length() * session.index.state_count(),
    )
  }
}

///|
fn session_identifier_value(name : String) -> @bound_value_model.BoundValue {
  let parsed = @untyped_cst.parse_expression(name, name="capture")
  Single(@cst.name_node(@cst.expression_root(parsed.root())).unwrap())
}

///|
test "list environment keys include every binding and lexical role" {
  let plan = ScanPlan::from_rules(
    compile_scan_plan_rules([
      "id: list\ndescription: Inherited identifiers.\npatterns:\n  - shape: sink($$$(names:id))\n",
    ]),
  )
  let root = parse_scan_plan_root(
    "fn sample { let a = source(); let b = source(); sink(a, b) }",
  )
  let session = ScanSession::new(plan, root)
  let mut sink : @cst.RegionId? = None
  session.index.walk(session.index.roots(), fn(region) {
    if session.index.candidate(region) is @cst.Direct(node) &&
      node.kind is @untyped_cst.Expr_Apply &&
      @cst.raw_child(node, "func").bind(@cst.normalized_expr_identifier_name) ==
      Some("sink") {
      sink = Some(region)
    }
    @cst.NodeVisitContinue
  })
  let region = sink.unwrap()
  let pattern = plan.groups[0].positive.patterns_for_candidate(
      session.index.candidate(region),
    )[0].pattern
  let matched = session.match_pattern(pattern, region, 0).unwrap()
  let value = matched.result.bindings.get("names").unwrap()
  guard matched.sources.get("names") is Some(MultipleIdentifiers(sources)) else {
    fail("expected list sources")
  }
  let capture : Capture = {
    id: 0,
    value,
    identity: session.values.intern(value),
    source: Some(MultipleIdentifiers(sources)),
  }
  let local_env = session.intern_environment([capture])
  assert_true(session.candidate(0, region, local_env) is GroupHit(_, _))
  let environments = [local_env]
  for position in 0..<sources.length() {
    for binding in [@cst.Lexical(None), @cst.NonLexical] {
      let changed = sources.copy()
      changed[position] = { ..changed[position], binding, }
      let env = session.intern_environment([
        { ..capture, source: Some(MultipleIdentifiers(changed)), },
      ])
      assert_false(environments.contains(env))
      environments.push(env)
      assert_eq(
        session.candidate(0, region, env) is GroupHit(_, _),
        binding is NonLexical,
      )
    }
  }
  assert_eq(session.candidate_expansions, 5)
}

///|
test "cache keys distinguish capture values and lexical binding identities" {
  let rules = compile_scan_plan_rules([
    "id: identity\ndescription: Captured identifier.\npatterns:\n  - shape: sink($(name:id))\n",
    "id: unused\ndescription: Unrelated capture.\npatterns:\n  - shape: other($(unused:id))\n",
  ])
  let plan = ScanPlan::from_rules(rules)
  let root = parse_scan_plan_root(
    "fn sample { let item = source(); sink(item) }",
  )
  let session = ScanSession::new(plan, root)
  let mut sink : @cst.RegionId? = None
  session.index.walk(session.index.roots(), fn(region) {
    if session.index.candidate(region) is @cst.Direct(node) &&
      node.kind is @untyped_cst.Expr_Apply &&
      @cst.raw_child(node, "func").bind(@cst.normalized_expr_identifier_name) ==
      Some("sink") {
      sink = Some(region)
    }
    @cst.NodeVisitContinue
  })
  let region = sink.unwrap()
  let local_binding = session.index.resolve(session.index.scope(region), "item")
  assert_true(local_binding is Some(_))
  let value = session_identifier_value("item")
  let capture : Capture = {
    id: 0,
    value,
    identity: session.values.intern(value),
    source: Some(SingleIdentifier({ name: "item", binding: Lexical(None), })),
  }
  let outer = session.intern_environment([capture])
  let local_env = session.intern_environment([
    {
      ..capture,
      source: Some(
        SingleIdentifier({ name: "item", binding: Lexical(local_binding), }),
      ),
    },
  ])
  let other_value = session_identifier_value("other")
  let other = session.intern_environment([
    {
      id: 0,
      value: other_value,
      identity: session.values.intern(other_value),
      source: Some(SingleIdentifier({ name: "other", binding: Lexical(None), })),
    },
  ])
  assert_true(session.candidate(0, region, outer) is GroupMiss)
  assert_true(session.candidate(0, region, other) is GroupMiss)
  assert_true(session.candidate(0, region, local_env) is GroupHit(_, _))
  assert_eq(session.candidate_expansions, 3)
  let same_value = session_identifier_value("  item ")
  let same = session.intern_environment([
    {
      ..capture,
      value: same_value,
      identity: session.values.intern(same_value),
      source: Some(
        SingleIdentifier({ name: "item", binding: Lexical(local_binding), }),
      ),
    },
  ])
  assert_eq(same, local_env)
  let irrelevant = session.intern_environment([
    {
      ..capture,
      source: Some(
        SingleIdentifier({ name: "item", binding: Lexical(local_binding), }),
      ),
    },
    {
      id: 1,
      value: other_value,
      identity: session.values.intern(other_value),
      source: Some(SingleIdentifier({ name: "other", binding: Lexical(None), })),
    },
  ])
  assert_true(session.candidate(0, region, irrelevant) is GroupHit(_, _))
  assert_eq(session.candidate_expansions, 3)
  let nonlexical = session.intern_environment([
    {
      ..capture,
      source: Some(SingleIdentifier({ name: "item", binding: NonLexical, })),
    },
  ])
  assert_true(nonlexical != outer && nonlexical != local_env)
  assert_true(session.candidate(0, region, nonlexical) is GroupHit(_, _))
  assert_eq(session.candidate_expansions, 4)
}

///|
test "success failure and negative rejection scale across source and rule chains" {
  let negative = compile_scan_plan_rules([
      "id: reject\ndescription: Reject an uncovered negative.\npatterns:\n  - shape: __TARGET__\n    then:\n      patterns-not:\n        - shape: $_\n",
    ])[0]
  guard negative.definition is Structural(negative_definition) else {
    fail("expected structural rule")
  }
  let reject_group = negative_definition.group.patterns[0].then_body.unwrap()
  for depth in [8, 16, 32, 64] {
    for length in [8, 16, 32, 64] {
      let mut body = "missing()"
      let mut statements = ""
      for _ in 0..<length {
        body = "wrapper(\{body})"
        statements += "let item = source(); "
      }
      for
        source in [
          "fn sample { \{body} }",
          "fn sample { \{statements}missing() }",
        ] {
        for outcome in ["success", "failure", "reject"] {
          let rule = recursive_bench_rule(
            depth,
            if outcome == "success" {
              "missing()"
            } else {
              "absent()"
            },
          )
          let plan = ScanPlan::from_rules([rule])
          let plan = if outcome == "reject" {
            // A negative-only leaf rejects every nonempty target.
            let reject_groups : Array[PlannedStructuralGroup] = []
            ignore(plan_structural_group(reject_group, reject_groups, []))
            let groups = plan.groups.copy()
            groups[groups.length() - 1] = reject_groups[0]
            { ..plan, groups, }
          } else {
            plan
          }
          let root = parse_scan_plan_root(source)
          let session = ScanSession::new(plan, root)
          let hits = apply_scan_session("scale.mbt", root, session)
          assert_eq(!hits.is_empty(), outcome == "success")
          assert_eq(session.candidate_expansions, session.candidates.length())
          assert_eq(session.region_expansions, session.regions.length())
          assert_true(
            session.candidate_expansions + session.region_expansions <=
            2 * plan.groups.length() * session.index.state_count(),
          )
        }
      }
    }
  }
}

///|
test "mixed scans keep plain entries out of evaluation caches" {
  let rules = compile_scan_plan_rules([
    (
      #|id: plain-before
      #|description: First plain rule.
      #|patterns:
      #|  - shape: wrapper($_)
    ),
    (
      #|id: recursive
      #|description: Recursive middle rule.
      #|patterns:
      #|  - shape: wrapper(__TARGET__)
      #|    then:
      #|      patterns:
      #|        - shape: target()
    ),
    (
      #|id: plain-after
      #|description: Last plain rule.
      #|patterns:
      #|  - shape: wrapper($_)
    ),
  ])
  let plan = ScanPlan::from_rules(rules)
  let root = parse_scan_plan_root("fn sample { wrapper(target()) }")
  let session = ScanSession::new(plan, root)
  let findings = apply_scan_session("mixed.mbt", root, session)
  debug_inspect(
    findings.map(finding => finding.rule_id),
    content="[\"plain-before\", \"recursive\", \"plain-after\"]",
  )
  let plain_groups = plan.structural_entries.filter_map(entry => {
    if entry.plain_root {
      Some(entry.group)
    } else {
      None
    }
  })
  for key, _ in session.candidates {
    assert_false(plain_groups.contains(key.group))
  }
  for key, _ in session.regions {
    assert_false(plain_groups.contains(key.group))
  }
  for key, _ in session.projections {
    assert_false(plain_groups.contains(key.1))
  }
}
