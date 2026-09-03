///|
test "apply taint rule supports inline constant metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Constant-tagged sink.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink($(tag:const), __SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let x = get_user_input();
    #|  sink(1, x);
    #|  sink(tag, x)
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply taint rule reports source reaching sink" {
  let rule_source =
    #|id: example
    #|description: |
    #|  User input reaches sink.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let x = get_user_input();
    #|  sink(x)
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
  assert_eq(hits[0].pattern_index, 0)
}

///|
test "apply taint rule covers migrated CST field mappings" {
  let rule_source =
    #|id: regression-probe
    #|description: Migrated CST taint fields.
    #|taint:
    #|  sources:
    #|    - shape: get_user_inputs()
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  let source =
    #|fn foreach_case {
    #|  for item in get_user_inputs() { sink(item) }
    #|}
    #|fn try_case {
    #|  try get_user_input() catch {
    #|    _ => ()
    #|  } noraise {
    #|    result => sink(result)
    #|  }
    #|}
    #|fn array_get_case {
    #|  let values = [get_user_input()];
    #|  sink(values[0])
    #|}
    #|fn array_set_case {
    #|  values[0] = sink(get_user_input())
    #|}
    #|fn else_case {
    #|  if clean() { () } else { sink(get_user_input()) }
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 5)
}

///|
test "taint sink locates source argument after ellipsis captures" {
  let rule_source =
    #|id: example
    #|description: |
    #|  User input reaches a variadic sink slot.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(prefix, $$$before, marker, __SOURCE__, $$$after)
    #|
  let source =
    #|fn sample {
    #|  let x = get_user_input();
    #|  sink(prefix, clean, also_clean, marker, x, trailing)
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
}

///|
test "default taint matcher applies source sink and sanitizer patterns" {
  let rule_source =
    #|id: example
    #|description: |
    #|  User input reaches sink unless sanitized.
    #|taint:
    #|  sources:
    #|    - shape: tagged_source($(tag:exp), $(tag:exp))
    #|  sinks:
    #|    - shape: tagged_sink($(tag:exp), $(tag:exp), __SOURCE__)
    #|  sanitizers:
    #|    - shape: clean($(tag:exp), $(tag:exp), __SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let dirty = tagged_source(if ready { a } else { b }, if ready { a } else { b });
    #|  tagged_sink(if ready { a } else { b }, if ready { a } else { b }, dirty);
    #|  tagged_sink(if ready { a } else { b }, if ready { a } else { b }, clean(if ready { a } else { b }, if ready { a } else { b }, dirty))
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
}

///|
test "apply taint rule supports inline identifier metavars" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Repeated tagged source reaches matching sink.
    #|taint:
    #|  sources:
    #|    - shape: tagged_source($(tag:id), $(tag:id))
    #|  sinks:
    #|    - shape: tagged_sink($(tag:id), $(tag:id), __SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let ignored = tagged_source(user, other);
    #|  let x = tagged_source(user, user);
    #|  tagged_sink(user, other, x);
    #|  tagged_sink(user, user, x)
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 1)
  inspect(hits[0].rule_id, content="example")
  assert_eq(hits[0].pattern_index, 0)
}

///|
test "apply taint rule sanitizer suppresses nested source sink" {
  let rule_source =
    #|id: example
    #|description: |
    #|  Sanitized input is safe.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|  sanitizers:
    #|    - shape: sanitize(__SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  sink(sanitize(get_user_input()))
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 0)
}

///|
test "apply taint rule matches source sink sanitizer" {
  let rule_source =
    #|id: example
    #|description: |
    #|  User input reaches sink unless sanitized.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|  sanitizers:
    #|    - shape: clean(__SOURCE__)
    #|
  let source =
    #|fn sample {
    #|  let dirty = get_user_input();
    #|  sink(dirty);
    #|  sink(clean(dirty))
    #|}
    #|
  let rules = compile_rule_source(rule_source)
  let impls = parse_root_node(source)
  let hits = apply_taint_test_rules("sample.mbt", impls, rules)
  assert_eq(hits.length(), 1)
}

///|
test "apply taint rule reports receiver and root call targets with sink indexes" {
  let rule_source =
    #|id: example
    #|description: |
    #|  User input reaches multiple sink shapes.
    #|taint:
    #|  sources:
    #|    - shape: get_user_input()
    #|  sinks:
    #|    - shape: receiver.method(__SOURCE__)
    #|    - shape: __SOURCE__.dangerous()
    #|    - shape: wrap(__SOURCE__)
    #|
  let source =
    #|fn sample(receiver) {
    #|  let x = get_user_input();
    #|  receiver.method(x);
    #|  x.dangerous();
    #|  wrap(x)
    #|}
    #|
  let hits = apply_taint_test_rules(
    "sample.mbt",
    parse_root_node(source),
    compile_rule_source(rule_source),
  )
  assert_eq(hits.length(), 3)
  assert_eq(hits[0].pattern_index, 0)
  assert_eq(hits[1].pattern_index, 1)
  assert_eq(hits[2].pattern_index, 2)
}
