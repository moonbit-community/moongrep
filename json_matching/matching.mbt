///|
/// Returns whether `candidate` has the same AST JSON shape as `pattern`.
///
/// This convenience entry point does not enable declared metavars. It still
/// treats identifiers made entirely of two or more underscores as ignore
/// placeholders.
pub fn expr_matches(pattern : Json, candidate : Json) -> Bool {
  let compiled : CompiledJsonExprPattern = {
    ast: pattern,
    expr_metavars: [],
    identifier_metavars: [],
    constant_metavars: [],
    target_metavar: None,
    source_metavar: None,
  }
  match_expr_pattern(compiled, candidate) is Some(_)
}

///|
/// Matches `candidate` against a compiled parser-AST JSON expression pattern.
///
/// This attempts a single root-level match of `compiled.ast` against
/// `candidate`. It does not traverse candidate descendants.
pub fn match_expr_pattern(
  compiled : CompiledJsonExprPattern,
  candidate : Json,
) -> JsonExprMatch? {
  let bindings : @hashmap.HashMap[String, JsonBoundValue] = @hashmap.HashMap([])
  match_expr_pattern_with_bindings(compiled, candidate, bindings)
}

///|
/// Matches with a caller-supplied binding context.
///
/// The input map is copied before matching, so failed attempts cannot mutate
/// the caller's context.
pub fn match_expr_pattern_with_bindings(
  compiled : CompiledJsonExprPattern,
  candidate : Json,
  initial_bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> JsonExprMatch? {
  let bindings = initial_bindings.copy()
  if match_json(compiled.ast, candidate, compiled, bindings) {
    Some({ root: candidate, bindings })
  } else {
    None
  }
}

///|
/// Matches a parser expression by first converting it to parser AST JSON.
pub fn match_expr_pattern_ast(
  compiled : CompiledJsonExprPattern,
  candidate : @syntax.Expr,
) -> JsonExprMatch? {
  match_expr_pattern(compiled, candidate.to_json())
}

///|
/// Matches a parser expression with a caller-supplied JSON binding context.
pub fn match_expr_pattern_ast_with_bindings(
  compiled : CompiledJsonExprPattern,
  candidate : @syntax.Expr,
  initial_bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> JsonExprMatch? {
  match_expr_pattern_with_bindings(
    compiled,
    candidate.to_json(),
    initial_bindings,
  )
}

///|
/// Converts an AST compiled pattern to its JSON equivalent.
pub fn compiled_expr_pattern_to_json(
  compiled : @matching.CompiledExprPattern,
) -> CompiledJsonExprPattern {
  {
    ast: compiled.ast.to_json(),
    expr_metavars: compiled.expr_metavars,
    identifier_metavars: compiled.identifier_metavars,
    constant_metavars: compiled.constant_metavars,
    target_metavar: compiled.target_metavar,
    source_metavar: compiled.source_metavar,
  }
}

///|
/// Returns the textual value used by rule guards for a JSON constant capture.
pub fn json_constant_guard_value(constant : Json) -> String? {
  match constant {
    { "kind": String(kind), "children": { "value": value, .. }, .. } =>
      if kind.has_prefix("Constant::") {
        constant_value_text(value)
      } else {
        None
      }
    _ => None
  }
}

///|
fn constant_value_text(value : Json) -> String? {
  match value {
    String(value) => Some(value)
    True => Some("true")
    False => Some("false")
    Number(_, repr=Some(raw)) => Some(raw)
    Number(value, repr=None) => Some(value.to_string())
    _ => None
  }
}

///|
/// Compares two JSON values exactly, including source locations.
pub fn json_exact_equal(left : Json, right : Json) -> Bool {
  json_value_equal_plain(left, right)
}

///|
fn match_json(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  if match_expr_placeholder(pattern, candidate, compiled, bindings)
    is Some(result) {
    result
  } else {
    match json_kind(pattern) {
      Some("Pattern::Var") =>
        match_pattern_var(pattern, candidate, compiled, bindings)
      Some(pattern_kind) =>
        if json_kind(candidate) is Some(candidate_kind) {
          if pattern_kind != candidate_kind {
            false
          } else {
            match pattern_kind {
              "Var" => match_var(pattern, candidate, compiled, bindings)
              "LongIdent::Ident" | "LongIdent::Dot" =>
                match_long_ident(pattern, candidate, compiled, bindings)
              "Binder" => match_binder(pattern, candidate, compiled, bindings)
              "Label" => match_label(pattern, candidate, compiled, bindings)
              "Constructor" =>
                match_constructor(pattern, candidate, compiled, bindings)
              "TypeName" =>
                match_type_name(pattern, candidate, compiled, bindings)
              "Expr::Let" =>
                match_let_expr(pattern, candidate, compiled, bindings)
              "InterpElem::Source" => true
              _ =>
                match_structured_node(
                  pattern, candidate, pattern_kind, compiled, bindings,
                )
            }
          }
        } else {
          false
        }
      None => json_value_equal(pattern, candidate, compiled, bindings)
    }
  }
}

///|
fn match_expr_placeholder(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool? {
  match pattern {
    { "kind": "Expr::Ident", "children": { "id": id, .. }, .. } =>
      if normalized_var(id) is Some(name) {
        if is_ignore_placeholder(name) {
          Some(true)
        } else if is_special_expr_metavar(compiled, name) ||
          contains_name(compiled.expr_metavars, name) {
          Some(bind_value(bindings, name, Expr(candidate)))
        } else if contains_name(compiled.identifier_metavars, name) {
          if normalized_expr(candidate) is Some(candidate_name) {
            Some(bind_value(bindings, name, Identifier(candidate_name)))
          } else {
            Some(false)
          }
        } else if contains_name(compiled.constant_metavars, name) {
          if expr_constant(candidate) is Some(constant) {
            Some(bind_value(bindings, name, Constant(constant)))
          } else {
            Some(false)
          }
        } else {
          None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
fn match_pattern_var(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match pattern {
    { "kind": "Pattern::Var", "children": { "value": value, .. }, .. } =>
      if binder_name(value) is Some(name) {
        if parse_pattern_metavar_name(name) is Some(meta_name) {
          bind_value(bindings, meta_name, Pattern(candidate))
        } else if is_ignore_placeholder(name) {
          true
        } else if contains_name(compiled.identifier_metavars, name) {
          if normalized_pattern(candidate) is Some(candidate_name) {
            bind_value(bindings, name, Identifier(candidate_name))
          } else {
            false
          }
        } else if contains_name(compiled.constant_metavars, name) {
          if pattern_constant(candidate) is Some(constant) {
            bind_value(bindings, name, Constant(constant))
          } else {
            false
          }
        } else {
          json_kind(candidate) == Some("Pattern::Var") &&
          child(candidate, "value").bind(binder_name) == Some(name)
        }
      } else {
        false
      }
    _ => false
  }
}

///|
fn match_let_expr(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match (pattern, candidate) {
    (
      {
        "children": {
          "pattern": pattern_pat,
          "expr": pattern_expr,
          "body": pattern_body,
          ..
        },
        ..
      },
      {
        "children": {
          "pattern": candidate_pat,
          "expr": candidate_expr,
          "body": candidate_body,
          ..
        },
        ..
      },
    ) =>
      match_json(pattern_pat, candidate_pat, compiled, bindings) &&
      match_json(pattern_expr, candidate_expr, compiled, bindings) &&
      (
        is_faked_unit(pattern_body) ||
        match_json(pattern_body, candidate_body, compiled, bindings)
      )
    _ => false
  }
}

///|
fn match_structured_node(
  pattern : Json,
  candidate : Json,
  node_kind : String,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match (pattern, candidate) {
    (
      { "children": Object(pattern_children), .. },
      { "children": Object(candidate_children), .. },
    ) =>
      match_child_object(
        pattern_children, candidate_children, node_kind, compiled, bindings,
      )
    (
      { "children": Array(pattern_items), .. },
      { "children": Array(candidate_items), .. },
    ) => match_json_array(pattern_items, candidate_items, compiled, bindings)
    ({ "children": left, .. }, { "children": right, .. }) =>
      json_value_equal(left, right, compiled, bindings)
    _ => false
  }
}

///|
fn match_child_object(
  pattern_children : Map[String, Json],
  candidate_children : Map[String, Json],
  node_kind : String,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  for key, pattern_value in pattern_children {
    if !ignore_child_key(node_kind, key) {
      if candidate_children.get(key) is Some(candidate_value) {
        if optional_location_key(key) {
          if json_has_value(pattern_value) != json_has_value(candidate_value) {
            return false
          }
        } else if !match_json(
            pattern_value, candidate_value, compiled, bindings,
          ) {
          return false
        }
      } else {
        return false
      }
    }
  }
  for key, _ in candidate_children {
    if !ignore_child_key(node_kind, key) && !pattern_children.contains(key) {
      return false
    }
  }
  true
}

///|
fn ignore_child_key(node_kind : String, key : String) -> Bool {
  key == "loc" ||
  (node_kind == "Expr::Apply" && key == "attr") ||
  (node_kind.has_prefix("Func::") && key == "has_error")
}

///|
fn optional_location_key(key : String) -> Bool {
  key == "is_async" || key.has_suffix("_loc")
}

///|
fn json_has_value(value : Json) -> Bool {
  match value {
    Null => false
    _ => true
  }
}

///|
fn match_var(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match (pattern, candidate) {
    (
      { "children": { "name": pattern_name, .. }, .. },
      { "children": { "name": candidate_name, .. }, .. },
    ) => match_long_ident(pattern_name, candidate_name, compiled, bindings)
    _ => false
  }
}

///|
fn match_long_ident(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match pattern {
    {
      "kind": "LongIdent::Ident",
      "children": { "value": String(pattern_name), .. },
      ..
    } =>
      if normalized_long_ident(candidate) is Some(candidate_name) {
        match_identifier_name(
          pattern_name, candidate_name, candidate_name, compiled, bindings,
        )
      } else {
        false
      }
    {
      "kind": "LongIdent::Dot",
      "children": { "pkg": String(pattern_pkg), "id": String(pattern_id), .. },
      ..
    } =>
      match candidate {
        {
          "children": {
            "pkg": String(candidate_pkg),
            "id": String(candidate_id),
            ..
          },
          ..
        } =>
          if normalized_long_ident(candidate) is Some(candidate_name) {
            pattern_pkg == candidate_pkg &&
            match_identifier_name(
              pattern_id, candidate_id, candidate_name, compiled, bindings,
            )
          } else {
            false
          }
        _ => false
      }
    _ => false
  }
}

///|
fn match_binder(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match (binder_name(pattern), binder_name(candidate)) {
    (Some(pattern_name), Some(candidate_name)) =>
      match_identifier_name(
        pattern_name, candidate_name, candidate_name, compiled, bindings,
      )
    _ => false
  }
}

///|
fn match_label(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match (label_name(pattern), label_name(candidate)) {
    (Some(pattern_name), Some(candidate_name)) =>
      match_identifier_name(
        pattern_name, candidate_name, candidate_name, compiled, bindings,
      )
    _ => false
  }
}

///|
fn match_type_name(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match (pattern, candidate) {
    (
      {
        "children": { "is_object": pattern_is_object, "name": pattern_name, .. },
        ..
      },
      {
        "children": {
          "is_object": candidate_is_object,
          "name": candidate_name,
          ..
        },
        ..
      },
    ) =>
      match (json_bool(pattern_is_object), json_bool(candidate_is_object)) {
        (Some(pattern_is_object), Some(candidate_is_object)) =>
          pattern_is_object == candidate_is_object &&
          match_long_ident(pattern_name, candidate_name, compiled, bindings)
        _ => false
      }
    _ => false
  }
}

///|
fn match_constructor(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match (pattern, candidate) {
    (
      {
        "children": {
          "name": pattern_name_json,
          "extra_info": pattern_extra,
          ..
        },
        ..
      },
      {
        "children": {
          "name": candidate_name_json,
          "extra_info": candidate_extra,
          ..
        },
        ..
      },
    ) =>
      match (constr_name(pattern_name_json), constr_name(candidate_name_json)) {
        (Some(pattern_name), Some(candidate_name)) =>
          if contains_name(compiled.identifier_metavars, pattern_name) {
            if normalized_constructor(candidate) is Some(candidate_normalized) {
              let extra_matches = if json_kind(pattern_extra) ==
                Some("ConstructorExtraInfo::NoExtraInfo") {
                true
              } else {
                match_constructor_extra_info(
                  pattern_extra, candidate_extra, compiled, bindings,
                )
              }
              extra_matches &&
              bind_value(
                bindings,
                pattern_name,
                Identifier(candidate_normalized),
              )
            } else {
              false
            }
          } else if is_ignore_placeholder(pattern_name) {
            true
          } else {
            pattern_name == candidate_name &&
            match_constructor_extra_info(
              pattern_extra, candidate_extra, compiled, bindings,
            )
          }
        _ => false
      }
    _ => false
  }
}

///|
fn match_constructor_extra_info(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match (pattern, candidate) {
    (
      { "kind": "ConstructorExtraInfo::NoExtraInfo", .. },
      { "kind": "ConstructorExtraInfo::NoExtraInfo", .. },
    ) => true
    (
      {
        "kind": "ConstructorExtraInfo::Package",
        "children": { "value": String(pattern_value), .. },
        ..
      },
      {
        "kind": "ConstructorExtraInfo::Package",
        "children": { "value": String(candidate_value), .. },
        ..
      },
    ) => pattern_value == candidate_value
    (
      {
        "kind": "ConstructorExtraInfo::TypeName",
        "children": { "value": pattern_type, .. },
        ..
      },
      {
        "kind": "ConstructorExtraInfo::TypeName",
        "children": { "value": candidate_type, .. },
        ..
      },
    ) => match_type_name(pattern_type, candidate_type, compiled, bindings)
    (
      {
        "kind": "ConstructorExtraInfo::TypeNameWithConstrPackage",
        "children": {
          "pkg": String(pattern_pkg),
          "type_name": pattern_type,
          ..
        },
        ..
      },
      {
        "kind": "ConstructorExtraInfo::TypeNameWithConstrPackage",
        "children": {
          "pkg": String(candidate_pkg),
          "type_name": candidate_type,
          ..
        },
        ..
      },
    ) => {
      let pkg_matches = pattern_pkg == candidate_pkg
      let type_matches = match_type_name(
        pattern_type, candidate_type, compiled, bindings,
      )
      pkg_matches && type_matches
    }
    _ => false
  }
}

///|
fn match_identifier_name(
  pattern_name : String,
  literal_candidate_name : String,
  bound_candidate_name : String,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  if is_ignore_placeholder(pattern_name) {
    true
  } else if contains_name(compiled.identifier_metavars, pattern_name) {
    bind_value(bindings, pattern_name, Identifier(bound_candidate_name))
  } else {
    pattern_name == literal_candidate_name
  }
}

///|
fn bind_value(
  bindings : @hashmap.HashMap[String, JsonBoundValue],
  name : String,
  value : JsonBoundValue,
) -> Bool {
  if bindings.get(name) is Some(existing) {
    bound_value_equal(existing, value)
  } else {
    bindings[name] = value
    true
  }
}

///|
fn bound_value_equal(left : JsonBoundValue, right : JsonBoundValue) -> Bool {
  match (left, right) {
    (Expr(left), Expr(right)) => expr_equal_ignoring_loc(left, right)
    (Identifier(left), Identifier(right)) => left == right
    (Constant(left), Constant(right)) => json_value_equal_plain(left, right)
    (Pattern(left), Pattern(right)) => pattern_equal_ignoring_loc(left, right)
    _ => false
  }
}

///|
fn expr_equal_ignoring_loc(left : Json, right : Json) -> Bool {
  match (json_kind(left), json_kind(right)) {
    (Some(left_kind), Some(right_kind)) =>
      if left_kind != right_kind {
        false
      } else {
        match left_kind {
          "Expr::Ident" =>
            option_match(child(left, "id"), child(right, "id"), var_equal_plain)
          "Expr::Hole" =>
            option_match(
              child(left, "kind"),
              child(right, "kind"),
              node_kind_equal,
            )
          "Expr::Constant" =>
            option_match(
              child(left, "constant"),
              child(right, "constant"),
              json_value_equal_plain,
            )
          "Expr::Infix" =>
            option_match(child(left, "op"), child(right, "op"), var_equal_plain) &&
            option_match(
              child(left, "lhs"),
              child(right, "lhs"),
              expr_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "rhs"),
              child(right, "rhs"),
              expr_equal_ignoring_loc,
            )
          "Expr::Apply" =>
            option_match(
              child(left, "func"),
              child(right, "func"),
              expr_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "args"),
              child(right, "args"),
              argument_list_equal_ignoring_loc,
            )
          "Expr::DotApply" =>
            option_match(
              child(left, "self"),
              child(right, "self"),
              expr_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "method_name"),
              child(right, "method_name"),
              label_equal_plain,
            ) &&
            option_match(
              child(left, "args"),
              child(right, "args"),
              argument_list_equal_ignoring_loc,
            ) &&
            child(left, "return_self") == child(right, "return_self")
          "Expr::Field" =>
            option_match(
              child(left, "record"),
              child(right, "record"),
              expr_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "accessor"),
              child(right, "accessor"),
              json_value_equal_ignoring_loc,
            )
          "Expr::Method" =>
            option_match(
              child(left, "type_name"),
              child(right, "type_name"),
              type_name_equal_plain,
            ) &&
            option_match(
              child(left, "method_name"),
              child(right, "method_name"),
              label_equal_plain,
            )
          "Expr::Constr" =>
            option_match(
              child(left, "constr"),
              child(right, "constr"),
              constructor_equal_plain,
            )
          "Expr::Array" | "Expr::Tuple" =>
            option_match(
              child(left, "exprs"),
              child(right, "exprs"),
              expr_list_equal_ignoring_loc,
            )
          "Expr::Group" =>
            child(left, "group") == child(right, "group") &&
            option_match(
              child(left, "expr"),
              child(right, "expr"),
              expr_equal_ignoring_loc,
            )
          "Expr::Sequence" =>
            option_match(
              child(left, "exprs"),
              child(right, "exprs"),
              expr_list_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "last_expr"),
              child(right, "last_expr"),
              expr_equal_ignoring_loc,
            )
          "Expr::For" =>
            option_match(
              child(left, "binders"),
              child(right, "binders"),
              binder_expr_list_equal,
            ) &&
            option_match(
              child(left, "condition"),
              child(right, "condition"),
              option_expr_equal,
            ) &&
            option_match(
              child(left, "continue_block"),
              child(right, "continue_block"),
              binder_expr_list_equal,
            ) &&
            option_match(
              child(left, "body"),
              child(right, "body"),
              expr_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "for_else"),
              child(right, "for_else"),
              option_expr_equal,
            )
          "Expr::Unit" => child(left, "faked") == child(right, "faked")
          _ => false
        }
      }
    _ => false
  }
}

///|
fn pattern_equal_ignoring_loc(left : Json, right : Json) -> Bool {
  match (json_kind(left), json_kind(right)) {
    (Some(left_kind), Some(right_kind)) =>
      if left_kind != right_kind {
        false
      } else {
        match left_kind {
          "Pattern::Var" =>
            child(left, "value").bind(binder_name) ==
            child(right, "value").bind(binder_name)
          "Pattern::Any" => true
          "Pattern::Alias" =>
            option_match(
              child(left, "pat"),
              child(right, "pat"),
              pattern_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "alias"),
              child(right, "alias"),
              binder_equal_plain,
            )
          "Pattern::Array" =>
            option_match(
              child(left, "pats"),
              child(right, "pats"),
              json_value_equal_ignoring_loc,
            )
          "Pattern::Constant" =>
            option_match(
              child(left, "constant"),
              child(right, "constant"),
              json_value_equal_plain,
            )
          "Pattern::Constr" =>
            child(left, "is_open") == child(right, "is_open") &&
            option_match(
              child(left, "constr"),
              child(right, "constr"),
              constructor_equal_plain,
            ) &&
            option_match(
              child(left, "args"),
              child(right, "args"),
              json_value_equal_ignoring_loc,
            )
          "Pattern::Constraint" =>
            option_match(
              child(left, "ty"),
              child(right, "ty"),
              json_value_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "pat"),
              child(right, "pat"),
              pattern_equal_ignoring_loc,
            )
          "Pattern::Map" | "Pattern::Record" =>
            json_value_equal_ignoring_loc(left, right)
          "Pattern::Or" =>
            option_match(
              child(left, "pat1"),
              child(right, "pat1"),
              pattern_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "pat2"),
              child(right, "pat2"),
              pattern_equal_ignoring_loc,
            )
          "Pattern::Range" =>
            child(left, "kind") == child(right, "kind") &&
            option_match(
              child(left, "lhs"),
              child(right, "lhs"),
              pattern_equal_ignoring_loc,
            ) &&
            option_match(
              child(left, "rhs"),
              child(right, "rhs"),
              pattern_equal_ignoring_loc,
            )
          "Pattern::SpecialConstr" =>
            option_match(
              child(left, "binder"),
              child(right, "binder"),
              binder_equal_plain,
            ) &&
            option_match(
              child(left, "args"),
              child(right, "args"),
              json_value_equal_ignoring_loc,
            )
          "Pattern::Tuple" =>
            option_match(
              child(left, "pats"),
              child(right, "pats"),
              pattern_list_equal_ignoring_loc,
            )
          _ => false
        }
      }
    _ => false
  }
}

