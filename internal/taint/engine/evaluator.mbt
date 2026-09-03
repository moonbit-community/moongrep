///|
fn control_label_name(node : @untyped_cst.CstNode) -> String? {
  let label = if node_child(node, "label") is Some(label) {
    label
  } else if @cst.raw_child(node, "label") is Some(label) {
    label
  } else {
    return None
  }
  if node_label_name(label) is Some(name) {
    Some(name)
  } else {
    @cst.raw_child(label, "name_value").bind(@cst.normalized_name)
  }
}

///|
fn analyze_single_function_like(
  node : @untyped_cst.CstNode,
  spec : TaintSpec,
) -> AnalysisResult raise {
  let function_like = function_like_from_impl(node)
  let findings : Array[SinkFinding] = []
  let mut state = empty_state()
  for source in spec.sources {
    match source {
      EntryPath(path, origin_id, note) =>
        if function_has_param_root(function_like, path.root) {
          let origin_site = ValueSite::Path(path)
          let origin : TaintOrigin = {
            rule_id: spec.rule_id,
            origin_id,
            site: origin_site,
            note,
          }
          state = state_write_path(state, path, [
            { path: [], origins: [origin], },
          ])
        }
      CallReturn(_, _, _, _) => ()
    }
  }
  let _ = eval_expr(function_like.body, state, spec, findings)
  {
    rule_id: spec.rule_id,
    function_name: function_like.name,
    function_loc: function_like.loc,
    findings,
  }
}

///|
fn function_has_param_root(function_like : FunctionLike, root : String) -> Bool {
  for path in function_like.params {
    if path.root == root {
      return true
    }
  }
  false
}

