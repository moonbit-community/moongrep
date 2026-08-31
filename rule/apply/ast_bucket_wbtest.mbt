///|
using @compile {compile_rules}

///|
fn parse_bucket_node(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_expression(source, name="CST bucket test")
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected expression to parse: \{source}")
  }
  @cst.expression_root(parsed.root())
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
      if structural.inside_expr.get(0) is Some(pattern) {
        pattern
      } else {
        fail("expected inside-expr")
      }
    Taint(_) => fail("expected structural rule")
  }
}

///|
fn manual_source_pattern(shape : String) -> CompiledRulePattern raise {
  let metavars = @matching.MetavarRegistry::new()
  metavars.register_special_expr_placeholder("__SOURCE__")
  let compiled : @matching.CompiledExprPattern = {
    cst: parse_bucket_node(shape),
    metavars,
    ignored_fields: [],
  }
  {
    source: { shape, guards: Map([]), match_mode: Default, },
    compiled,
    guards: [],
  }
}

///|
fn root_key_signature(key : ExprRootKey?) -> String {
  match key {
    None => "*"
    Some(IdentRoot) => "Expr_Ident"
    Some(ConstantRoot) => "Expr_Constant"
    Some(OtherRoot(kind)) => "\{Repr(kind)}"
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
test "CST bucket treats broad root placeholders as wildcard" {
  let wildcard = "*"
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
    #|  - shape: $_
    #|
  let target_rule_source =
    #|id: example
    #|description: Target root.
    #|inside-expr:
    #|  - shape: __TARGET__
    #|patterns:
    #|  - shape: target()
    #|
  let exp_pattern = compile_bucket_structural_patterns(exp_rule_source)[0]
  let ignore_pattern = compile_bucket_structural_patterns(ignore_rule_source)[0]
  let target_pattern = compile_bucket_inside_pattern(target_rule_source)
  let source_pattern = manual_source_pattern("__SOURCE__")
  inspect(
    root_key_signature(compiled_pattern_root_key(exp_pattern)),
    content=wildcard,
  )
  inspect(
    root_key_signature(compiled_pattern_root_key(ignore_pattern)),
    content=wildcard,
  )
  inspect(
    root_key_signature(compiled_pattern_root_key(target_pattern)),
    content=wildcard,
  )
  inspect(
    root_key_signature(compiled_pattern_root_key(source_pattern)),
    content=wildcard,
  )
}

///|
test "CST bucket keeps id and const root metavars precise" {
  let rule_source =
    #|id: example
    #|description: Root kinds.
    #|patterns:
    #|  - shape: $(name:id)
    #|  - shape: $(value:const)
    #|  - shape: target()
    #|
  let patterns = compile_bucket_structural_patterns(rule_source)
  inspect(
    root_key_signature(compiled_pattern_root_key(patterns[0])),
    content="Expr_Ident",
  )
  inspect(
    root_key_signature(compiled_pattern_root_key(patterns[1])),
    content="Expr_Constant",
  )
  inspect(
    root_key_signature(compiled_pattern_root_key(patterns[2])),
    content="Expr_Apply",
  )
}

///|
test "CST bucket classifies keyword metavars" {
  let rule_source =
    #|id: example
    #|description: Keyword root kinds.
    #|patterns:
    #|  - shape: $(else:exp)
    #|  - shape: $(if:id)
    #|  - shape: $(for:const)
    #|
  let patterns = compile_bucket_structural_patterns(rule_source)
  inspect(
    root_key_signature(compiled_pattern_root_key(patterns[0])),
    content="*",
  )
  inspect(
    root_key_signature(compiled_pattern_root_key(patterns[1])),
    content="Expr_Ident",
  )
  inspect(
    root_key_signature(compiled_pattern_root_key(patterns[2])),
    content="Expr_Constant",
  )
}

///|
test "CST bucket merges wildcard and keyed patterns in source order" {
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
        buckets.patterns_for_node(parse_bucket_node("target()")),
      ),
    ),
    content="[0, 1, 4]",
  )
  inspect(
    int_array_signature(
      bucket_pattern_indices(
        buckets.patterns_for_node(parse_bucket_node("value")),
      ),
    ),
    content="[0, 2]",
  )
  inspect(
    int_array_signature(
      bucket_pattern_indices(buckets.patterns_for_node(parse_bucket_node("42"))),
    ),
    content="[0, 3]",
  )
}

///|
test "CST bucket only offers sequence-compatible patterns to sequences" {
  let rule_source =
    #|id: example
    #|description: Sequence roots.
    #|patterns:
    #|  - shape: $(any:exp)
    #|  - shape: let value = source()
    #|  - shape: guard ready() else { fallback() }
    #|  - shape: let mut value = source()
    #|  - shape: "first(); second()"
    #|  - shape: "{ first(); second() }"
    #|
  let patterns = compile_bucket_structural_patterns(rule_source)
  let buckets = ExprPatternBuckets::from_patterns(patterns)
  let sequence = parse_bucket_node("first(); second()")
  guard sequence.kind is @untyped_cst.Expression else {
    fail("expected expression sequence")
  }
  inspect(
    int_array_signature(
      bucket_pattern_indices(
        buckets.patterns_for_candidate(
          @cst.Sequence(@cst.expression_nodes(sequence)),
        ),
      ),
    ),
    content="[1, 2, 4]",
  )
}
