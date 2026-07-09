///|
pub(all) struct ScopedExprNode {
  expr : Node
  shadowed_names : Array[String]
}

///|
pub(all) enum NodeVisitAction {
  NodeVisitContinue
  NodeVisitPrune
  NodeVisitReturn
}

///|
pub fn collect_node_scoped_exprs(
  expr : Node,
  exprs : Array[ScopedExprNode],
) -> Unit {
  collect_node_scoped_exprs_with_shadow(expr, [], exprs)
}

///|
pub fn collect_node_scoped_expr_roots(
  root : Node,
  exprs : Array[ScopedExprNode],
) -> Unit {
  visit_node_scoped_expr_roots(root, fn(scoped_expr) {
    exprs.push(scoped_expr)
    NodeVisitContinue
  })
}

///|
fn collect_node_scoped_exprs_with_shadow(
  expr : Node,
  shadowed : Array[String],
  exprs : Array[ScopedExprNode],
) -> Unit {
  exprs.push({ expr, shadowed_names: copy_names(shadowed) })
  visit_node_scoped_expr_children(expr, shadowed, fn(child) {
    collect_node_scoped_exprs_with_shadow(
      child.expr,
      child.shadowed_names,
      exprs,
    )
  })
}

///|
pub fn visit_node_scoped_exprs(
  expr : Node,
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> Unit {
  let _ = visit_node_scoped_exprs_with_shadow(expr, [], visitor)
}

///|
pub fn visit_node_scoped_expr_roots(
  root : Node,
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> Unit {
  let _ = visit_node_scoped_expr_roots_with_shadow(root, [], visitor)
}

///|
fn visit_node_scoped_expr_roots_with_shadow(
  root : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  match root.kind {
    ImplList => visit_node_root_children(root, shadowed, visitor)
    Impl_TopExpr | Impl_TopLetDef | Impl_TopTest =>
      visit_node_root_named_expr(root, "expr", shadowed, visitor)
    Impl_TopView => visit_node_root_named_expr(root, "body", shadowed, visitor)
    Impl_TopFuncDef =>
      visit_node_root_named_expr(root, "decl_body", shadowed, visitor)
    Impl_TopImpl => visit_node_root_named_expr(root, "body", shadowed, visitor)
    Impl_TopTypeDef | Impl_TopTrait | Impl_TopImplRelation | Impl_TopUsing =>
      NodeVisitContinue
    DeclBody_DeclBody =>
      visit_node_root_named_expr(root, "expr", shadowed, visitor)
    Func_Lambda => visit_node_func_root_exprs(root, shadowed, visitor)
    _ =>
      if is_expr_node(root) {
        visit_node_scoped_exprs_with_shadow(root, shadowed, visitor)
      } else {
        visit_node_root_children(root, shadowed, visitor)
      }
  }
}

///|
fn visit_node_root_named_expr(
  node : Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  match node_child(node, name) {
    Some(child) =>
      visit_node_scoped_expr_roots_with_shadow(child, shadowed, visitor)
    None => NodeVisitContinue
  }
}

///|
fn visit_node_root_children(
  node : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  for entry in node.children {
    let (_, child) = entry
    match visit_node_scoped_expr_roots_with_shadow(child, shadowed, visitor) {
      NodeVisitReturn => return NodeVisitReturn
      _ => ()
    }
  }
  NodeVisitContinue
}

///|
fn visit_node_func_root_exprs(
  func : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  let body_shadowed = if node_child(func, "parameters") is Some(parameters) {
    shadowed_with_node_parameters(shadowed, parameters)
  } else {
    copy_names(shadowed)
  }
  visit_node_root_named_expr(func, "body", body_shadowed, visitor)
}

///|
fn visit_node_scoped_exprs_with_shadow(
  expr : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  let scoped_expr = { expr, shadowed_names: copy_names(shadowed) }
  match visitor(scoped_expr) {
    NodeVisitPrune => NodeVisitPrune
    NodeVisitReturn => NodeVisitReturn
    NodeVisitContinue =>
      visit_node_scoped_expr_children_with_action(expr, shadowed, fn(child) {
        visit_node_scoped_exprs_with_shadow(
          child.expr,
          child.shadowed_names,
          visitor,
        )
      })
  }
}

///|
pub fn visit_node_scoped_expr_children(
  expr : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> Unit,
) -> Unit {
  let _ = visit_node_scoped_expr_children_with_action(expr, shadowed, fn(
    scoped,
  ) {
    visitor(scoped)
    NodeVisitContinue
  })
}

///|
fn visit_node_scoped_expr_children_with_action(
  expr : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  match expr.kind {
    Expr_Let => {
      match visit_node_named_expr(expr, "expr", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let body_shadowed = if node_child(expr, "pattern") is Some(pattern) {
        shadowed_with_node_pattern(shadowed, pattern)
      } else {
        copy_names(shadowed)
      }
      match visit_node_named_expr(expr, "body", body_shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_LetMut => {
      match visit_node_named_expr(expr, "expr", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let body_shadowed = if node_child(expr, "binder") is Some(binder) {
        shadowed_with_node_binder(shadowed, binder)
      } else {
        copy_names(shadowed)
      }
      match visit_node_named_expr(expr, "body", body_shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_Infix =>
      if node_infix_op(expr, "&&") {
        match visit_node_named_expr(expr, "lhs", shadowed, visitor) {
          NodeVisitReturn => return NodeVisitReturn
          _ => ()
        }
        let rhs_shadowed = shadowed_with_node_condition_child(
          shadowed, expr, "lhs",
        )
        match visit_node_named_expr(expr, "rhs", rhs_shadowed, visitor) {
          NodeVisitReturn => NodeVisitReturn
          _ => NodeVisitContinue
        }
      } else {
        visit_node_all_child_exprs(expr, shadowed, visitor)
      }
    Expr_If => {
      match visit_node_named_expr(expr, "cond", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let true_shadowed = shadowed_with_node_condition_child(
        shadowed, expr, "cond",
      )
      match visit_node_named_expr(expr, "ifso", true_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_expr(expr, "ifnot", shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_Guard => {
      match visit_node_named_expr(expr, "cond", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let true_shadowed = shadowed_with_node_condition_child(
        shadowed, expr, "cond",
      )
      match visit_node_named_expr(expr, "otherwise", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_expr(expr, "body", true_shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_While => {
      match visit_node_named_expr(expr, "loop_cond", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let true_shadowed = shadowed_with_node_condition_child(
        shadowed, expr, "loop_cond",
      )
      match visit_node_named_expr(expr, "loop_body", true_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_expr(expr, "while_else", shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_For => {
      match visit_node_binding_list_exprs(expr, "binders", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let loop_shadowed = if node_child(expr, "binders") is Some(binders) {
        shadowed_with_node_binding_list_binders(shadowed, binders)
      } else {
        copy_names(shadowed)
      }
      match visit_node_named_expr(expr, "condition", loop_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let true_shadowed = shadowed_with_node_condition_child(
        loop_shadowed, expr, "condition",
      )
      match
        visit_node_binding_list_exprs(
          expr, "continue_block", true_shadowed, visitor,
        ) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_expr(expr, "body", true_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_expr(expr, "for_else", loop_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match
        visit_node_named_container_exprs(
          expr, "where_clause", loop_shadowed, visitor,
        ) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_ForEach => {
      match visit_node_named_expr(expr, "expr", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_binding_list_exprs(expr, "init", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let loop_shadowed = if node_child(expr, "binders") is Some(binders) {
        shadowed_with_node_optional_binders(shadowed, binders)
      } else {
        copy_names(shadowed)
      }
      if node_child(expr, "init") is Some(init) {
        add_node_binding_list_names(loop_shadowed, init)
      }
      match
        visit_node_binding_list_exprs(
          expr, "continue_block", loop_shadowed, visitor,
        ) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_expr(expr, "body", loop_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_expr(expr, "else_block", loop_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match
        visit_node_named_container_exprs(
          expr, "where_clause", loop_shadowed, visitor,
        ) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_Match => {
      match visit_node_named_expr(expr, "expr", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_case_list_exprs(expr, "cases", shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_Lexmatch => {
      match visit_node_named_expr(expr, "expr", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_lex_case_list_exprs(expr, "cases", shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_Lexscan => {
      match visit_node_named_expr(expr, "expr", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match
        visit_node_lex_scan_case_list_exprs(expr, "cases", shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_ListComprehension => {
      let (kind_action, body_shadowed) = if node_child(expr, "kind")
        is Some(kind) {
        visit_node_list_comprehension_kind_exprs(kind, shadowed, visitor)
      } else {
        (NodeVisitContinue, copy_names(shadowed))
      }
      match kind_action {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_expr(expr, "guard", body_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let guard_shadowed = shadowed_with_node_condition_child(
        body_shadowed, expr, "guard",
      )
      match visit_node_named_expr(expr, "body", guard_shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_Function =>
      if node_child(expr, "func") is Some(func) {
        visit_node_func_exprs(func, shadowed, visitor)
      } else {
        NodeVisitContinue
      }
    Expr_LetFn => {
      let name_shadowed = if node_child(expr, "name") is Some(binder) {
        shadowed_with_node_binder(shadowed, binder)
      } else {
        copy_names(shadowed)
      }
      if node_child(expr, "func") is Some(func) {
        match visit_node_func_exprs(func, name_shadowed, visitor) {
          NodeVisitReturn => return NodeVisitReturn
          _ => ()
        }
      }
      match visit_node_named_expr(expr, "body", name_shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_LetAnd => {
      let binding_shadowed = if node_child(expr, "bindings") is Some(bindings) {
        shadowed_with_node_let_and_binders(shadowed, bindings)
      } else {
        copy_names(shadowed)
      }
      if node_child(expr, "bindings") is Some(bindings) {
        for entry in bindings.children {
          let (_, binding) = entry
          if node_child(binding, "func") is Some(func) {
            match visit_node_func_exprs(func, binding_shadowed, visitor) {
              NodeVisitReturn => return NodeVisitReturn
              _ => ()
            }
          }
        }
      }
      match visit_node_named_expr(expr, "body", binding_shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_Quantifier => {
      let body_shadowed = if node_child(expr, "binder") is Some(binder) {
        shadowed_with_node_binder(shadowed, binder)
      } else {
        copy_names(shadowed)
      }
      match visit_node_named_expr(expr, "body", body_shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_Try => {
      match visit_node_named_expr(expr, "body", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_case_list_exprs(expr, "catch", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_case_list_exprs(expr, "try_else", shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_IsLexmatch => {
      match visit_node_named_expr(expr, "expr", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_container_exprs(expr, "pat", shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    Expr_RegexMatch => {
      match visit_node_named_expr(expr, "expr", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      match visit_node_named_container_exprs(expr, "pat", shadowed, visitor) {
        NodeVisitReturn => NodeVisitReturn
        _ => NodeVisitContinue
      }
    }
    _ => visit_node_all_child_exprs(expr, shadowed, visitor)
  }
}

///|
fn visit_node_named_expr(
  node : Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  match node_child(node, name) {
    Some(child) => visit_node_descendant_exprs(child, shadowed, visitor)
    None => NodeVisitContinue
  }
}

///|
fn visit_node_named_container_exprs(
  node : Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  match node_child(node, name) {
    Some(child) => visit_node_all_child_exprs(child, shadowed, visitor)
    None => NodeVisitContinue
  }
}

///|
fn visit_node_descendant_exprs(
  node : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  if is_expr_node(node) {
    visitor({ expr: node, shadowed_names: copy_names(shadowed) })
  } else {
    visit_node_all_child_exprs(node, shadowed, visitor)
  }
}

///|
fn visit_node_all_child_exprs(
  node : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  for entry in node.children {
    let (_, child) = entry
    match visit_node_descendant_exprs(child, shadowed, visitor) {
      NodeVisitReturn => return NodeVisitReturn
      _ => ()
    }
  }
  NodeVisitContinue
}

///|
fn visit_node_binding_list_exprs(
  node : Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  if node_child(node, name) is Some(list) {
    for entry in list.children {
      let (_, binding) = entry
      match visit_node_named_expr(binding, "expr", shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
    }
  }
  NodeVisitContinue
}

///|
fn visit_node_case_list_exprs(
  node : Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  match node_child(node, name) {
    Some(list) => visit_node_case_container_exprs(list, shadowed, visitor)
    None => NodeVisitContinue
  }
}

///|
fn visit_node_case_container_exprs(
  list : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  for entry in list.children {
    let (_, case) = entry
    let case_shadowed = if node_child(case, "pattern") is Some(pattern) {
      shadowed_with_node_pattern(shadowed, pattern)
    } else {
      copy_names(shadowed)
    }
    match visit_node_named_expr(case, "guard", case_shadowed, visitor) {
      NodeVisitReturn => return NodeVisitReturn
      _ => ()
    }
    let body_shadowed = shadowed_with_node_condition_child(
      case_shadowed, case, "guard",
    )
    match visit_node_named_expr(case, "body", body_shadowed, visitor) {
      NodeVisitReturn => return NodeVisitReturn
      _ => ()
    }
  }
  NodeVisitContinue
}

///|
fn visit_node_lex_case_list_exprs(
  node : Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  if node_child(node, name) is Some(list) {
    for entry in list.children {
      let (_, case) = entry
      let case_shadowed = if node_child(case, "pat") is Some(patterns) {
        shadowed_with_node_patterns(shadowed, patterns)
      } else {
        copy_names(shadowed)
      }
      match visit_node_named_expr(case, "guard", case_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let body_shadowed = shadowed_with_node_condition_child(
        case_shadowed, case, "guard",
      )
      match visit_node_named_expr(case, "body", body_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
    }
  }
  NodeVisitContinue
}

///|
fn visit_node_lex_scan_case_list_exprs(
  node : Node,
  name : String,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  if node_child(node, name) is Some(list) {
    for entry in list.children {
      let (_, case) = entry
      let case_shadowed = if node_child(case, "pat") is Some(pattern) {
        shadowed_with_node_pattern(shadowed, pattern)
      } else {
        copy_names(shadowed)
      }
      match visit_node_named_expr(case, "guard", case_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
      let body_shadowed = shadowed_with_node_condition_child(
        case_shadowed, case, "guard",
      )
      match visit_node_named_expr(case, "body", body_shadowed, visitor) {
        NodeVisitReturn => return NodeVisitReturn
        _ => ()
      }
    }
  }
  NodeVisitContinue
}

///|
fn visit_node_list_comprehension_kind_exprs(
  kind : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> (NodeVisitAction, Array[String]) {
  match kind.kind {
    Expr_ListComprehension_Kind_For => {
      match visit_node_binding_list_exprs(kind, "binders", shadowed, visitor) {
        NodeVisitReturn => return (NodeVisitReturn, copy_names(shadowed))
        _ => ()
      }
      let loop_shadowed = if node_child(kind, "binders") is Some(binders) {
        shadowed_with_node_binding_list_binders(shadowed, binders)
      } else {
        copy_names(shadowed)
      }
      match visit_node_named_expr(kind, "condition", loop_shadowed, visitor) {
        NodeVisitReturn => return (NodeVisitReturn, loop_shadowed)
        _ => ()
      }
      let true_shadowed = shadowed_with_node_condition_child(
        loop_shadowed, kind, "condition",
      )
      match
        visit_node_binding_list_exprs(
          kind, "continue_block", true_shadowed, visitor,
        ) {
        NodeVisitReturn => (NodeVisitReturn, true_shadowed)
        _ => (NodeVisitContinue, true_shadowed)
      }
    }
    Expr_ListComprehension_Kind_Foreach => {
      match visit_node_named_expr(kind, "expr", shadowed, visitor) {
        NodeVisitReturn => return (NodeVisitReturn, copy_names(shadowed))
        _ => ()
      }
      match visit_node_binding_list_exprs(kind, "init", shadowed, visitor) {
        NodeVisitReturn => return (NodeVisitReturn, copy_names(shadowed))
        _ => ()
      }
      let loop_shadowed = if node_child(kind, "binders") is Some(binders) {
        shadowed_with_node_optional_binders(shadowed, binders)
      } else {
        copy_names(shadowed)
      }
      if node_child(kind, "init") is Some(init) {
        add_node_binding_list_names(loop_shadowed, init)
      }
      match
        visit_node_binding_list_exprs(
          kind, "continue_block", loop_shadowed, visitor,
        ) {
        NodeVisitReturn => (NodeVisitReturn, loop_shadowed)
        _ => (NodeVisitContinue, loop_shadowed)
      }
    }
    _ =>
      match visit_node_all_child_exprs(kind, shadowed, visitor) {
        NodeVisitReturn => (NodeVisitReturn, copy_names(shadowed))
        _ => (NodeVisitContinue, copy_names(shadowed))
      }
  }
}

///|
fn visit_node_func_exprs(
  func : Node,
  shadowed : Array[String],
  visitor : (ScopedExprNode) -> NodeVisitAction,
) -> NodeVisitAction {
  let body_shadowed = if node_child(func, "parameters") is Some(parameters) {
    shadowed_with_node_parameters(shadowed, parameters)
  } else {
    copy_names(shadowed)
  }
  visit_node_named_expr(func, "body", body_shadowed, visitor)
}

///|
fn is_expr_node(node : Node) -> Bool {
  match node.kind {
    Expr_Apply
    | Expr_Array
    | Expr_ArrayAugmentedSet
    | Expr_ArrayGet
    | Expr_ArrayGetSlice
    | Expr_ArraySet
    | Expr_ArraySpread
    | Expr_As
    | Expr_Assign
    | Expr_Break
    | Expr_BytesInterp
    | Expr_Constant
    | Expr_Constr
    | Expr_Constraint
    | Expr_Continue
    | Expr_Defer
    | Expr_DotApply
    | Expr_Field
    | Expr_For
    | Expr_ForEach
    | Expr_Function
    | Expr_Group
    | Expr_Guard
    | Expr_Hole
    | Expr_Ident
    | Expr_If
    | Expr_Implies
    | Expr_Infix
    | Expr_Interp
    | Expr_Is
    | Expr_IsLexmatch
    | Expr_Let
    | Expr_LetAnd
    | Expr_LetFn
    | Expr_LetMut
    | Expr_Lexmatch
    | Expr_Lexscan
    | Expr_ListComprehension
    | Expr_Map
    | Expr_Match
    | Expr_Method
    | Expr_MultilineString
    | Expr_Mutate
    | Expr_Pipe
    | Expr_ProofAssert
    | Expr_ProofLet
    | Expr_Quantifier
    | Expr_Raise
    | Expr_Record
    | Expr_RecordUpdate
    | Expr_RegexMatch
    | Expr_Return
    | Expr_RevPipe
    | Expr_Sequence
    | Expr_StaticAssert
    | Expr_TemplateWriting
    | Expr_Try
    | Expr_TryOperator
    | Expr_Tuple
    | Expr_Unary
    | Expr_Unit
    | Expr_While => true
    _ => false
  }
}

///|
fn copy_names(names : Array[String]) -> Array[String] {
  let copied : Array[String] = []
  for name in names {
    copied.push(name)
  }
  copied
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

///|
fn shadowed_with_node_binder(
  shadowed : Array[String],
  binder : Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  add_node_binder_name(next, binder)
  next
}

///|
fn shadowed_with_node_pattern(
  shadowed : Array[String],
  pattern : Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  add_node_pattern_names(next, pattern)
  next
}

///|
fn shadowed_with_node_patterns(
  shadowed : Array[String],
  patterns : Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  for entry in patterns.children {
    let (_, pattern) = entry
    add_node_pattern_names(next, pattern)
  }
  next
}

///|
fn shadowed_with_node_parameters(
  shadowed : Array[String],
  parameters : Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  for entry in parameters.children {
    let (_, parameter) = entry
    if node_child(parameter, "binder") is Some(binder) {
      add_node_binder_name(next, binder)
    }
  }
  next
}

///|
fn shadowed_with_node_binding_list_binders(
  shadowed : Array[String],
  bindings : Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  add_node_binding_list_names(next, bindings)
  next
}

///|
fn shadowed_with_node_optional_binders(
  shadowed : Array[String],
  binders : Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  for entry in binders.children {
    let (_, binder) = entry
    add_node_binder_name(next, binder)
  }
  next
}

///|
fn shadowed_with_node_let_and_binders(
  shadowed : Array[String],
  bindings : Node,
) -> Array[String] {
  let next = copy_names(shadowed)
  for entry in bindings.children {
    let (_, binding) = entry
    if node_child(binding, "binder") is Some(binder) {
      add_node_binder_name(next, binder)
    }
  }
  next
}

///|
fn shadowed_with_node_condition_child(
  shadowed : Array[String],
  node : Node,
  name : String,
) -> Array[String] {
  let next = copy_names(shadowed)
  if node_child(node, name) is Some(condition) {
    add_node_condition_binding_names(next, condition)
  }
  next
}

///|
fn add_node_condition_binding_names(
  names : Array[String],
  condition : Node,
) -> Unit {
  match condition.kind {
    Expr_Group =>
      if node_child(condition, "expr") is Some(inner) {
        add_node_condition_binding_names(names, inner)
      }
    Expr_Is =>
      if node_child(condition, "pat") is Some(pattern) {
        add_node_pattern_names(names, pattern)
      }
    Expr_IsLexmatch =>
      if node_child(condition, "pat") is Some(patterns) {
        add_node_pattern_names(names, patterns)
      }
    Expr_RegexMatch => {
      if node_child(condition, "pat") is Some(pattern) {
        add_node_pattern_names(names, pattern)
      }
      if node_child(condition, "bindings") is Some(bindings) {
        add_node_pattern_names(names, bindings)
      }
    }
    Expr_Infix =>
      if node_infix_op(condition, "&&") {
        if node_child(condition, "lhs") is Some(lhs) {
          add_node_condition_binding_names(names, lhs)
        }
        if node_child(condition, "rhs") is Some(rhs) {
          add_node_condition_binding_names(names, rhs)
        }
      }
    _ => ()
  }
}

///|
fn add_node_binding_list_names(names : Array[String], bindings : Node) -> Unit {
  for entry in bindings.children {
    let (_, binding) = entry
    if node_child(binding, "binder") is Some(binder) {
      add_node_binder_name(names, binder)
    }
    if node_child(binding, "init") is Some(binder) {
      add_node_binder_name(names, binder)
    }
  }
}

///|
fn add_node_pattern_names(names : Array[String], pattern : Node) -> Unit {
  if pattern.kind == Binder {
    add_node_binder_name(names, pattern)
  } else {
    for entry in pattern.children {
      let (_, child) = entry
      add_node_pattern_names(names, child)
    }
  }
}

///|
fn add_node_binder_name(names : Array[String], binder : Node) -> Unit {
  if node_binder_name(binder) is Some(name) {
    add_unique_name(names, name)
  }
}

///|
fn node_child(node : Node, name : String) -> Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn node_leaf_string(node : Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn node_leaf_string_child(node : Node, name : String) -> String? {
  if node_child(node, name) is Some(value) {
    node_leaf_string(value)
  } else {
    None
  }
}

///|
fn node_binder_name(node : Node) -> String? {
  if node.kind == Binder {
    node_leaf_string_child(node, "name")
  } else {
    None
  }
}

///|
fn node_infix_op(node : Node, op : String) -> Bool {
  match node_child(node, "op") {
    Some(op_node) => node_var_name(op_node) == Some(op)
    None => false
  }
}

///|
fn node_var_name(node : Node) -> String? {
  guard node.kind == Var else { return None }
  guard node_child(node, "name") is Some(long_ident) else { return None }
  node_long_ident_name(long_ident)
}

///|
fn node_long_ident_name(node : Node) -> String? {
  match node.kind {
    LongIdent_Ident => node_leaf_string_child(node, "value")
    LongIdent_Dot =>
      match
        (
          node_leaf_string_child(node, "pkg"),
          node_leaf_string_child(node, "id"),
        ) {
        (Some(pkg), Some(id)) => Some("@\{pkg}.\{id}")
        _ => None
      }
    _ => None
  }
}
