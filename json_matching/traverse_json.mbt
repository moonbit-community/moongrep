///|
/// Collects parser expression JSON nodes in the same pre-order used by
/// `@traverse.collect_exprs`.
///
/// Only fields known to contain expressions are traversed; this is intentionally
/// not a generic recursive JSON walk.
pub fn collect_expr_jsons(expr : Json, exprs : Array[Json]) -> Unit {
  match json_kind(expr) {
    Some(kind) if kind.has_prefix("Expr::") => {
      exprs.push(expr)
      collect_expr_json_children(expr, kind, exprs)
    }
    _ => ()
  }
}

///|
pub(all) struct ScopedJsonExpr {
  expr : Json
  shadowed_names : Array[String]
}

///|
pub fn collect_scoped_expr_jsons(
  expr : Json,
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_scoped_expr_jsons_with_shadow(expr, [], exprs)
}

///|
fn collect_scoped_expr_jsons_with_shadow(
  expr : Json,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  match json_kind(expr) {
    Some(kind) if kind.has_prefix("Expr::") => {
      exprs.push({ expr, shadowed_names: copy_shadowed_names(shadowed) })
      collect_scoped_expr_json_children(expr, kind, shadowed, exprs)
    }
    _ => ()
  }
}

///|
fn collect_scoped_expr_json_children(
  expr : Json,
  kind : String,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  match kind {
    "Expr::Apply" => {
      collect_scoped_child_expr_json(expr, "func", shadowed, exprs)
      collect_scoped_argument_expr_jsons(child(expr, "args"), shadowed, exprs)
    }
    "Expr::DotApply" => {
      collect_scoped_child_expr_json(expr, "self", shadowed, exprs)
      collect_scoped_argument_expr_jsons(child(expr, "args"), shadowed, exprs)
    }
    "Expr::Field" =>
      collect_scoped_child_expr_json(expr, "record", shadowed, exprs)
    "Expr::Infix" | "Expr::Pipe" | "Expr::RevPipe" | "Expr::Implies" => {
      collect_scoped_child_expr_json(expr, "lhs", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "rhs", shadowed, exprs)
    }
    "Expr::Unary"
    | "Expr::Assign"
    | "Expr::Is"
    | "Expr::ProofAssert"
    | "Expr::ProofLet" =>
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
    "Expr::RegexMatch" => {
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
      collect_scoped_regex_pattern_expr_json(
        child(expr, "pat"),
        shadowed,
        exprs,
      )
    }
    "Expr::Array" | "Expr::Tuple" =>
      collect_scoped_expr_list_jsons(child(expr, "exprs"), shadowed, exprs)
    "Expr::Continue" =>
      collect_scoped_expr_list_jsons(child(expr, "args"), shadowed, exprs)
    "Expr::Sequence" => {
      collect_scoped_expr_list_jsons(child(expr, "exprs"), shadowed, exprs)
      collect_scoped_child_expr_json(expr, "last_expr", shadowed, exprs)
    }
    "Expr::ArrayGet" => {
      collect_scoped_child_expr_json(expr, "array", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "index", shadowed, exprs)
    }
    "Expr::ArraySet" | "Expr::ArrayAugmentedSet" => {
      collect_scoped_child_expr_json(expr, "array", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "index", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "value", shadowed, exprs)
    }
    "Expr::ArraySpread" =>
      collect_scoped_spreadable_elem_expr_jsons(
        child(expr, "elems"),
        shadowed,
        exprs,
      )
    "Expr::ArrayGetSlice" => {
      collect_scoped_child_expr_json(expr, "array", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "start_index", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "end_index", shadowed, exprs)
    }
    "Expr::Group" | "Expr::Constraint" | "Expr::As" | "Expr::TryOperator" =>
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
    "Expr::If" => {
      collect_scoped_child_expr_json(expr, "cond", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "ifso", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "ifnot", shadowed, exprs)
    }
    "Expr::Guard" => {
      collect_scoped_child_expr_json(expr, "cond", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "otherwise", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "body", shadowed, exprs)
    }
    "Expr::Let" => {
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
      let body_shadowed = shadowed_with_json_pattern(
        shadowed,
        child(expr, "pattern"),
      )
      collect_scoped_child_expr_json(expr, "body", body_shadowed, exprs)
    }
    "Expr::LetMut" => {
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
      let body_shadowed = shadowed_with_json_binder(
        shadowed,
        child(expr, "binder"),
      )
      collect_scoped_child_expr_json(expr, "body", body_shadowed, exprs)
    }
    "Expr::For" => {
      collect_scoped_binder_expr_pair_jsons(
        child(expr, "binders"),
        shadowed,
        exprs,
      )
      let loop_shadowed = shadowed_with_json_binder_expr_pairs(
        shadowed,
        child(expr, "binders"),
      )
      collect_scoped_child_expr_json(expr, "condition", loop_shadowed, exprs)
      collect_scoped_binder_expr_pair_jsons(
        child(expr, "continue_block"),
        loop_shadowed,
        exprs,
      )
      collect_scoped_child_expr_json(expr, "body", loop_shadowed, exprs)
      collect_scoped_child_expr_json(expr, "for_else", loop_shadowed, exprs)
      collect_scoped_where_clause_expr_jsons(
        child(expr, "where_clause"),
        loop_shadowed,
        exprs,
      )
    }
    "Expr::ForEach" => {
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
      collect_scoped_binder_expr_pair_jsons(
        child(expr, "init"),
        shadowed,
        exprs,
      )
      let loop_shadowed = shadowed_with_json_optional_binders(
        shadowed,
        child(expr, "binders"),
      )
      add_json_binder_expr_pair_names(loop_shadowed, child(expr, "init"))
      collect_scoped_binder_expr_pair_jsons(
        child(expr, "continue_block"),
        loop_shadowed,
        exprs,
      )
      collect_scoped_child_expr_json(expr, "body", loop_shadowed, exprs)
      collect_scoped_child_expr_json(expr, "else_block", loop_shadowed, exprs)
      collect_scoped_where_clause_expr_jsons(
        child(expr, "where_clause"),
        loop_shadowed,
        exprs,
      )
    }
    "Expr::Return" =>
      collect_scoped_child_expr_json(expr, "return_value", shadowed, exprs)
    "Expr::Raise" =>
      collect_scoped_child_expr_json(expr, "err_value", shadowed, exprs)
    "Expr::Interp" =>
      collect_scoped_interp_elem_expr_jsons(
        child(expr, "elems"),
        shadowed,
        exprs,
      )
    "Expr::Record" =>
      collect_scoped_field_def_expr_jsons(
        child(expr, "fields"),
        shadowed,
        exprs,
      )
    "Expr::RecordUpdate" => {
      collect_scoped_child_expr_json(expr, "record", shadowed, exprs)
      collect_scoped_field_def_expr_jsons(
        child(expr, "fields"),
        shadowed,
        exprs,
      )
    }
    "Expr::Mutate" => {
      collect_scoped_child_expr_json(expr, "record", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "field", shadowed, exprs)
    }
    "Expr::Match" => {
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
      collect_scoped_case_expr_jsons(child(expr, "cases"), shadowed, exprs)
    }
    "Expr::IsLexmatch" => {
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
      collect_scoped_lex_top_pattern_expr_jsons(
        child(expr, "pat"),
        shadowed,
        exprs,
      )
    }
    "Expr::Lexmatch" => {
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
      collect_scoped_lex_case_expr_jsons(child(expr, "cases"), shadowed, exprs)
    }
    "Expr::ListComprehension" => {
      let body_shadowed = collect_scoped_list_comprehension_kind_expr_jsons(
        child(expr, "kind"),
        shadowed,
        exprs,
      )
      collect_scoped_child_expr_json(expr, "guard", body_shadowed, exprs)
      collect_scoped_child_expr_json(expr, "body", body_shadowed, exprs)
    }
    "Expr::Try" => {
      collect_scoped_child_expr_json(expr, "body", shadowed, exprs)
      collect_scoped_case_expr_jsons(child(expr, "catch"), shadowed, exprs)
      if child(expr, "try_else") is Some(try_else) {
        collect_scoped_case_expr_jsons(Some(try_else), shadowed, exprs)
      }
    }
    "Expr::While" => {
      collect_scoped_child_expr_json(expr, "loop_cond", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "loop_body", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "while_else", shadowed, exprs)
    }
    "Expr::Break" =>
      collect_scoped_child_expr_json(expr, "arg", shadowed, exprs)
    "Expr::Defer" | "Expr::TemplateWriting" => {
      collect_scoped_child_expr_json(expr, "expr", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "body", shadowed, exprs)
      collect_scoped_child_expr_json(expr, "template", shadowed, exprs)
    }
    "Expr::Quantifier" => {
      let body_shadowed = shadowed_with_json_binder(
        shadowed,
        child(expr, "binder"),
      )
      collect_scoped_child_expr_json(expr, "body", body_shadowed, exprs)
    }
    "Expr::StaticAssert" =>
      collect_scoped_child_expr_json(expr, "body", shadowed, exprs)
    "Expr::Function" =>
      collect_scoped_func_body_expr_json(child(expr, "func"), shadowed, exprs)
    "Expr::LetFn" => {
      let name_shadowed = shadowed_with_json_binder(
        shadowed,
        child(expr, "name"),
      )
      collect_scoped_func_body_expr_json(
        child(expr, "func"),
        name_shadowed,
        exprs,
      )
      collect_scoped_child_expr_json(expr, "body", name_shadowed, exprs)
    }
    "Expr::LetAnd" => {
      let binding_shadowed = shadowed_with_json_let_and_bindings(
        shadowed,
        child(expr, "bindings"),
      )
      collect_scoped_let_and_binding_expr_jsons(
        child(expr, "bindings"),
        binding_shadowed,
        exprs,
      )
      collect_scoped_child_expr_json(expr, "body", binding_shadowed, exprs)
    }
    "Expr::Map" =>
      collect_scoped_map_elem_expr_jsons(child(expr, "elems"), shadowed, exprs)
    "Expr::MultilineString" =>
      collect_scoped_multiline_string_elem_expr_jsons(
        child(expr, "elems"),
        shadowed,
        exprs,
      )
    _ => ()
  }
}

