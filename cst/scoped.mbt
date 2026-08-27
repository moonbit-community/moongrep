///|
/// An expression together with names introduced between an outer context and
/// that expression.
priv struct ScopedExprNode {
  expr : @untyped_cst.CstNode
  shadowed_names : Array[String]
}

///|
/// One semantic expression-matching candidate. A direct candidate retains its
/// source CST node. A sequence candidate represents statements without the
/// braces of the block that contains them.
pub(all) enum ExprMatchCandidate {
  Direct(@untyped_cst.CstNode)
  Sequence(Array[@untyped_cst.CstNode])
}

///|
/// An expression-matching candidate together with names introduced between an
/// outer context and that candidate.
pub(all) struct ScopedExprMatchCandidate {
  candidate : ExprMatchCandidate
  shadowed_names : Array[String]
}

///|
pub(all) enum NodeVisitAction {
  NodeVisitContinue
  NodeVisitPrune
  NodeVisitReturn
}

///|
pub fn visit_scoped_expr_match_candidate(
  candidate : ExprMatchCandidate,
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> Unit {
  ignore(visit_match_candidate_with_shadow(candidate, shadowed, visitor))
}

///|
pub fn visit_scoped_expr_match_candidate_roots(
  root : @untyped_cst.CstNode,
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> Unit {
  ignore(visit_match_candidate_roots_with_shadow(root, [], visitor))
}

///|
pub fn visit_scoped_expr_match_candidate_children(
  candidate : ExprMatchCandidate,
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> Unit,
) -> Unit {
  ignore(
    visit_match_candidate_children(candidate, shadowed, fn(item) {
      visitor(item)
      NodeVisitPrune
    }),
  )
}

///|
fn visit_match_candidate_roots_with_shadow(
  node : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> NodeVisitAction {
  if node.kind.is_expr() || node.kind is @untyped_cst.Expression {
    return visit_match_candidate_from_node(node, shadowed, visitor)
  }
  match node.kind {
    @untyped_cst.Impl_Function => {
      let body_shadowed = shadowed_with_parameters(
        shadowed,
        raw_child(node, "params"),
      )
      visit_function_body_match_candidate(node, body_shadowed, visitor)
    }
    @untyped_cst.Impl_ImplMethod =>
      if raw_child(node, "method") is Some(method_node) {
        let body_shadowed = shadowed_with_parameters(
          shadowed,
          raw_child(method_node, "params"),
        )
        visit_function_body_match_candidate(method_node, body_shadowed, visitor)
      } else {
        NodeVisitContinue
      }
    @untyped_cst.Impl_Test =>
      visit_function_body_match_candidate(node, shadowed, visitor)
    @untyped_cst.Impl_Let | @untyped_cst.Impl_Const =>
      visit_raw_named_match_candidate(node, "expr", shadowed, visitor)
    _ => {
      for entry in node.children {
        match
          visit_match_candidate_roots_with_shadow(entry.1, shadowed, visitor) {
          NodeVisitReturn => return NodeVisitReturn
          _ => ()
        }
      }
      NodeVisitContinue
    }
  }
}

///|
fn visit_raw_named_match_candidate(
  node : @untyped_cst.CstNode,
  label : String,
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> NodeVisitAction {
  if raw_child(node, label) is Some(child) {
    visit_match_candidate_roots_with_shadow(child, shadowed, visitor)
  } else {
    NodeVisitContinue
  }
}

///|
fn visit_function_body_match_candidate(
  node : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> NodeVisitAction {
  guard raw_child(node, "body") is Some(body) else { return NodeVisitContinue }
  if body.kind is @untyped_cst.Expr_Block {
    visit_match_candidate_with_shadow(
      Sequence(sequence_items(body)),
      shadowed,
      visitor,
    )
  } else {
    visit_match_candidate_from_node(body, shadowed, visitor)
  }
}

///|
fn visit_match_candidate_from_node(
  node : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> NodeVisitAction {
  if node.kind is @untyped_cst.Expression {
    visit_match_candidate_with_shadow(
      Sequence(expression_nodes(node)),
      shadowed,
      visitor,
    )
  } else if node.kind.is_expr() {
    visit_match_candidate_with_shadow(Direct(node), shadowed, visitor)
  } else {
    visit_match_candidate_roots_with_shadow(node, shadowed, visitor)
  }
}

///|
fn visit_match_candidate_with_shadow(
  candidate : ExprMatchCandidate,
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> NodeVisitAction {
  match visitor({ candidate, shadowed_names: copy_names(shadowed) }) {
    NodeVisitPrune => NodeVisitPrune
    NodeVisitReturn => NodeVisitReturn
    NodeVisitContinue =>
      visit_match_candidate_children(candidate, shadowed, visitor)
  }
}

///|
fn visit_match_candidate_children(
  candidate : ExprMatchCandidate,
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> NodeVisitAction {
  match candidate {
    Sequence(expressions) =>
      visit_match_sequence_children(expressions, shadowed, visitor)
    Direct(expr) =>
      visit_direct_match_candidate_children(expr, shadowed, visitor)
  }
}

///|
fn visit_direct_match_candidate_children(
  expr : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> NodeVisitAction {
  match expr.kind {
    @untyped_cst.Expr_Block | @untyped_cst.Expr_Sequence =>
      visit_match_candidate_with_shadow(
        Sequence(sequence_items(expr)),
        shadowed,
        visitor,
      )
    @untyped_cst.Expr_Function => {
      let body_shadowed = shadowed_with_parameters(
        shadowed,
        raw_child(expr, "params"),
      )
      visit_function_body_match_candidate(expr, body_shadowed, visitor)
    }
    @untyped_cst.Expr_LetFn => {
      let named_shadowed = shadowed_with_name_node(shadowed, expr)
      let body_shadowed = shadowed_with_parameters(
        named_shadowed,
        raw_child(expr, "params"),
      )
      visit_function_body_match_candidate(expr, body_shadowed, visitor)
    }
    @untyped_cst.Expr_LetAnd => {
      let names = copy_names(shadowed)
      for binding in raw_children(expr, "binding") {
        add_normalized_name(names, binding)
      }
      for binding in raw_children(expr, "binding") {
        let body_shadowed = shadowed_with_parameters(
          names,
          raw_child(binding, "params"),
        )
        if visit_function_body_match_candidate(binding, body_shadowed, visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
        if visit_raw_named_match_candidate(binding, "expr", names, visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
      }
      NodeVisitContinue
    }
    _ =>
      visit_expr_children(expr, shadowed, fn(item) {
        visit_match_candidate_from_node(item.expr, item.shadowed_names, visitor)
      })
  }
}

///|
fn visit_match_sequence_children(
  expressions : Array[@untyped_cst.CstNode],
  shadowed : Array[String],
  visitor : (ScopedExprMatchCandidate) -> NodeVisitAction,
) -> NodeVisitAction {
  let current = copy_names(shadowed)
  for index in 0..<expressions.length() {
    let expr = expressions[index]
    let has_continuation = continuation_owner(expr.kind) &&
      index + 1 < expressions.length()
    if index == 0 && has_continuation {
      if visit_direct_match_candidate_children(expr, current, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
    } else if has_continuation {
      let suffix = expressions[index:].to_owned()
      if visit_match_candidate_with_shadow(Sequence(suffix), current, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      return NodeVisitContinue
    } else if visit_match_candidate_with_shadow(Direct(expr), current, visitor)
      is NodeVisitReturn {
      return NodeVisitReturn
    }
    add_statement_bindings(current, expr)
  }
  NodeVisitContinue
}

///|
fn continuation_owner(kind : @untyped_cst.NodeKind) -> Bool {
  match kind {
    @untyped_cst.Expr_Let
    | @untyped_cst.Expr_LetMut
    | @untyped_cst.Expr_LetFn
    | @untyped_cst.Expr_LetAnd
    | @untyped_cst.Expr_Guard
    | @untyped_cst.Expr_Defer => true
    _ => false
  }
}

///|
fn visit_roots_with_shadow(
  node : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  if node.kind.is_expr() {
    return visit_expr_with_shadow(node, shadowed, visitor)
  }
  match node.kind {
    @untyped_cst.Expression =>
      visit_expression_sequence(expression_nodes(node), shadowed, visitor)
    @untyped_cst.Impl_Function => {
      let body_shadowed = shadowed_with_parameters(
        shadowed,
        raw_child(node, "params"),
      )
      visit_raw_named_roots(node, "body", body_shadowed, visitor)
    }
    @untyped_cst.Impl_ImplMethod =>
      if raw_child(node, "method") is Some(method_node) {
        let body_shadowed = shadowed_with_parameters(
          shadowed,
          raw_child(method_node, "params"),
        )
        visit_raw_named_roots(method_node, "body", body_shadowed, visitor)
      } else {
        NodeVisitContinue
      }
    @untyped_cst.Impl_Test =>
      visit_raw_named_roots(node, "body", shadowed, visitor)
    @untyped_cst.Impl_Let | @untyped_cst.Impl_Const =>
      visit_raw_named_roots(node, "expr", shadowed, visitor)
    _ => {
      for entry in node.children {
        match visit_roots_with_shadow(entry.1, shadowed, visitor) {
          NodeVisitReturn => return NodeVisitReturn
          _ => ()
        }
      }
      NodeVisitContinue
    }
  }
}

///|
fn visit_raw_named_roots(
  node : @untyped_cst.CstNode,
  label : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  if raw_child(node, label) is Some(child) {
    visit_roots_with_shadow(child, shadowed, visitor)
  } else {
    NodeVisitContinue
  }
}

///|
fn visit_expr_with_shadow(
  expr : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  match visitor({ expr, shadowed_names: copy_names(shadowed) }) {
    NodeVisitPrune => NodeVisitPrune
    NodeVisitReturn => NodeVisitReturn
    NodeVisitContinue => visit_expr_children(expr, shadowed, visitor)
  }
}

///|
fn visit_expr_children(
  expr : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  match expr.kind {
    @untyped_cst.Expr_Block =>
      visit_expression_sequence(sequence_items(expr), shadowed, visitor)
    @untyped_cst.Expr_Sequence =>
      visit_expression_sequence(sequence_items(expr), shadowed, visitor)
    @untyped_cst.Expr_Infix if operator_name(expr) == Some("&&") => {
      if visit_named_expr(expr, "lhs", shadowed, visitor) is NodeVisitReturn {
        return NodeVisitReturn
      }
      let rhs_shadowed = shadowed_with_condition(
        shadowed,
        raw_child(expr, "lhs"),
      )
      visit_named_expr(expr, "rhs", rhs_shadowed, visitor)
    }
    @untyped_cst.Expr_If => {
      if visit_named_expr(expr, "cond", shadowed, visitor) is NodeVisitReturn {
        return NodeVisitReturn
      }
      let then_shadowed = shadowed_with_condition(
        shadowed,
        raw_child(expr, "cond"),
      )
      if visit_named_expr(expr, "body", then_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_named_expr(expr, "else", shadowed, visitor)
    }
    @untyped_cst.Expr_While => {
      if visit_named_expr(expr, "cond", shadowed, visitor) is NodeVisitReturn {
        return NodeVisitReturn
      }
      let body_shadowed = shadowed_with_condition(
        shadowed,
        raw_child(expr, "cond"),
      )
      if visit_named_expr(expr, "body", body_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_named_expr(expr, "else", shadowed, visitor)
    }
    @untyped_cst.Expr_For => {
      if visit_binding_list_exprs(expr, "init", shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      let loop_shadowed = shadowed_with_loop_bindings(
        shadowed,
        raw_child(expr, "init"),
      )
      if visit_named_expr(expr, "cond", loop_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      let body_shadowed = shadowed_with_condition(
        loop_shadowed,
        raw_child(expr, "cond"),
      )
      if visit_binding_list_exprs(expr, "continue", body_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_named_expr(expr, "body", body_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_named_expr(expr, "else", loop_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_named_expr(expr, "where", loop_shadowed, visitor)
    }
    @untyped_cst.Expr_ForEach => {
      if visit_named_expr(expr, "expr", shadowed, visitor) is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_binding_list_exprs(expr, "init", shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      let loop_shadowed = shadowed_with_pattern(
        shadowed,
        raw_child(expr, "pattern"),
      )
      add_loop_binding_names(loop_shadowed, raw_child(expr, "init"))
      if visit_binding_list_exprs(expr, "continue", loop_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_named_expr(expr, "body", loop_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_named_expr(expr, "else", loop_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_named_expr(expr, "where", loop_shadowed, visitor)
    }
    @untyped_cst.Expr_ListComprehension => {
      let body_shadowed = if raw_child(expr, "pattern") is Some(pattern) {
        if visit_named_expr(expr, "expr", shadowed, visitor) is NodeVisitReturn {
          return NodeVisitReturn
        }
        if visit_binding_list_exprs(expr, "init", shadowed, visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
        let loop_shadowed = shadowed_with_pattern(shadowed, Some(pattern))
        add_loop_binding_names(loop_shadowed, raw_child(expr, "init"))
        if visit_binding_list_exprs(expr, "continue", loop_shadowed, visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
        loop_shadowed
      } else {
        if visit_binding_list_exprs(expr, "init", shadowed, visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
        let loop_shadowed = shadowed_with_loop_bindings(
          shadowed,
          raw_child(expr, "init"),
        )
        if visit_named_expr(expr, "cond", loop_shadowed, visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
        let cond_shadowed = shadowed_with_condition(
          loop_shadowed,
          raw_child(expr, "cond"),
        )
        if visit_binding_list_exprs(expr, "continue", cond_shadowed, visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
        cond_shadowed
      }
      if visit_named_expr(expr, "guard", body_shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      let guarded_shadowed = shadowed_with_condition(
        body_shadowed,
        raw_child(expr, "guard"),
      )
      visit_named_expr(expr, "body", guarded_shadowed, visitor)
    }
    @untyped_cst.Expr_Match => {
      if visit_named_expr(expr, "expr", shadowed, visitor) is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_case_list_exprs(expr, "case", shadowed, visitor)
    }
    @untyped_cst.Expr_LexMatch | @untyped_cst.Expr_LexScan => {
      if visit_named_expr(expr, "expr", shadowed, visitor) is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_case_list_exprs(expr, "case", shadowed, visitor)
    }
    @untyped_cst.Expr_Try => {
      if visit_named_expr(expr, "body", shadowed, visitor) is NodeVisitReturn {
        return NodeVisitReturn
      }
      if visit_case_list_exprs(expr, "case", shadowed, visitor)
        is NodeVisitReturn {
        return NodeVisitReturn
      }
      visit_case_list_exprs(expr, "else", shadowed, visitor)
    }
    @untyped_cst.Expr_Quantifier => {
      let body_shadowed = copy_names(shadowed)
      if raw_child(expr, "name").bind(normalized_name) is Some(name) {
        add_unique_name(body_shadowed, name)
      }
      visit_named_expr(expr, "body", body_shadowed, visitor)
    }
    @untyped_cst.Expr_Function => {
      let body_shadowed = shadowed_with_parameters(
        shadowed,
        raw_child(expr, "params"),
      )
      visit_named_expr(expr, "body", body_shadowed, visitor)
    }
    @untyped_cst.Expr_LetFn => {
      let named_shadowed = shadowed_with_name_node(shadowed, expr)
      let body_shadowed = shadowed_with_parameters(
        named_shadowed,
        raw_child(expr, "params"),
      )
      visit_named_expr(expr, "body", body_shadowed, visitor)
    }
    @untyped_cst.Expr_LetAnd => {
      let names = copy_names(shadowed)
      for binding in raw_children(expr, "binding") {
        add_normalized_name(names, binding)
      }
      for binding in raw_children(expr, "binding") {
        let body_shadowed = shadowed_with_parameters(
          names,
          raw_child(binding, "params"),
        )
        if visit_named_expr(binding, "body", body_shadowed, visitor)
          is NodeVisitReturn {
          return NodeVisitReturn
        }
        if visit_named_expr(binding, "expr", names, visitor) is NodeVisitReturn {
          return NodeVisitReturn
        }
      }
      NodeVisitContinue
    }
    _ => visit_all_descendant_exprs(expr, shadowed, visitor)
  }
}

///|
fn visit_expression_sequence(
  expressions : Array[@untyped_cst.CstNode],
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  let current = copy_names(shadowed)
  for expr in expressions {
    match visit_expr_with_shadow(expr, current, visitor) {
      NodeVisitReturn => return NodeVisitReturn
      _ => ()
    }
    add_statement_bindings(current, expr)
  }
  NodeVisitContinue
}

///|
fn visit_named_expr(
  node : @untyped_cst.CstNode,
  label : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  if child(node, label) is Some(child) {
    visit_descendant_exprs(child, shadowed, visitor)
  } else {
    NodeVisitContinue
  }
}

///|
fn visit_binding_list_exprs(
  node : @untyped_cst.CstNode,
  label : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  guard raw_child(node, label) is Some(list) else { return NodeVisitContinue }
  for binding in raw_children(list, "item") {
    if visit_named_expr(binding, "expr", shadowed, visitor) is NodeVisitReturn {
      return NodeVisitReturn
    }
  }
  NodeVisitContinue
}

///|
fn visit_case_list_exprs(
  node : @untyped_cst.CstNode,
  label : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  for list in raw_children(node, label) {
    if list.kind
      is (@untyped_cst.Case_MatchCase
      | @untyped_cst.Case_LexCase
      | @untyped_cst.Case_LexScanCase) {
      if visit_case_exprs(list, shadowed, visitor) is NodeVisitReturn {
        return NodeVisitReturn
      }
    } else {
      for case in raw_children(list, "case") {
        if visit_case_exprs(case, shadowed, visitor) is NodeVisitReturn {
          return NodeVisitReturn
        }
      }
    }
  }
  NodeVisitContinue
}

///|
fn visit_case_exprs(
  case : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  let case_shadowed = shadowed_with_pattern(
    shadowed,
    raw_child(case, "pattern"),
  )
  if visit_named_expr(case, "cond", case_shadowed, visitor) is NodeVisitReturn {
    return NodeVisitReturn
  }
  let body_shadowed = shadowed_with_condition(
    case_shadowed,
    raw_child(case, "cond"),
  )
  visit_named_expr(case, "body", body_shadowed, visitor)
}

///|
fn visit_descendant_exprs(
  node : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  if node.kind.is_expr() {
    visit_expr_with_shadow(node, shadowed, visitor)
  } else {
    visit_all_descendant_exprs(node, shadowed, visitor)
  }
}

///|
fn visit_all_descendant_exprs(
  node : @untyped_cst.CstNode,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  for entry in node.children {
    if is_syntax_kind(entry.1.kind) {
      continue
    }
    match visit_descendant_exprs(entry.1, shadowed, visitor) {
      NodeVisitReturn => return NodeVisitReturn
      _ => ()
    }
  }
  NodeVisitContinue
}

///|
fn add_statement_bindings(
  shadowed : Array[String],
  statement : @untyped_cst.CstNode,
) -> Unit {
  match statement.kind {
    @untyped_cst.Expr_Let | @untyped_cst.Expr_LetMut =>
      if raw_child(statement, "pattern") is Some(pattern) {
        add_pattern_names(shadowed, pattern)
      }
    @untyped_cst.Expr_LetFn => add_normalized_name(shadowed, statement)
    @untyped_cst.Expr_LetAnd =>
      for binding in raw_children(statement, "binding") {
        add_normalized_name(shadowed, binding)
      }
    @untyped_cst.Expr_Guard =>
      add_condition_names(shadowed, raw_child(statement, "cond"))
    @untyped_cst.Expr_ProofLet => add_normalized_name(shadowed, statement)
    _ => ()
  }
}

///|
fn shadowed_with_condition(
  shadowed : Array[String],
  condition : @untyped_cst.CstNode?,
) -> Array[String] {
  let result = copy_names(shadowed)
  add_condition_names(result, condition)
  result
}

///|
fn add_condition_names(
  names : Array[String],
  condition : @untyped_cst.CstNode?,
) -> Unit {
  guard condition is Some(node) else { return }
  match node.kind {
    @untyped_cst.Expr_Group =>
      if raw_child(node, "body") is Some(body) {
        for item in raw_children(body, "item") {
          add_condition_names(names, Some(item))
        }
      }
    @untyped_cst.Expr_Is | @untyped_cst.Expr_RegexMatch =>
      if raw_child(node, "pattern") is Some(pattern) {
        add_pattern_names(names, pattern)
      }
    @untyped_cst.Expr_Infix if operator_name(node) == Some("&&") => {
      add_condition_names(names, raw_child(node, "lhs"))
      add_condition_names(names, raw_child(node, "rhs"))
    }
    _ => ()
  }
}

///|
fn shadowed_with_pattern(
  shadowed : Array[String],
  pattern : @untyped_cst.CstNode?,
) -> Array[String] {
  let result = copy_names(shadowed)
  if pattern is Some(node) {
    add_pattern_names(result, node)
  }
  result
}

///|
fn shadowed_with_loop_bindings(
  shadowed : Array[String],
  bindings : @untyped_cst.CstNode?,
) -> Array[String] {
  let result = copy_names(shadowed)
  add_loop_binding_names(result, bindings)
  result
}

///|
fn add_loop_binding_names(
  names : Array[String],
  bindings : @untyped_cst.CstNode?,
) -> Unit {
  guard bindings is Some(list) else { return }
  for binding in raw_children(list, "item") {
    if raw_child(binding, "pattern") is Some(pattern) {
      add_pattern_names(names, pattern)
    } else {
      add_normalized_name(names, binding)
    }
  }
}

///|
fn add_pattern_names(
  names : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match pattern.kind {
    @untyped_cst.Name_Binder => {
      if normalized_name(pattern) is Some(name) {
        add_unique_name(names, name)
      }
      return
    }
    @untyped_cst.Pattern_Var => {
      if normalized_pattern_identifier_name(pattern) is Some(name) {
        add_unique_name(names, name)
      }
      return
    }
    @untyped_cst.Pattern_Alias
    | @untyped_cst.LexPattern_Alias
    | @untyped_cst.RegexPattern_Alias =>
      if raw_child(pattern, "name").bind(normalized_name) is Some(name) {
        add_unique_name(names, name)
      }
    @untyped_cst.Field_Pattern if raw_child(pattern, "pattern") is None =>
      if raw_child(pattern, "name").bind(normalized_name) is Some(name) {
        add_unique_name(names, name)
      }
    @untyped_cst.Pattern_Rest =>
      match raw_child(pattern, "name").bind(normalized_name) {
        Some(name) if name != "_" => add_unique_name(names, name)
        _ => ()
      }
    _ => ()
  }
  for entry in pattern.children {
    if !is_syntax_kind(entry.1.kind) {
      add_pattern_names(names, entry.1)
    }
  }
}

///|
fn shadowed_with_parameters(
  shadowed : Array[String],
  parameters : @untyped_cst.CstNode?,
) -> Array[String] {
  let result = copy_names(shadowed)
  guard parameters is Some(list) else { return result }
  for parameter in raw_children(list, "item") {
    if raw_child(parameter, "pattern") is Some(pattern) {
      add_pattern_names(result, pattern)
    } else {
      add_normalized_name(result, parameter)
    }
  }
  result
}

///|
fn shadowed_with_name_node(
  shadowed : Array[String],
  node : @untyped_cst.CstNode,
) -> Array[String] {
  let result = copy_names(shadowed)
  add_normalized_name(result, node)
  result
}

///|
fn add_normalized_name(
  names : Array[String],
  node : @untyped_cst.CstNode,
) -> Unit {
  if name_node(node).bind(normalized_name) is Some(name) {
    add_unique_name(names, name)
  }
}

///|
fn copy_names(names : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for name in names {
    result.push(name)
  }
  result
}

///|
fn add_unique_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}
