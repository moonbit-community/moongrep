///|
test "single expression pattern prefilter keeps literals and omits metavars" {
  let compiled = @compile.compile_expr_pattern("sink($(value:exp), \"needle\")")
  let prefilter = compile_expr_pattern_prefilter(compiled)
  debug_inspect(prefilter.alternatives, content="[[\"sink\", \"needle\"]]")
  assert_true(
    prefilter_matches_source(
      prefilter, "fn sample { sink(actual, \"needle\") }\n",
    ),
  )
  assert_false(
    prefilter_matches_source(
      prefilter, "fn sample { other(actual, \"needle\") }\n",
    ),
  )
  assert_false(
    prefilter_matches_source(
      prefilter, "fn sample { sink(actual, \"other\") }\n",
    ),
  )
}

///|
test "single metavar expression pattern remains conservatively relevant" {
  let compiled = @compile.compile_expr_pattern("$(_value:exp)")
  let prefilter = compile_expr_pattern_prefilter(compiled)
  debug_inspect(prefilter.alternatives, content="[[]]")
  assert_true(prefilter_matches_source(prefilter, "any expression"))
  assert_true(prefilter_matches_source(prefilter, ""))
}