///|
fn collect_scoped_child_expr_json(
  node : Json,
  name : String,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  match child(node, name) {
    Some(Null) | None => ()
    Some(expr) => collect_scoped_expr_jsons_with_shadow(expr, shadowed, exprs)
  }
}

///|
fn collect_scoped_expr_list_jsons(
  list : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(list, fn(item) {
    collect_scoped_expr_jsons_with_shadow(item, shadowed, exprs)
  })
}

///|
fn collect_scoped_argument_expr_jsons(
  args : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(args, fn(arg) {
    collect_scoped_child_expr_json(arg, "value", shadowed, exprs)
  })
}

///|
fn collect_scoped_spreadable_elem_expr_jsons(
  elems : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(elems, fn(elem) {
    match elem {
      { "kind": "SpreadableElem::Regular", .. } =>
        collect_scoped_child_expr_json(elem, "value", shadowed, exprs)
      { "kind": "SpreadableElem::Spread", .. } =>
        collect_scoped_child_expr_json(elem, "expr", shadowed, exprs)
      _ => ()
    }
  })
}

///|
fn collect_scoped_binder_expr_pair_jsons(
  pairs : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(pairs, fn(pair) {
    collect_scoped_child_expr_json(pair, "expr", shadowed, exprs)
  })
}

///|
fn collect_scoped_where_clause_expr_jsons(
  clause : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  match clause {
    Some(Null) | None => ()
    Some({ "children": { "fields": fields, .. }, .. }) =>
      collect_scoped_field_def_expr_jsons(Some(fields), shadowed, exprs)
    Some(_) => ()
  }
}