///|
fn expr_list_equal_ignoring_loc(left : Json, right : Json) -> Bool {
  match (left, right) {
    (
      { "children": Array(left_items), .. },
      { "children": Array(right_items), .. },
    ) => match_plain_array(left_items, right_items, expr_equal_ignoring_loc)
    _ => false
  }
}

///|
fn argument_list_equal_ignoring_loc(left : Json, right : Json) -> Bool {
  match (left, right) {
    (
      { "children": Array(left_items), .. },
      { "children": Array(right_items), .. },
    ) => match_plain_array(left_items, right_items, argument_equal_ignoring_loc)
    _ => false
  }
}

///|
fn argument_equal_ignoring_loc(left : Json, right : Json) -> Bool {
  json_kind(left) == Some("Argument") &&
  json_kind(right) == Some("Argument") &&
  option_match(
    child(left, "kind"),
    child(right, "kind"),
    argument_kind_equal_ignoring_loc,
  ) &&
  option_match(
    child(left, "value"),
    child(right, "value"),
    expr_equal_ignoring_loc,
  )
}

///|
fn argument_kind_equal_ignoring_loc(left : Json, right : Json) -> Bool {
  if json_kind(left) != json_kind(right) {
    return false
  }
  match json_kind(left) {
    Some("ArgumentKind::Positional") => true
    Some("ArgumentKind::Labelled")
    | Some("ArgumentKind::LabelledPun")
    | Some("ArgumentKind::LabelledOption")
    | Some("ArgumentKind::LabelledOptionPun") =>
      option_match(
        argument_kind_label(left),
        argument_kind_label(right),
        label_equal_plain,
      )
    _ => false
  }
}

