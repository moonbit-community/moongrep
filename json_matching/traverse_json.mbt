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
    match json_kind(elem) {
      Some("SpreadableElem::Regular") =>
        collect_child_expr_json(elem, "value", exprs)
      Some("SpreadableElem::Spread") =>
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
    Some(clause) => collect_field_def_expr_jsons(child(clause, "fields"), exprs)
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
    if json_kind(elem) == Some("InterpElem::Expr") {
      collect_child_expr_json(elem, "expr", exprs)
    }
  })
}

///|
fn collect_multiline_string_elem_expr_jsons(
  elems : Json?,
  exprs : Array[Json],
) -> Unit {
  collect_json_list_items(elems, fn(elem) {
    if json_kind(elem) == Some("MultilineString::Interp") {
      collect_interp_elem_expr_jsons(child(elem, "value"), exprs)
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
    if json_kind(pattern) == Some("LexTopPattern::Pattern") {
      collect_lex_pattern_expr_json(child(pattern, "value"), exprs)
    }
  })
}

///|
fn collect_lex_pattern_expr_json(pattern : Json?, exprs : Array[Json]) -> Unit {
  match pattern {
    Some(pattern) =>
      match json_kind(pattern) {
        Some("LexPattern::Alias") =>
          collect_lex_pattern_expr_json(child(pattern, "pat"), exprs)
        Some("LexPattern::RegexInterp") =>
          collect_interp_elem_expr_jsons(child(pattern, "elems"), exprs)
        Some("LexPattern::Sequence") =>
          collect_json_list_items(child(pattern, "pats"), fn(pat) {
            collect_lex_pattern_expr_json(Some(pat), exprs)
          })
        _ => ()
      }
    None => ()
  }
}

///|
fn collect_list_comprehension_kind_expr_jsons(
  kind : Json?,
  exprs : Array[Json],
) -> Unit {
  match kind {
    Some(kind) =>
      match json_kind(kind) {
        Some("Expr::ListComprehension::Kind::For") => {
          collect_binder_expr_pair_jsons(child(kind, "binders"), exprs)
          collect_child_expr_json(kind, "condition", exprs)
          collect_binder_expr_pair_jsons(child(kind, "continue_block"), exprs)
        }
        Some("Expr::ListComprehension::Kind::Foreach") => {
          collect_child_expr_json(kind, "expr", exprs)
          collect_binder_expr_pair_jsons(child(kind, "init"), exprs)
          collect_binder_expr_pair_jsons(child(kind, "continue_block"), exprs)
        }
        _ => ()
      }
    None => ()
  }
}

///|
fn collect_func_body_expr_json(func : Json?, exprs : Array[Json]) -> Unit {
  match func {
    Some(Null) | None => ()
    Some(func) => collect_child_expr_json(func, "body", exprs)
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
    Some(value) =>
      match node_children(value) {
        Some(Array(items)) =>
          for item in items {
            f(item)
          }
        _ => ()
      }
    None => ()
  }
}