///|
fn collect_scoped_field_def_expr_jsons(
  fields : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(fields, fn(field) {
    collect_scoped_child_expr_json(field, "expr", shadowed, exprs)
  })
}

///|
fn collect_scoped_case_expr_jsons(
  cases : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(cases, fn(case) {
    let case_shadowed = shadowed_with_json_pattern(
      shadowed,
      child(case, "pattern"),
    )
    collect_scoped_child_expr_json(case, "guard", case_shadowed, exprs)
    collect_scoped_child_expr_json(case, "body", case_shadowed, exprs)
  })
}

///|
fn collect_scoped_interp_elem_expr_jsons(
  elems : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(elems, fn(elem) {
    match elem {
      { "kind": "InterpElem::Expr", "children": { "expr": expr, .. }, .. } =>
        collect_scoped_expr_jsons_with_shadow(expr, shadowed, exprs)
      _ => ()
    }
  })
}

///|
fn collect_scoped_multiline_string_elem_expr_jsons(
  elems : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(elems, fn(elem) {
    match elem {
      {
        "kind": "MultilineString::Interp",
        "children": { "value": value, .. },
        ..
      } => collect_scoped_interp_elem_expr_jsons(Some(value), shadowed, exprs)
      _ => ()
    }
  })
}

///|
fn collect_scoped_lex_case_expr_jsons(
  cases : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(cases, fn(case) {
    collect_scoped_lex_top_pattern_expr_jsons(
      child(case, "pat"),
      shadowed,
      exprs,
    )
    let case_shadowed = shadowed_with_json_lex_top_patterns(
      shadowed,
      child(case, "pat"),
    )
    collect_scoped_child_expr_json(case, "guard", case_shadowed, exprs)
    collect_scoped_child_expr_json(case, "body", case_shadowed, exprs)
  })
}

///|
fn collect_scoped_lex_top_pattern_expr_jsons(
  patterns : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(patterns, fn(pattern) {
    match pattern {
      {
        "kind": "LexTopPattern::Pattern",
        "children": { "value": value, .. },
        ..
      } => collect_scoped_lex_pattern_expr_json(Some(value), shadowed, exprs)
      _ => ()
    }
  })
}

///|
fn collect_scoped_lex_pattern_expr_json(
  pattern : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  match pattern {
    Some({ "kind": "LexPattern::Alias", "children": { "pat": pat, .. }, .. }) =>
      collect_scoped_lex_pattern_expr_json(Some(pat), shadowed, exprs)
    Some(
      {
        "kind": "LexPattern::RegexInterp",
        "children": { "elems": elems, .. },
        ..
      }
    ) => collect_scoped_interp_elem_expr_jsons(Some(elems), shadowed, exprs)
    Some(
      { "kind": "LexPattern::Sequence", "children": { "pats": pats, .. }, .. }
    ) =>
      collect_json_list_items(Some(pats), fn(pat) {
        collect_scoped_lex_pattern_expr_json(Some(pat), shadowed, exprs)
      })
    Some(_) | None => ()
  }
}

