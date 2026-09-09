///|
// Deliberately recursive and uncached. This small interpreter is test-only and
// keeps the declarative priority, pruning, and negative-coverage semantics.
fn reference_candidate(
  session : ScanSession,
  group_id : Int,
  region : @cst.RegionId,
  env : Int,
) -> GroupCandidateResult {
  let group = session.plan.groups[group_id]
  for
    indexed in group.positive.patterns_for_candidate(
      session.index.candidate(region),
    ) {
    guard session.match_pattern(indexed.pattern, region, env) is Some(matched) else {
      continue
    }
    if group.children[indexed.pattern_index] is Some(child) {
      guard matched.target is Some(target) else { continue }
      let child_env = session.target_environment(
        indexed.pattern,
        matched,
        env,
        child,
      )
      if !reference_scan(session, child, target.region, child_env, fn(_, _) {
          ()
        }) {
        continue
      }
    }
    return GroupHit(indexed.pattern_index, matched.result.loc)
  }
  for
    indexed in group.negative.patterns_for_candidate(
      session.index.candidate(region),
    ) {
    if session.match_pattern(indexed.pattern, region, env) is Some(_) {
      return GroupNegative
    }
  }
  GroupMiss
}

///|
fn reference_scan(
  session : ScanSession,
  group_id : Int,
  region : @cst.RegionId,
  env : Int,
  publish : (Int, @basic.Location) -> Unit,
) -> Bool {
  let group = session.plan.groups[group_id]
  let pending : Array[(Int, @basic.Location)] = []
  let mut rejected = false
  session.index.walk(session.index.scan(region), fn(candidate) {
    match reference_candidate(session, group_id, candidate, env) {
      GroupHit(index, loc) => {
        pending.push((index, loc))
        @cst.NodeVisitPrune
      }
      GroupNegative =>
        if group.reject_negative || !group.has_positive {
          rejected = true
          @cst.NodeVisitReturn
        } else {
          @cst.NodeVisitPrune
        }
      GroupMiss => @cst.NodeVisitContinue
    }
  })
  if rejected || (group.has_positive && pending.is_empty()) {
    return false
  }
  for (index, loc) in pending {
    publish(index, loc)
  }
  true
}

///|
fn reference_findings(
  file : String,
  node : @untyped_cst.CstNode,
  plan : ScanPlan,
) -> Array[RuleFinding] {
  let session = ScanSession::new(plan, node)
  let hits : Array[RuleFinding] = []
  let toplevel = if node.kind is @untyped_cst.Impls {
    @cst.toplevel_nodes(node)
  } else {
    [node]
  }
  for node in toplevel {
    let region = session.index.direct(session.index.node_id(node))
    for entry in plan.structural_entries {
      if entry.structural.inside_toplevel.is_empty() {
        continue
      }
      for
        indexed in entry.inside_pattern_buckets.patterns_for_candidate(
          session.index.candidate(region),
        ) {
        if session.match_pattern(indexed.pattern, region, 0) is Some(matched) {
          if matched.target is Some(target) {
            let env = session.target_environment(
              indexed.pattern,
              matched,
              0,
              entry.group,
            )
            let success = reference_scan(
              session,
              entry.group,
              target.region,
              env,
              fn(index, loc) {
                push_structural_hit(file, entry.rule, index, loc, hits)
              },
            )
            if success && !plan.groups[entry.group].has_positive {
              push_structural_hit(file, entry.rule, 0, matched.result.loc, hits)
            }
          }
          break
        }
      }
    }
  }
  let entries = plan.structural_entries.filter(entry => {
    entry.structural.inside_toplevel.is_empty()
  })
  fn visit(
    cursor : @cst.CursorId,
    entries : Array[CstStructuralRuleEntry],
  ) -> Unit {
    match session.index.step(cursor) {
      End => ()
      Scan(_) | Finish(_) | AfterContinue(_, _) =>
        abort("expected an ordinary root cursor")
      Concat(left, right) => {
        visit(left, entries)
        visit(right, entries)
      }
      Visit(region, next) => {
        let remaining : Array[CstStructuralRuleEntry] = []
        for entry in entries {
          match reference_candidate(session, entry.group, region, 0) {
            GroupHit(index, loc) =>
              push_structural_hit(file, entry.rule, index, loc, hits)
            GroupNegative => ()
            GroupMiss => remaining.push(entry)
          }
        }
        if !remaining.is_empty() {
          visit(session.index.children(region), remaining)
        }
        visit(next, entries)
      }
    }
  }
  visit(session.index.roots(), entries)
  hits
}

///|
fn complete_finding_signature(
  finding : RuleFinding,
) -> (String, String, String, Int, @basic.Location) {
  (
    finding.file,
    finding.rule_id,
    finding.description,
    finding.pattern_index,
    finding.loc,
  )
}

///|
test "cached evaluator agrees with an uncached interpreter on generated sources" {
  let rules = compile_scan_plan_rules([
    (
      #|id: inherited
      #|description: Deep dependencies and ordered alternatives.
      #|patterns:
      #|  - shape: wrapper($(name:id), __TARGET__)
      #|    then:
      #|      patterns:
      #|        - shape: __TARGET__
      #|          then:
      #|            patterns:
      #|              - shape: sink($(name:id))
      #|                guard:
      #|                  $name: '^a$'
      #|            patterns-not:
      #|              - shape: danger($(name:id))
      #|  - shape: fallback($_)
      #|patterns-not:
      #|  - shape: ignore($_)
    ),
    (
      #|id: context
      #|description: Context-wide rejection before publication.
      #|inside-toplevel:
      #|  - shape: fn sample { __TARGET__ }
      #|patterns:
      #|  - shape: sink($_)
      #|  - shape: wrapper($_, __TARGET__)
      #|    then:
      #|      patterns:
      #|        - shape: sink($_)
      #|patterns-not:
      #|  - shape: danger($_)
    ),
    (
      #|id: ordered
      #|description: Ellipsis backtracking and rule order.
      #|patterns:
      #|  - shape: choose($$$before, __TARGET__, $$$after)
      #|    then:
      #|      patterns:
      #|        - shape: sink($_)
      #|  - shape: sink($_)
    ),
  ])
  let plan = ScanPlan::from_rules(rules)
  let atoms = [
    "sink(a)", "sink(b)", "danger(a)", "fallback(a)", "ignore(sink(a))", "wrapper(a, sink(a))",
  ]
  for left in atoms {
    for right in atoms {
      for binding in ["a", "b"] {
        for
          body in [
            "wrapper(a, { let \{binding} = source(); \{left}; \{right} })",
            "choose(\{left}, \{right}); \{right}",
            "{ \{left}; \{right} }; \{left}",
          ] {
          let root = parse_scan_plan_root(
            "fn sample { \{body} }\nfn second { sink(a) }",
          )
          let actual = apply_structural_scan_plan_to_node(
            "generated.mbt", root, plan,
          )
          let expected = reference_findings("generated.mbt", root, plan)
          assert_eq(
            actual.map(complete_finding_signature),
            expected.map(complete_finding_signature),
          )
        }
      }
    }
  }
}
