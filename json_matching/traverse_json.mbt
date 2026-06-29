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