///|
fn argument_kind_label(value : Json) -> Json? {
  match value {
    { "children": { "value": label, .. }, .. } => Some(label)
    { "children": { "label": label, .. }, .. } => Some(label)
    _ => None
  }
}

///|
fn pattern_list_equal_ignoring_loc(left : Json, right : Json) -> Bool {
  match (left, right) {
    (
      { "children": Array(left_items), .. },
      { "children": Array(right_items), .. },
    ) => match_plain_array(left_items, right_items, pattern_equal_ignoring_loc)
    _ => false
  }
}

///|
fn binder_expr_list_equal(left : Json, right : Json) -> Bool {
  match (left, right) {
    (
      { "children": Array(left_items), .. },
      { "children": Array(right_items), .. },
    ) => match_plain_array(left_items, right_items, binder_expr_equal)
    _ => false
  }
}

///|
fn binder_expr_equal(left : Json, right : Json) -> Bool {
  option_match(
    child(left, "binder"),
    child(right, "binder"),
    binder_equal_plain,
  ) &&
  option_match(
    child(left, "expr"),
    child(right, "expr"),
    expr_equal_ignoring_loc,
  )
}

///|
fn option_expr_equal(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Null, Null) => true
    _ => expr_equal_ignoring_loc(left, right)
  }
}

