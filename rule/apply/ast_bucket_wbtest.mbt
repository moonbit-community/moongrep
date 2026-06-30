///|
using @compile {compile_rules}

///|
fn parse_bucket_expr(source : String) -> @syntax.Expr raise {
  let tokens = @lexer.tokens_from_string(
      source,
      comment=true,
      name="ast bucket test",
    ).tokens
  let (expr, reports) = @handrolled_parser.parse_expr(tokens)
  guard reports is [] else { fail("expected expression to parse: \{source}") }
  expr
}

///|
fn compile_bucket_rule_source(source : String) -> CompiledRule raise {
  let rules = compile_rules([
    @model.RawRuleSpec::from_str(
      "/tmp/rules/example.yaml", "/tmp/rules", source,
    ),
  ])
  guard rules is [rule] else { fail("expected one compiled rule") }
  rule
}

///|
fn compile_bucket_structural_patterns(
  source : String,
) -> Array[CompiledRulePattern] raise {
  match compile_bucket_rule_source(source).definition {
    Structural(structural) => structural.patterns
    Taint(_) => fail("expected structural rule")
  }
}

///|
fn compile_bucket_inside_pattern(source : String) -> CompiledRulePattern raise {
  match compile_bucket_rule_source(source).definition {
    Structural(structural) =>
      match structural.inside_expr {
        Some(pattern) => pattern
        None => fail("expected inside-expr")
      }
    Taint(_) => fail("expected structural rule")
  }
}

///|
fn manual_source_pattern(shape : String) -> CompiledRulePattern raise {
  let compiled : @matching.CompiledExprPattern = {
    ast: parse_bucket_expr(shape),
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
    target_metavar: None,
    source_metavar: Some("__SOURCE__"),
  }
  {
    source: { shape, guards: {} },
    compiled,
    json_compiled: @json_matching.compiled_expr_pattern_to_json(compiled),
    guards: [],
  }
}

///|
fn bucket_pattern_indices(
  patterns : Array[IndexedCompiledRulePattern],
) -> Array[Int] {
  let indices : Array[Int] = []
  for pattern in patterns {
    indices.push(pattern.pattern_index)
  }
  indices
}

///|
fn int_array_signature(values : Array[Int]) -> String {
  let parts : Array[String] = []
  for value in values {
    parts.push(value.to_string())
  }
  "[\{parts.join(", ")}]"
}

///|
test "ast bucket treats broad root placeholders as wildcard" {
  let wildcard = ast_bucket_wildcard_key()
  let exp_rule_source =
    #|id: example
    #|description: Expression root.
    #|patterns:
    #|  - shape: $(value:exp)
    #|
  let ignore_rule_source =
    #|id: example
    #|description: Ignore root.
    #|patterns:
    #|  - shape: __
    #|
  let target_rule_source =
    #|id: example
    #|description: Target root.
    #|inside-expr: __TARGET__
    #|patterns:
    #|  - shape: target()
    #|
  let exp_pattern = compile_bucket_structural_patterns(exp_rule_source)[0]
  let ignore_pattern = compile_bucket_structural_patterns(ignore_rule_source)[0]
  let target_pattern = compile_bucket_inside_pattern(target_rule_source)
  let source_pattern = manual_source_pattern("__SOURCE__")
  inspect(compiled_pattern_root_key(exp_pattern), content=wildcard)
  inspect(compiled_pattern_root_key(ignore_pattern), content=wildcard)
  inspect(compiled_pattern_root_key(target_pattern), content=wildcard)
  inspect(compiled_pattern_root_key(source_pattern), content=wildcard)
}

///|
test "ast bucket keeps id and const root metavars precise" {
  let rule_source =
    #|id: example
    #|description: Root kinds.
    #|patterns:
    #|  - shape: $(name:id)
    #|  - shape: $(value:const)
    #|  - shape: target()
    #|
  let patterns = compile_bucket_structural_patterns(rule_source)
  inspect(compiled_pattern_root_key(patterns[0]), content="Ident")
  inspect(compiled_pattern_root_key(patterns[1]), content="Constant")
  inspect(compiled_pattern_root_key(patterns[2]), content="Apply")
}

///|
test "ast bucket merges wildcard and keyed patterns in source order" {
  let rule_source =
    #|id: example
    #|description: Ordered root buckets.
    #|patterns:
    #|  - shape: $(any:exp)
    #|  - shape: target()
    #|  - shape: $(name:id)
    #|  - shape: $(value:const)
    #|  - shape: other()
    #|
  let patterns = compile_bucket_structural_patterns(rule_source)
  let buckets = ExprPatternBuckets::from_patterns(patterns)
  inspect(
    int_array_signature(
      bucket_pattern_indices(
        buckets.patterns_for_expr(parse_bucket_expr("target()")),
      ),
    ),
    content="[0, 1, 4]",
  )
  inspect(
    int_array_signature(
      bucket_pattern_indices(
        buckets.patterns_for_expr(parse_bucket_expr("value")),
      ),
    ),
    content="[0, 2]",
  )
  inspect(
    int_array_signature(
      bucket_pattern_indices(buckets.patterns_for_expr(parse_bucket_expr("42"))),
    ),
    content="[0, 3]",
  )
}