///|
fn collect_scoped_list_comprehension_kind_expr_jsons(
  kind : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Array[String] {
  match kind {
    Some(
      {
        "kind": "Expr::ListComprehension::Kind::For",
        "children": {
          "binders": binders,
          "condition": condition,
          "continue_block": continue_block,
          ..
        },
        ..
      }
    ) => {
      collect_scoped_binder_expr_pair_jsons(Some(binders), shadowed, exprs)
      let loop_shadowed = shadowed_with_json_binder_expr_pairs(
        shadowed,
        Some(binders),
      )
      collect_scoped_optional_expr_json(condition, loop_shadowed, exprs)
      collect_scoped_binder_expr_pair_jsons(
        Some(continue_block),
        loop_shadowed,
        exprs,
      )
      loop_shadowed
    }
    Some(
      {
        "kind": "Expr::ListComprehension::Kind::Foreach",
        "children": {
          "binders": binders,
          "expr": iter,
          "init": init,
          "continue_block": continue_block,
          ..
        },
        ..
      }
    ) => {
      collect_scoped_expr_jsons_with_shadow(iter, shadowed, exprs)
      collect_scoped_binder_expr_pair_jsons(Some(init), shadowed, exprs)
      let loop_shadowed = shadowed_with_json_optional_binders(
        shadowed,
        Some(binders),
      )
      add_json_binder_expr_pair_names(loop_shadowed, Some(init))
      collect_scoped_binder_expr_pair_jsons(
        Some(continue_block),
        loop_shadowed,
        exprs,
      )
      loop_shadowed
    }
    Some(_) | None => copy_shadowed_names(shadowed)
  }
}

///|
fn collect_scoped_optional_expr_json(
  expr : Json,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  match expr {
    Null => ()
    _ => collect_scoped_expr_jsons_with_shadow(expr, shadowed, exprs)
  }
}

///|
fn collect_scoped_func_body_expr_json(
  func : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  match func {
    Some(Null) | None => ()
    Some({ "children": { "parameters": parameters, "body": body, .. }, .. }) => {
      let body_shadowed = shadowed_with_json_parameters(
        shadowed,
        Some(parameters),
      )
      collect_scoped_expr_jsons_with_shadow(body, body_shadowed, exprs)
    }
    Some(_) => ()
  }
}

///|
fn collect_scoped_let_and_binding_expr_jsons(
  bindings : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(bindings, fn(binding) {
    collect_scoped_func_body_expr_json(child(binding, "func"), shadowed, exprs)
  })
}

///|
fn collect_scoped_map_elem_expr_jsons(
  elems : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  collect_json_list_items(elems, fn(elem) {
    collect_scoped_child_expr_json(elem, "expr", shadowed, exprs)
  })
}

///|
fn collect_scoped_regex_pattern_expr_json(
  pattern : Json?,
  shadowed : Array[String],
  exprs : Array[ScopedJsonExpr],
) -> Unit {
  match pattern {
    Some({ "kind": "RegexPattern::Alias", "children": { "pat": pat, .. }, .. }) =>
      collect_scoped_regex_pattern_expr_json(Some(pat), shadowed, exprs)
    Some(
      {
        "kind": "RegexPattern::Alternation",
        "children": { "pat1": pat1, "pat2": pat2, .. },
        ..
      }
    )
    | Some(
      {
        "kind": "RegexPattern::Sequence",
        "children": { "pat1": pat1, "pat2": pat2, .. },
        ..
      }
    ) => {
      collect_scoped_regex_pattern_expr_json(Some(pat1), shadowed, exprs)
      collect_scoped_regex_pattern_expr_json(Some(pat2), shadowed, exprs)
    }
    Some(_) | None => ()
  }
}

///|
fn copy_shadowed_names(names : Array[String]) -> Array[String] {
  let copied : Array[String] = []
  for name in names {
    copied.push(name)
  }
  copied
}

///|
fn add_shadowed_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn add_json_binder_name(names : Array[String], binder : Json?) -> Unit {
  if binder.bind(binder_name) is Some(name) {
    add_shadowed_name(names, name)
  }
}

///|
fn shadowed_with_json_binder(
  shadowed : Array[String],
  binder : Json?,
) -> Array[String] {
  let next = copy_shadowed_names(shadowed)
  add_json_binder_name(next, binder)
  next
}

///|
fn shadowed_with_json_pattern(
  shadowed : Array[String],
  pattern : Json?,
) -> Array[String] {
  let next = copy_shadowed_names(shadowed)
  add_json_pattern_names(next, pattern)
  next
}

///|
fn shadowed_with_json_parameters(
  shadowed : Array[String],
  parameters : Json?,
) -> Array[String] {
  let next = copy_shadowed_names(shadowed)
  collect_json_list_items(parameters, fn(parameter) {
    add_json_binder_name(next, child(parameter, "binder"))
  })
  next
}

///|
fn shadowed_with_json_binder_expr_pairs(
  shadowed : Array[String],
  pairs : Json?,
) -> Array[String] {
  let next = copy_shadowed_names(shadowed)
  add_json_binder_expr_pair_names(next, pairs)
  next
}

///|
fn shadowed_with_json_optional_binders(
  shadowed : Array[String],
  binders : Json?,
) -> Array[String] {
  let next = copy_shadowed_names(shadowed)
  collect_json_list_items(binders, fn(binder) {
    match binder {
      Null => ()
      _ => add_json_binder_name(next, Some(binder))
    }
  })
  next
}

///|
fn shadowed_with_json_let_and_bindings(
  shadowed : Array[String],
  bindings : Json?,
) -> Array[String] {
  let next = copy_shadowed_names(shadowed)
  collect_json_list_items(bindings, fn(binding) {
    add_json_binder_name(next, child(binding, "binder"))
  })
  next
}

///|
fn shadowed_with_json_lex_top_patterns(
  shadowed : Array[String],
  patterns : Json?,
) -> Array[String] {
  let next = copy_shadowed_names(shadowed)
  collect_json_list_items(patterns, fn(pattern) {
    add_json_lex_top_pattern_names(next, Some(pattern))
  })
  next
}

///|
fn add_json_binder_expr_pair_names(
  names : Array[String],
  pairs : Json?,
) -> Unit {
  collect_json_list_items(pairs, fn(pair) {
    add_json_binder_name(names, child(pair, "binder"))
  })
}

///|
fn add_json_pattern_names(names : Array[String], pattern : Json?) -> Unit {
  match pattern {
    Some({ "kind": "Pattern::Var", "children": { "value": value, .. }, .. }) =>
      add_json_binder_name(names, Some(value))
    Some(
      {
        "kind": "Pattern::Alias",
        "children": { "pat": pat, "alias": alias_json, .. },
        ..
      }
    ) => {
      add_json_pattern_names(names, Some(pat))
      add_json_binder_name(names, Some(alias_json))
    }
    Some({ "kind": "Pattern::Constraint", "children": { "pat": pat, .. }, .. }) =>
      add_json_pattern_names(names, Some(pat))
    Some(
      {
        "kind": "Pattern::Or",
        "children": { "pat1": pat1, "pat2": pat2, .. },
        ..
      }
    ) => {
      add_json_pattern_names(names, Some(pat1))
      add_json_pattern_names(names, Some(pat2))
    }
    Some(
      {
        "kind": "Pattern::Range",
        "children": { "lhs": lhs, "rhs": rhs, .. },
        ..
      }
    ) => {
      add_json_pattern_names(names, Some(lhs))
      add_json_pattern_names(names, Some(rhs))
    }
    Some(
      {
        "kind": "Pattern::SpecialConstr",
        "children": { "binder": binder, "args": args, .. },
        ..
      }
    ) => {
      add_json_binder_name(names, Some(binder))
      add_json_binder_nodes(names, Some(args))
    }
    Some({ "kind": "Pattern::Array", .. })
    | Some({ "kind": "Pattern::Constr", .. })
    | Some({ "kind": "Pattern::Map", .. })
    | Some({ "kind": "Pattern::Record", .. })
    | Some({ "kind": "Pattern::Tuple", .. }) =>
      add_json_binder_nodes(names, pattern)
    Some(_) | None => ()
  }
}

///|
fn add_json_binder_nodes(names : Array[String], value : Json?) -> Unit {
  match value {
    Some({ "kind": "Binder", .. } as binder) =>
      add_json_binder_name(names, Some(binder))
    Some(Object(fields)) =>
      for key, field in fields {
        if key != "loc" {
          add_json_binder_nodes(names, Some(field))
        }
      }
    Some(Array(items)) =>
      for item in items {
        add_json_binder_nodes(names, Some(item))
      }
    Some(_) | None => ()
  }
}

///|
fn add_json_lex_top_pattern_names(
  names : Array[String],
  pattern : Json?,
) -> Unit {
  match pattern {
    Some(
      {
        "kind": "LexTopPattern::Binder",
        "children": { "value": value, .. },
        ..
      }
    ) => add_json_binder_name(names, Some(value))
    Some(
      {
        "kind": "LexTopPattern::Pattern",
        "children": { "value": value, .. },
        ..
      }
    ) => add_json_lex_pattern_names(names, Some(value))
    Some(_) | None => ()
  }
}

///|
fn add_json_lex_pattern_names(names : Array[String], pattern : Json?) -> Unit {
  match pattern {
    Some(
      {
        "kind": "LexPattern::Alias",
        "children": { "pat": pat, "binder": binder, .. },
        ..
      }
    ) => {
      add_json_lex_pattern_names(names, Some(pat))
      add_json_binder_name(names, Some(binder))
    }
    Some(
      { "kind": "LexPattern::Sequence", "children": { "pats": pats, .. }, .. }
    ) =>
      collect_json_list_items(Some(pats), fn(pat) {
        add_json_lex_pattern_names(names, Some(pat))
      })
    Some(_) | None => ()
  }
}

///|
fn collect_expr_json_children(
  expr : Json,
  kind : String,
  exprs : Array[Json],
) -> Unit {
  match kind {
    "Expr::Apply" => {
      collect_child_expr_json(expr, "func", exprs)
      collect_argument_expr_jsons(child(expr, "args"), exprs)
    }
    "Expr::DotApply" => {
      collect_child_expr_json(expr, "self", exprs)
      collect_argument_expr_jsons(child(expr, "args"), exprs)
    }
    "Expr::Field" => collect_child_expr_json(expr, "record", exprs)
    "Expr::Infix" | "Expr::Pipe" | "Expr::RevPipe" | "Expr::Implies" => {
      collect_child_expr_json(expr, "lhs", exprs)
      collect_child_expr_json(expr, "rhs", exprs)
    }
    "Expr::Unary"
    | "Expr::Assign"
    | "Expr::Is"
    | "Expr::RegexMatch"
    | "Expr::ProofAssert"
    | "Expr::ProofLet" => collect_child_expr_json(expr, "expr", exprs)
    "Expr::Array" | "Expr::Tuple" =>
      collect_expr_list_jsons(child(expr, "exprs"), exprs)
    "Expr::Continue" => collect_expr_list_jsons(child(expr, "args"), exprs)
    "Expr::Sequence" => {
      collect_expr_list_jsons(child(expr, "exprs"), exprs)
      collect_child_expr_json(expr, "last_expr", exprs)
    }
    "Expr::ArrayGet" => {
      collect_child_expr_json(expr, "array", exprs)
      collect_child_expr_json(expr, "index", exprs)
    }
    "Expr::ArraySet" | "Expr::ArrayAugmentedSet" => {
      collect_child_expr_json(expr, "array", exprs)
      collect_child_expr_json(expr, "index", exprs)
      collect_child_expr_json(expr, "value", exprs)
    }
    "Expr::ArraySpread" =>
      collect_spreadable_elem_expr_jsons(child(expr, "elems"), exprs)
    "Expr::ArrayGetSlice" => {
      collect_child_expr_json(expr, "array", exprs)
      collect_child_expr_json(expr, "start_index", exprs)
      collect_child_expr_json(expr, "end_index", exprs)
    }
    "Expr::Group" | "Expr::Constraint" | "Expr::As" | "Expr::TryOperator" =>
      collect_child_expr_json(expr, "expr", exprs)
    "Expr::If" => {
      collect_child_expr_json(expr, "cond", exprs)
      collect_child_expr_json(expr, "ifso", exprs)
      collect_child_expr_json(expr, "ifnot", exprs)
    }
    "Expr::Guard" => {
      collect_child_expr_json(expr, "cond", exprs)
      collect_child_expr_json(expr, "otherwise", exprs)
      collect_child_expr_json(expr, "body", exprs)
    }
    "Expr::Let" | "Expr::LetMut" => {
      collect_child_expr_json(expr, "expr", exprs)
      collect_child_expr_json(expr, "body", exprs)
    }
    "Expr::For" => {
      collect_binder_expr_pair_jsons(child(expr, "binders"), exprs)
      collect_child_expr_json(expr, "condition", exprs)
      collect_binder_expr_pair_jsons(child(expr, "continue_block"), exprs)
      collect_child_expr_json(expr, "body", exprs)
      collect_child_expr_json(expr, "for_else", exprs)
      collect_where_clause_expr_jsons(child(expr, "where_clause"), exprs)
    }
    "Expr::ForEach" => {
      collect_child_expr_json(expr, "expr", exprs)
      collect_binder_expr_pair_jsons(child(expr, "init"), exprs)
      collect_binder_expr_pair_jsons(child(expr, "continue_block"), exprs)
      collect_child_expr_json(expr, "body", exprs)
      collect_child_expr_json(expr, "else_block", exprs)
      collect_where_clause_expr_jsons(child(expr, "where_clause"), exprs)
    }
    "Expr::Return" => collect_child_expr_json(expr, "return_value", exprs)
    "Expr::Raise" => collect_child_expr_json(expr, "err_value", exprs)
    "Expr::Interp" =>
      collect_interp_elem_expr_jsons(child(expr, "elems"), exprs)
    "Expr::Record" => collect_field_def_expr_jsons(child(expr, "fields"), exprs)
    "Expr::RecordUpdate" => {
      collect_child_expr_json(expr, "record", exprs)
      collect_field_def_expr_jsons(child(expr, "fields"), exprs)
    }
    "Expr::Mutate" => {
      collect_child_expr_json(expr, "record", exprs)
      collect_child_expr_json(expr, "field", exprs)
    }
    "Expr::Match" => {
      collect_child_expr_json(expr, "expr", exprs)
      collect_case_expr_jsons(child(expr, "cases"), exprs)
    }
    "Expr::IsLexmatch" => {
      collect_child_expr_json(expr, "expr", exprs)
      collect_lex_top_pattern_expr_jsons(child(expr, "pat"), exprs)
    }
    "Expr::Lexmatch" => {
      collect_child_expr_json(expr, "expr", exprs)
      collect_lex_case_expr_jsons(child(expr, "cases"), exprs)
    }
    "Expr::ListComprehension" => {
      collect_list_comprehension_kind_expr_jsons(child(expr, "kind"), exprs)
      collect_child_expr_json(expr, "guard", exprs)
      collect_child_expr_json(expr, "body", exprs)
    }
    "Expr::Try" => {
      collect_child_expr_json(expr, "body", exprs)
      collect_case_expr_jsons(child(expr, "catch"), exprs)
      if child(expr, "try_else") is Some(try_else) {
        collect_case_expr_jsons(Some(try_else), exprs)
      }
    }
    "Expr::While" => {
      collect_child_expr_json(expr, "loop_cond", exprs)
      collect_child_expr_json(expr, "loop_body", exprs)
      collect_child_expr_json(expr, "while_else", exprs)
    }
    "Expr::Break" => collect_child_expr_json(expr, "arg", exprs)
    "Expr::Defer" | "Expr::TemplateWriting" => {
      collect_child_expr_json(expr, "expr", exprs)
      collect_child_expr_json(expr, "body", exprs)
      collect_child_expr_json(expr, "template", exprs)
    }
    "Expr::Quantifier" | "Expr::StaticAssert" =>
      collect_child_expr_json(expr, "body", exprs)
    "Expr::Function" => collect_func_body_expr_json(child(expr, "func"), exprs)
    "Expr::LetFn" => {
      collect_func_body_expr_json(child(expr, "func"), exprs)
      collect_child_expr_json(expr, "body", exprs)
    }
    "Expr::LetAnd" => {
      collect_let_and_binding_expr_jsons(child(expr, "bindings"), exprs)
      collect_child_expr_json(expr, "body", exprs)
    }
    "Expr::Map" => collect_map_elem_expr_jsons(child(expr, "elems"), exprs)
    "Expr::MultilineString" =>
      collect_multiline_string_elem_expr_jsons(child(expr, "elems"), exprs)
    _ => ()
  }
}

///|
fn collect_child_expr_json(
  node : Json,
  name : String,
  exprs : Array[Json],
) -> Unit {
  match child(node, name) {
    Some(Null) | None => ()
    Some(expr) => collect_expr_jsons(expr, exprs)
  }
}

///|
fn collect_expr_list_jsons(list : Json?, exprs : Array[Json]) -> Unit {
  collect_json_list_items(list, fn(item) { collect_expr_jsons(item, exprs) })
}

///|
fn collect_argument_expr_jsons(args : Json?, exprs : Array[Json]) -> Unit {
  collect_json_list_items(args, fn(arg) {
    collect_child_expr_json(arg, "value", exprs)
  })
}

///|
fn collect_spreadable_elem_expr_jsons(
  elems : Json?,
  exprs : Array[Json],
) -> Unit {
  collect_json_list_items(elems, fn(elem) {
    match elem {
      { "kind": "SpreadableElem::Regular", .. } =>
        collect_child_expr_json(elem, "value", exprs)
      { "kind": "SpreadableElem::Spread", .. } =>
        collect_child_expr_json(elem, "expr", exprs)
      _ => ()
    }
  })
}

///|
fn collect_binder_expr_pair_jsons(pairs : Json?, exprs : Array[Json]) -> Unit {
  collect_json_list_items(pairs, fn(pair) {
    collect_child_expr_json(pair, "expr", exprs)
  })
}

///|
fn collect_where_clause_expr_jsons(clause : Json?, exprs : Array[Json]) -> Unit {
  match clause {
    Some(Null) | None => ()
    Some({ "children": { "fields": fields, .. }, .. }) =>
      collect_field_def_expr_jsons(Some(fields), exprs)
    Some(_) => ()
  }
}

///|
fn collect_field_def_expr_jsons(fields : Json?, exprs : Array[Json]) -> Unit {
  collect_json_list_items(fields, fn(field) {
    collect_child_expr_json(field, "expr", exprs)
  })
}

///|
fn collect_case_expr_jsons(cases : Json?, exprs : Array[Json]) -> Unit {
  collect_json_list_items(cases, fn(case) {
    collect_child_expr_json(case, "guard", exprs)
    collect_child_expr_json(case, "body", exprs)
  })
}

///|
fn collect_interp_elem_expr_jsons(elems : Json?, exprs : Array[Json]) -> Unit {
  collect_json_list_items(elems, fn(elem) {
    match elem {
      { "kind": "InterpElem::Expr", "children": { "expr": expr, .. }, .. } =>
        collect_expr_jsons(expr, exprs)
      _ => ()
    }
  })
}

///|
fn collect_multiline_string_elem_expr_jsons(
  elems : Json?,
  exprs : Array[Json],
) -> Unit {
  collect_json_list_items(elems, fn(elem) {
    match elem {
      {
        "kind": "MultilineString::Interp",
        "children": { "value": value, .. },
        ..
      } => collect_interp_elem_expr_jsons(Some(value), exprs)
      _ => ()
    }
  })
}

///|
fn collect_lex_case_expr_jsons(cases : Json?, exprs : Array[Json]) -> Unit {
  collect_json_list_items(cases, fn(case) {
    collect_lex_top_pattern_expr_jsons(child(case, "pat"), exprs)
    collect_child_expr_json(case, "guard", exprs)
    collect_child_expr_json(case, "body", exprs)
  })
}

///|
fn collect_lex_top_pattern_expr_jsons(
  patterns : Json?,
  exprs : Array[Json],
) -> Unit {
  collect_json_list_items(patterns, fn(pattern) {
    match pattern {
      {
        "kind": "LexTopPattern::Pattern",
        "children": { "value": value, .. },
        ..
      } => collect_lex_pattern_expr_json(Some(value), exprs)
      _ => ()
    }
  })
}

///|
fn collect_lex_pattern_expr_json(pattern : Json?, exprs : Array[Json]) -> Unit {
  match pattern {
    Some({ "kind": "LexPattern::Alias", "children": { "pat": pat, .. }, .. }) =>
      collect_lex_pattern_expr_json(Some(pat), exprs)
    Some(
      {
        "kind": "LexPattern::RegexInterp",
        "children": { "elems": elems, .. },
        ..
      }
    ) => collect_interp_elem_expr_jsons(Some(elems), exprs)
    Some(
      { "kind": "LexPattern::Sequence", "children": { "pats": pats, .. }, .. }
    ) =>
      collect_json_list_items(Some(pats), fn(pat) {
        collect_lex_pattern_expr_json(Some(pat), exprs)
      })
    Some(_) | None => ()
  }
}

///|
fn collect_list_comprehension_kind_expr_jsons(
  kind : Json?,
  exprs : Array[Json],
) -> Unit {
  match kind {
    Some(
      {
        "kind": "Expr::ListComprehension::Kind::For",
        "children": {
          "binders": binders,
          "condition": condition,
          "continue_block": continue_block,
          ..
        },
        ..
      }
    ) => {
      collect_binder_expr_pair_jsons(Some(binders), exprs)
      collect_optional_expr_json(condition, exprs)
      collect_binder_expr_pair_jsons(Some(continue_block), exprs)
    }
    Some(
      {
        "kind": "Expr::ListComprehension::Kind::Foreach",
        "children": {
          "expr": expr,
          "init": init,
          "continue_block": continue_block,
          ..
        },
        ..
      }
    ) => {
      collect_expr_jsons(expr, exprs)
      collect_binder_expr_pair_jsons(Some(init), exprs)
      collect_binder_expr_pair_jsons(Some(continue_block), exprs)
    }
    Some(_) | None => ()
  }
}

///|
fn collect_optional_expr_json(expr : Json, exprs : Array[Json]) -> Unit {
  match expr {
    Null => ()
    _ => collect_expr_jsons(expr, exprs)
  }
}

///|
fn collect_func_body_expr_json(func : Json?, exprs : Array[Json]) -> Unit {
  match func {
    Some(Null) | None => ()
    Some({ "children": { "body": body, .. }, .. }) =>
      collect_expr_jsons(body, exprs)
    Some(_) => ()
  }
}

///|
fn collect_let_and_binding_expr_jsons(
  bindings : Json?,
  exprs : Array[Json],
) -> Unit {
  collect_json_list_items(bindings, fn(binding) {
    collect_func_body_expr_json(child(binding, "func"), exprs)
  })
}

///|
fn collect_map_elem_expr_jsons(elems : Json?, exprs : Array[Json]) -> Unit {
  collect_json_list_items(elems, fn(elem) {
    collect_child_expr_json(elem, "expr", exprs)
  })
}

///|
fn collect_json_list_items(list : Json?, f : (Json) -> Unit) -> Unit {
  match list {
    Some({ "children": Array(items), .. }) =>
      for item in items {
        f(item)
      }
    Some(_) | None => ()
  }
}