///|
fn node_kind_equal(left : Json, right : Json) -> Bool {
  json_kind(left) == json_kind(right)
}

///|
fn var_equal_plain(left : Json, right : Json) -> Bool {
  match (normalized_var(left), normalized_var(right)) {
    (Some(left), Some(right)) => left == right
    _ => false
  }
}

///|
fn binder_equal_plain(left : Json, right : Json) -> Bool {
  match (binder_name(left), binder_name(right)) {
    (Some(left), Some(right)) => left == right
    _ => false
  }
}

///|
fn label_equal_plain(left : Json, right : Json) -> Bool {
  match (label_name(left), label_name(right)) {
    (Some(left), Some(right)) => left == right
    _ => false
  }
}

///|
fn type_name_equal_plain(left : Json, right : Json) -> Bool {
  match (left, right) {
    (
      { "children": { "is_object": left_object, "name": left_name, .. }, .. },
      { "children": { "is_object": right_object, "name": right_name, .. }, .. },
    ) =>
      match (json_bool(left_object), json_bool(right_object)) {
        (Some(left_object), Some(right_object)) =>
          left_object == right_object &&
          long_ident_equal_plain(left_name, right_name)
        _ => false
      }
    _ => false
  }
}

///|
fn constructor_equal_plain(left : Json, right : Json) -> Bool {
  match (normalized_constructor(left), normalized_constructor(right)) {
    (Some(left), Some(right)) => left == right
    _ => false
  }
}