///|
fn eval_expr(
  expr : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  match expr.kind {
    @untyped_cst.Expr_Block =>
      eval_cst_sequence(@cst.sequence_items(expr), state, spec, findings)
    @untyped_cst.Expr_LabelledBlock =>
      if node_child(expr, "body") is Some(body) {
        eval_labelled_block(
          control_label_name(expr),
          body,
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Ident => eval_path_like(expr, state)
    @untyped_cst.Expr_Field =>
      match (node_child(expr, "record"), node_child(expr, "accessor")) {
        (Some(record), Some(accessor)) =>
          eval_field_expr(expr, record, accessor, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_ArrayGet =>
      match (node_child(expr, "array"), node_child(expr, "index")) {
        (Some(array), Some(index)) =>
          eval_array_get_expr(expr, array, index, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Tuple =>
      eval_tuple_expr(node_child_items(expr, "exprs"), state, spec, findings)
    @untyped_cst.Expr_Array =>
      eval_array_expr(node_child_items(expr, "exprs"), state, spec, findings)
    @untyped_cst.Expr_Record =>
      eval_record_expr(node_child_items(expr, "fields"), state, spec, findings)
    @untyped_cst.Expr_Group | @untyped_cst.Expr_Constraint =>
      if node_child(expr, "expr") is Some(inner) {
        eval_expr(inner, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Sequence =>
      eval_cst_sequence(@cst.sequence_items(expr), state, spec, findings)
    @untyped_cst.Expr_Let =>
      match
        (
          node_child(expr, "pattern"),
          node_child(expr, "expr"),
          node_child(expr, "body"),
        ) {
        (Some(pattern), Some(bound_expr), Some(body)) =>
          eval_let(pattern, bound_expr, body, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_LetMut =>
      match
        (
          node_child(expr, "binder"),
          node_child(expr, "expr"),
          node_child(expr, "body"),
        ) {
        (Some(binder), Some(bound_expr), Some(body)) =>
          eval_let_binder(binder, bound_expr, body, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Assign =>
      if @cst.raw_child(expr, "rhs") is Some(rhs) {
        eval_assign(expr, rhs, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Mutate =>
      match (@cst.raw_child(expr, "self"), @cst.raw_child(expr, "rhs")) {
        (Some(receiver), Some(rhs)) =>
          eval_mutate(expr, receiver, rhs, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Apply =>
      match (node_child(expr, "func"), node_child(expr, "args")) {
        (Some(func), Some(args)) =>
          eval_apply_call(expr, func, args, expr.loc, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_DotApply =>
      match
        (
          node_child(expr, "self"),
          node_child(expr, "method_name"),
          node_child(expr, "args"),
        ) {
        (Some(self), Some(method_name), Some(args)) =>
          eval_dot_apply_call(
            expr,
            self,
            method_name,
            args,
            expr.loc,
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Pipe =>
      match (node_child(expr, "lhs"), node_child(expr, "rhs")) {
        (Some(lhs), Some(rhs)) =>
          eval_pipe_call(expr, lhs, rhs, expr.loc, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_RevPipe =>
      match (node_child(expr, "lhs"), node_child(expr, "rhs")) {
        (Some(lhs), Some(rhs)) =>
          eval_rev_pipe_call(expr, lhs, rhs, expr.loc, state, spec, findings)
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_If =>
      match (node_child(expr, "cond"), node_child(expr, "ifso")) {
        (Some(cond), Some(ifso)) =>
          eval_if(
            cond,
            ifso,
            node_optional_child(expr, "ifnot"),
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Match =>
      if node_child(expr, "expr") is Some(scrutinee) {
        eval_match(
          scrutinee,
          node_child_items(expr, "cases"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_LexMatch =>
      if node_child(expr, "expr") is Some(scrutinee) {
        eval_lex_match(
          scrutinee,
          node_child_items(expr, "cases"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_LexScan =>
      if node_child(expr, "expr") is Some(scrutinee) {
        eval_lex_scan(
          scrutinee,
          node_child_items(expr, "cases"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Try =>
      if node_child(expr, "body") is Some(body) {
        eval_try(
          body,
          node_child_items(expr, "catch"),
          node_optional_child(expr, "try_else"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_While =>
      match (node_child(expr, "loop_cond"), node_child(expr, "loop_body")) {
        (Some(loop_cond), Some(loop_body)) =>
          eval_while(
            control_label_name(expr),
            expr.loc,
            loop_cond,
            loop_body,
            node_optional_child(expr, "while_else"),
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_For =>
      if node_child(expr, "body") is Some(body) {
        eval_for(
          control_label_name(expr),
          expr.loc,
          node_child_items(expr, "binders"),
          @cst.raw_child(expr, "cond"),
          node_child_items(expr, "continue_block"),
          body,
          @cst.raw_child(expr, "else"),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_ForEach =>
      match (node_child(expr, "expr"), node_child(expr, "body")) {
        (Some(collection), Some(body)) =>
          eval_for_each(
            control_label_name(expr),
            expr.loc,
            node_child_items(expr, "binders"),
            collection,
            node_child_items(expr, "init"),
            node_child_items(expr, "continue_block"),
            body,
            node_optional_child(expr, "else_block"),
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_LetFn =>
      match (node_child(expr, "name"), node_child(expr, "body")) {
        (Some(name), Some(body)) => {
          let roots : Array[String] = []
          add_binder_root_name(roots, name)
          eval_clean_root_scope(body, roots, state, spec, findings)
        }
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_LetAnd =>
      if node_child(expr, "body") is Some(body) {
        eval_clean_root_scope(
          body,
          let_and_bound_roots(node_child_items(expr, "bindings")),
          state,
          spec,
          findings,
        )
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Function => normal_result(state, [])
    @untyped_cst.Expr_Return =>
      if node_optional_child(expr, "return_value") is Some(value) {
        flow_normal_to_return(eval_expr(value, state, spec, findings))
      } else {
        return_result(state, [])
      }
    @untyped_cst.Expr_Break =>
      if node_optional_child(expr, "arg") is Some(value) {
        flow_normal_to_break(
          eval_expr(value, state, spec, findings),
          control_label_name(expr),
        )
      } else {
        break_result(control_label_name(expr), state, [])
      }
    @untyped_cst.Expr_Raise =>
      if node_child(expr, "err_value") is Some(value) {
        flow_normal_to_raise(eval_expr(value, state, spec, findings))
      } else {
        raise_result(state, [])
      }
    @untyped_cst.Expr_Continue => {
      let result = eval_children(
        node_child_items(expr, "args"),
        state,
        spec,
        findings,
      )
      flow_normal_to_continue(result, control_label_name(expr))
    }
    _ => eval_unknown_expr(expr, state, spec, findings)
  }
}

///|
fn eval_unknown_expr(
  expr : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  match expr.kind {
    @untyped_cst.Expr_Infix =>
      eval_children(
        node_children_by_names(expr, ["lhs", "rhs"]),
        state,
        spec,
        findings,
      )
    @untyped_cst.Expr_Unary =>
      if node_child(expr, "expr") is Some(inner) {
        eval_expr(inner, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_As
    | @untyped_cst.Expr_TryOperator
    | @untyped_cst.Expr_ProofAssert
    | @untyped_cst.Expr_TemplateWriting =>
      if node_child(expr, "expr") is Some(inner) {
        eval_expr(inner, state, spec, findings)
      } else if node_child(expr, "body") is Some(body) {
        eval_expr(body, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_ArraySet | @untyped_cst.Expr_ArrayAugmentedSet =>
      eval_children(
        node_children_by_names(expr, ["array", "index", "value"]),
        state,
        spec,
        findings,
      )
    @untyped_cst.Expr_ArrayGetSlice =>
      eval_children(
        node_optional_children_by_names(expr, [
          "array", "start_index", "end_index",
        ]),
        state,
        spec,
        findings,
      )
    @untyped_cst.Expr_Defer =>
      eval_children(
        node_children_by_names(expr, ["expr", "body"]),
        state,
        spec,
        findings,
      )
    @untyped_cst.Expr_Guard =>
      match (node_child(expr, "cond"), node_child(expr, "body")) {
        (Some(cond), Some(body)) =>
          eval_guard(
            cond,
            node_optional_child(expr, "otherwise"),
            body,
            state,
            spec,
            findings,
          )
        _ => normal_result(state, [])
      }
    @untyped_cst.Expr_Is | @untyped_cst.Expr_RegexMatch =>
      if node_child(expr, "expr") is Some(inner) {
        eval_expr(inner, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    @untyped_cst.Expr_Interp | @untyped_cst.Expr_BytesInterp =>
      eval_interp_elems(node_child_items(expr, "elems"), state, spec, findings)
    @untyped_cst.Expr_Map => {
      let mut current = state
      let mut value : TaintTree = []
      let mut exits = empty_flow_summary()
      for elem in node_child_items(expr, "elems") {
        if node_child(elem, "expr") is Some(child) {
          let result = eval_expr(child, current, spec, findings)
          exits = flow_join(exits, flow_without_normal(result))
          match result.normal {
            Some(path) => {
              current = path.state
              value = tree_merge(value, path.value)
            }
            None => return exits
          }
        }
      }
      flow_join(exits, normal_result(current, value))
    }
    @untyped_cst.Expr_RecordUpdate =>
      if node_child(expr, "record") is Some(record) {
        let base = eval_expr(record, state, spec, findings)
        match base.normal {
          Some(path) =>
            flow_sequence(
              base,
              eval_record_expr(
                node_child_items(expr, "fields"),
                path.state,
                spec,
                findings,
              ),
            )
          None => base
        }
      } else {
        normal_result(state, [])
      }
    _ => normal_result(state, [])
  }
}

///|
fn node_children_by_names(
  node : @untyped_cst.CstNode,
  names : Array[String],
) -> Array[@untyped_cst.CstNode] {
  let children : Array[@untyped_cst.CstNode] = []
  for name in names {
    if node_child(node, name) is Some(child) {
      children.push(child)
    }
  }
  children
}

///|
fn node_optional_children_by_names(
  node : @untyped_cst.CstNode,
  names : Array[String],
) -> Array[@untyped_cst.CstNode] {
  let children : Array[@untyped_cst.CstNode] = []
  for name in names {
    if node_optional_child(node, name) is Some(child) {
      children.push(child)
    }
  }
  children
}

///|
fn eval_children(
  children : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for child in children {
    let result = eval_expr(child, current, spec, findings)
    exits = flow_join(exits, flow_without_normal(result))
    match result.normal {
      Some(path) => {
        current = path.state
        value = tree_merge(value, path.value)
      }
      None => return exits
    }
  }
  flow_join(exits, normal_result(current, value))
}