///|
fn long_ident_equal_plain(left : Json, right : Json) -> Bool {
  match (normalized_long_ident(left), normalized_long_ident(right)) {
    (Some(left), Some(right)) => left == right
    _ => false
  }
}

///|
fn normalized_expr(expr : Json) -> String? {
  match expr {
    { "kind": "Expr::Ident", "children": { "id": id, .. }, .. } =>
      normalized_var(id)
    _ => None
  }
}

///|
fn normalized_pattern(pattern : Json) -> String? {
  match pattern {
    { "kind": "Pattern::Var", "children": { "value": value, .. }, .. } =>
      binder_name(value)
    _ => None
  }
}

///|
fn normalized_var(value : Json) -> String? {
  match value {
    { "kind": "Var", "children": { "name": name, .. }, .. } =>
      normalized_long_ident(name)
    _ => None
  }
}

///|
fn normalized_long_ident(value : Json) -> String? {
  match value {
    {
      "kind": "LongIdent::Ident",
      "children": { "value": String(value), .. },
      ..
    } => Some(value)
    {
      "kind": "LongIdent::Dot",
      "children": { "pkg": String(pkg), "id": String(id), .. },
      ..
    } => Some("@\{pkg}.\{id}")
    _ => None
  }
}

///|
fn normalized_constructor(constr : Json) -> String? {
  match constr {
    { "children": { "name": name_json, "extra_info": extra, .. }, .. } =>
      match (constr_name(name_json), extra) {
        (Some(name), { "kind": "ConstructorExtraInfo::NoExtraInfo", .. }) =>
          Some(name)
        (
          Some(name),
          {
            "kind": "ConstructorExtraInfo::Package",
            "children": { "value": String(pkg), .. },
            ..
          },
        ) => Some("@\{pkg}.\{name}")
        (
          Some(name),
          {
            "kind": "ConstructorExtraInfo::TypeName",
            "children": { "value": type_name_json, .. },
            ..
          },
        ) =>
          normalized_type_name(type_name_json).map(type_name => {
            "\{type_name}::\{name}"
          })
        (
          Some(name),
          {
            "kind": "ConstructorExtraInfo::TypeNameWithConstrPackage",
            "children": { "type_name": type_name_json, "pkg": String(pkg), .. },
            ..
          },
        ) =>
          normalized_type_name(type_name_json).map(type_name => {
            "\{type_name}::@\{pkg}.\{name}"
          })
        _ => None
      }
    _ => None
  }
}

///|
fn normalized_type_name(type_name : Json) -> String? {
  match type_name {
    { "children": { "name": name_json, "is_object": True, .. }, .. } =>
      normalized_long_ident(name_json).map(name => "object \{name}")
    { "children": { "name": name_json, "is_object": False, .. }, .. } =>
      normalized_long_ident(name_json)
    _ => None
  }
}

///|
fn expr_constant(expr : Json) -> Json? {
  match expr {
    { "kind": "Expr::Constant", "children": { "constant": constant, .. }, .. } =>
      Some(constant)
    _ => None
  }
}

///|
fn pattern_constant(pattern : Json) -> Json? {
  match pattern {
    {
      "kind": "Pattern::Constant",
      "children": { "constant": constant, .. },
      ..
    } => Some(constant)
    _ => None
  }
}

///|
fn is_faked_unit(expr : Json) -> Bool {
  expr is { "kind": "Expr::Unit", "children": { "faked": True, .. }, .. }
}

///|
fn binder_name(binder : Json) -> String? {
  match binder {
    { "kind": "Binder", "children": { "name": String(name), .. }, .. } =>
      Some(name)
    _ => None
  }
}

///|
fn label_name(label : Json) -> String? {
  match label {
    { "kind": "Label", "children": { "name": String(name), .. }, .. } =>
      Some(name)
    _ => None
  }
}

///|
fn constr_name(name : Json) -> String? {
  match name {
    { "kind": "ConstrName", "children": { "name": String(name), .. }, .. } =>
      Some(name)
    _ => None
  }
}

///|
fn json_kind(value : Json) -> String? {
  match value {
    { "kind": String(kind), .. } => Some(kind)
    _ => None
  }
}

///|
fn child(value : Json, name : String) -> Json? {
  match value {
    { "children": Object(fields), .. } => fields.get(name)
    _ => None
  }
}

///|
fn json_bool(value : Json) -> Bool? {
  match value {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
fn match_json_array(
  pattern_items : Array[Json],
  candidate_items : Array[Json],
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  if pattern_items.length() != candidate_items.length() {
    return false
  }
  for index in 0..<pattern_items.length() {
    if !match_json(
        pattern_items[index],
        candidate_items[index],
        compiled,
        bindings,
      ) {
      return false
    }
  }
  true
}

///|
fn[A] match_plain_array(
  left : Array[A],
  right : Array[A],
  equal : (A, A) -> Bool,
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index in 0..<left.length() {
    if !equal(left[index], right[index]) {
      return false
    }
  }
  true
}

///|
fn json_value_equal(
  pattern : Json,
  candidate : Json,
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  match (pattern, candidate) {
    (Null, Null) => true
    (True, True) => true
    (False, False) => true
    (String(left), String(right)) => left == right
    (Number(left, repr=left_repr), Number(right, repr=right_repr)) =>
      left == right && left_repr == right_repr
    (Array(left), Array(right)) =>
      match_json_array(left, right, compiled, bindings)
    (Object(left), Object(right)) =>
      match_plain_object(left, right, compiled, bindings)
    _ => false
  }
}

///|
fn match_plain_object(
  pattern_fields : Map[String, Json],
  candidate_fields : Map[String, Json],
  compiled : CompiledJsonExprPattern,
  bindings : @hashmap.HashMap[String, JsonBoundValue],
) -> Bool {
  for key, pattern_value in pattern_fields {
    if key != "loc" {
      if candidate_fields.get(key) is Some(candidate_value) {
        if !match_json(pattern_value, candidate_value, compiled, bindings) {
          return false
        }
      } else {
        return false
      }
    }
  }
  for key, _ in candidate_fields {
    if key != "loc" && !pattern_fields.contains(key) {
      return false
    }
  }
  true
}

///|
fn json_value_equal_plain(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Null, Null) => true
    (True, True) => true
    (False, False) => true
    (String(left), String(right)) => left == right
    (Number(left, repr=left_repr), Number(right, repr=right_repr)) =>
      left == right && left_repr == right_repr
    (Array(left), Array(right)) =>
      match_plain_array(left, right, json_value_equal_plain)
    (Object(left), Object(right)) => plain_object_equal(left, right)
    _ => false
  }
}

///|
fn json_value_equal_ignoring_loc(left : Json, right : Json) -> Bool {
  match (left, right) {
    (Object(left_fields), Object(right_fields)) =>
      plain_object_equal_ignoring_loc(left_fields, right_fields)
    (Array(left), Array(right)) =>
      match_plain_array(left, right, json_value_equal_ignoring_loc)
    _ => json_value_equal_plain(left, right)
  }
}

///|
fn plain_object_equal(
  left : Map[String, Json],
  right : Map[String, Json],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for key, value in left {
    if right.get(key) is Some(right_value) {
      if !json_value_equal_plain(value, right_value) {
        return false
      }
    } else {
      return false
    }
  }
  true
}

///|
fn plain_object_equal_ignoring_loc(
  left : Map[String, Json],
  right : Map[String, Json],
) -> Bool {
  for key, value in left {
    if key != "loc" {
      if right.get(key) is Some(right_value) {
        if !json_value_equal_ignoring_loc(value, right_value) {
          return false
        }
      } else {
        return false
      }
    }
  }
  for key, _ in right {
    if key != "loc" && !left.contains(key) {
      return false
    }
  }
  true
}

///|
fn[A] option_match(left : A?, right : A?, equal : (A, A) -> Bool) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(left), Some(right)) => equal(left, right)
    _ => false
  }
}

///|
fn contains_name(names : Array[String], name : String) -> Bool {
  for item in names {
    if item == name {
      return true
    }
  }
  false
}

///|
fn is_special_expr_metavar(
  compiled : CompiledJsonExprPattern,
  name : String,
) -> Bool {
  compiled.target_metavar == Some(name) || compiled.source_metavar == Some(name)
}

///|
fn parse_pattern_metavar_name(raw : String) -> String? {
  if raw.has_prefix("$(") && raw.has_suffix(")") {
    let end = raw.length() - 1
    for index in 2..<end {
      if raw[index] == ':' && raw[index + 1:end].to_owned() == "pat" {
        let name = raw[2:index]
        if name.length() > 0 {
          return Some(name.to_owned())
        }
      }
    }
  }
  None
}

///|
fn is_ignore_placeholder(name : String) -> Bool {
  if name.length() < 2 {
    return false
  }
  for char in name {
    if char != '_' {
      return false
    }
  }
  true
}
