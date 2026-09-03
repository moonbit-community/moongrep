///|
fn copy_root_names(names : Array[String]) -> Array[String] {
  let copied : Array[String] = []
  for name in names {
    copied.push(name)
  }
  copied
}

///|
fn add_unique_root_name(names : Array[String], name : String) -> Unit {
  for existing in names {
    if existing == name {
      return
    }
  }
  names.push(name)
}

///|
fn add_binder_root_name(
  names : Array[String],
  binder : @untyped_cst.CstNode,
) -> Unit {
  if node_binder_name(binder) is Some(name) {
    add_unique_root_name(names, name)
  }
}

///|
fn root_name_in(root : String, names : Array[String]) -> Bool {
  for name in names {
    if root == name {
      return true
    }
  }
  false
}

///|
fn merge_root_names(
  left : Array[String],
  right : Array[String],
) -> Array[String] {
  let merged = copy_root_names(left)
  for name in right {
    add_unique_root_name(merged, name)
  }
  merged
}

///|
fn restore_scoped_roots(
  base : TaintState,
  scoped : TaintState,
  roots : Array[String],
) -> TaintState {
  if roots.is_empty() {
    return scoped
  }
  let builder = new_state_builder()
  for entry in scoped.entries {
    if !root_name_in(entry.path.root, roots) {
      builder.merge_entry(entry)
    }
  }
  for entry in base.entries {
    if root_name_in(entry.path.root, roots) {
      builder.merge_entry(entry)
    }
  }
  builder.finish()
}

///|
fn restore_result_scoped_roots(
  result : EvalResult,
  base : TaintState,
  roots : Array[String],
) -> EvalResult {
  {
    normal: restore_optional_flow_path(result.normal, base, roots),
    returned: restore_optional_flow_path(result.returned, base, roots),
    raised: restore_optional_flow_path(result.raised, base, roots),
    breaks: restore_labelled_flow_paths(result.breaks, base, roots),
    continues: restore_labelled_flow_paths(result.continues, base, roots),
  }
}

///|
fn restore_optional_flow_path(
  path : FlowPath?,
  base : TaintState,
  roots : Array[String],
) -> FlowPath? {
  match path {
    Some(path) =>
      Some({
        state: restore_scoped_roots(base, path.state, roots),
        value: path.value,
      })
    None => None
  }
}

///|
fn restore_labelled_flow_paths(
  paths : Array[LabelledFlowPath],
  base : TaintState,
  roots : Array[String],
) -> Array[LabelledFlowPath] {
  let restored : Array[LabelledFlowPath] = []
  for entry in paths {
    restored.push({
      label: entry.label,
      path: {
        state: restore_scoped_roots(base, entry.path.state, roots),
        value: entry.path.value,
      },
    })
  }
  restored
}

///|
fn clean_bind_roots(state : TaintState, roots : Array[String]) -> TaintState {
  let mut next = state
  for root in roots {
    next = state_write_path(next, { root, segments: [], }, [])
  }
  next
}

///|
fn tree_root_taint(tree : TaintTree) -> TaintTree {
  let root : TaintTree = []
  for entry in tree {
    if entry.path.is_empty() {
      merge_relative_entry(root, [], entry.origins)
    }
  }
  root
}

///|
fn tree_project_for_binding(
  tree : TaintTree,
  segment : PathSegment,
) -> TaintTree {
  tree_merge(tree_project(tree, [segment]), tree_root_taint(tree))
}

///|
fn pattern_bound_roots(pattern : @untyped_cst.CstNode) -> Array[String] {
  let roots : Array[String] = []
  add_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match pattern.kind {
    @untyped_cst.Pattern_Var =>
      if @cst.normalized_pattern_identifier_name(pattern) is Some(name) {
        add_unique_root_name(roots, name)
      }
    @untyped_cst.Pattern_Alias => {
      if node_child(pattern, "pat") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "alias") is Some(alias_) {
        add_binder_root_name(roots, alias_)
      }
    }
    @untyped_cst.Pattern_Constraint =>
      if node_child(pattern, "pat") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
    @untyped_cst.Pattern_Tuple =>
      for pat in pattern_body_items(pattern) {
        add_pattern_bound_roots(roots, pat)
      }
    @untyped_cst.Pattern_Record =>
      for field in pattern_body_items(pattern) {
        if node_child(field, "pattern") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        } else if field.kind is @untyped_cst.Field_Pattern {
          add_binder_root_name(roots, field)
        }
      }
    @untyped_cst.Pattern_Map =>
      for elem in pattern_body_items(pattern) {
        if node_child(elem, "pattern") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        }
      }
    @untyped_cst.Pattern_Array =>
      for item in array_pattern_items(pattern) {
        add_array_pattern_item_bound_roots(roots, item)
      }
    @untyped_cst.Pattern_Constr | @untyped_cst.Pattern_SpecialConstr =>
      for arg in constructor_pattern_items(pattern) {
        if arg.kind.is_pattern() {
          add_pattern_bound_roots(roots, arg)
        } else if node_child(arg, "pattern") is Some(pat) {
          add_pattern_bound_roots(roots, pat)
        } else if arg.kind is @untyped_cst.Argument_LabelledPun {
          add_binder_root_name(roots, arg)
        }
      }
    @untyped_cst.Pattern_Or | @untyped_cst.Pattern_Range => {
      if node_child(pattern, "pat1") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "pat2") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "lhs") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
      if node_child(pattern, "rhs") is Some(pat) {
        add_pattern_bound_roots(roots, pat)
      }
    }
    @untyped_cst.Pattern_Rest => add_binder_root_name(roots, pattern)
    @untyped_cst.Pattern_Any | @untyped_cst.Pattern_Constant => ()
    _ => ()
  }
}

///|
fn pattern_body_items(
  pattern : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  if @cst.raw_child(pattern, "body") is Some(body) {
    node_items(body)
  } else {
    []
  }
}

///|
fn array_pattern_items(
  pattern : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  guard @cst.raw_child(pattern, "body") is Some(array_patterns) else {
    return []
  }
  if @cst.raw_child(array_patterns, "body") is Some(list) {
    node_items(list)
  } else {
    []
  }
}

///|
fn constructor_pattern_items(
  pattern : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  if @cst.raw_child(pattern, "params") is Some(list) {
    node_items(list)
  } else {
    []
  }
}

///|
fn add_array_pattern_item_bound_roots(
  roots : Array[String],
  item : @untyped_cst.CstNode,
) -> Unit {
  match item.kind {
    @untyped_cst.ArrayPattern_Pattern =>
      if @cst.raw_child(item, "pattern") is Some(pattern) {
        add_pattern_bound_roots(roots, pattern)
      }
    @untyped_cst.ArrayPattern_ConstSpread => add_binder_root_name(roots, item)
    @untyped_cst.Pattern_Rest => add_binder_root_name(roots, item)
    @untyped_cst.ArrayPattern_BytesSpread
    | @untyped_cst.ArrayPattern_StringSpread => ()
    _ => ()
  }
}

///|
fn let_and_bound_roots(bindings : Array[@untyped_cst.CstNode]) -> Array[String] {
  let roots : Array[String] = []
  for binding in bindings {
    add_binder_root_name(roots, binding)
  }
  roots
}

///|
fn bind_binder(
  binder : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  if node_binder_name(binder) is Some(name) {
    state_write_path(state, { root: name, segments: [], }, value)
  } else {
    state
  }
}

///|
fn bind_pattern(
  pattern : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern.kind {
    @untyped_cst.Pattern_Var => bind_binder(pattern, value, state)
    @untyped_cst.Pattern_Alias => {
      let next = if node_child(pattern, "pat") is Some(pat) {
        bind_pattern(pat, value, state)
      } else {
        state
      }
      if node_child(pattern, "alias") is Some(alias_) {
        bind_binder(alias_, value, next)
      } else {
        next
      }
    }
    @untyped_cst.Pattern_Constraint =>
      if node_child(pattern, "pat") is Some(pat) {
        bind_pattern(pat, value, state)
      } else {
        state
      }
    @untyped_cst.Pattern_Tuple => {
      let mut next = state
      let items = pattern_body_items(pattern)
      for index in 0..<items.length() {
        next = bind_pattern(
          items[index],
          tree_project_for_binding(value, TupleIndex(index)),
          next,
        )
      }
      next
    }
    @untyped_cst.Pattern_Record => {
      let mut next = state
      for field in pattern_body_items(pattern) {
        if node_label_name(field) is Some(name) {
          let projected = tree_project_for_binding(value, Field(name))
          if node_child(field, "pattern") is Some(pat) {
            next = bind_pattern(pat, projected, next)
          } else if field.kind is @untyped_cst.Field_Pattern {
            next = bind_binder(field, projected, next)
          }
        }
      }
      next
    }
    @untyped_cst.Pattern_Map => {
      let mut next = state
      for elem in pattern_body_items(pattern) {
        if node_child(elem, "pattern") is Some(pat) {
          next = bind_pattern(pat, value, next)
        }
      }
      next
    }
    @untyped_cst.Pattern_Array => {
      let mut next = state
      let items = array_pattern_items(pattern)
      let mut after_rest = false
      let mut positional_index = 0
      for item in items {
        let segment : PathSegment = if after_rest ||
          item.kind is @untyped_cst.Pattern_Rest {
          AnyIndex
        } else {
          ConstIndex(positional_index.to_string())
        }
        next = bind_array_pattern_item(item, segment, value, next)
        if item.kind is @untyped_cst.Pattern_Rest {
          after_rest = true
        } else {
          positional_index += 1
        }
      }
      next
    }
    @untyped_cst.Pattern_Constr | @untyped_cst.Pattern_SpecialConstr => {
      let mut next = state
      let items = constructor_pattern_items(pattern)
      for index in 0..<items.length() {
        let item = items[index]
        let segment = segment_from_argument_kind(item, index)
        let projected = tree_project_for_binding(value, segment)
        if item.kind.is_pattern() {
          next = bind_pattern(item, projected, next)
        } else if node_child(item, "pattern") is Some(pat) {
          next = bind_pattern(pat, projected, next)
        } else if item.kind is @untyped_cst.Argument_LabelledPun {
          next = bind_binder(item, projected, next)
        }
      }
      next
    }
    @untyped_cst.Pattern_Or =>
      match (node_child(pattern, "lhs"), node_child(pattern, "rhs")) {
        (Some(pat1), Some(pat2)) =>
          state_merge(
            bind_pattern(pat1, value, state),
            bind_pattern(pat2, value, state),
          )
        _ => state
      }
    _ => state
  }
}

///|
fn bind_array_pattern_item(
  item : @untyped_cst.CstNode,
  segment : PathSegment,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match item.kind {
    @untyped_cst.ArrayPattern_Pattern =>
      if @cst.raw_child(item, "pattern") is Some(pattern) {
        bind_pattern(pattern, tree_project_for_binding(value, segment), state)
      } else {
        state
      }
    @untyped_cst.ArrayPattern_ConstSpread | @untyped_cst.Pattern_Rest =>
      bind_binder(item, tree_project_for_binding(value, segment), state)
    @untyped_cst.ArrayPattern_BytesSpread
    | @untyped_cst.ArrayPattern_StringSpread => state
    _ => state
  }
}

///|
fn condition_from_eval_result(result : EvalResult) -> ConditionEval {
  {
    normal: match result.normal {
      Some(path) =>
        Some({
          base_state: path.state,
          true_state: path.state,
          bound_roots: [],
          value: path.value,
        })
      None => None
    },
    exits: flow_without_normal(result),
  }
}

///|
fn eval_condition_scope(
  cond : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> ConditionEval raise {
  match cond.kind {
    @untyped_cst.Expr_Group | @untyped_cst.Expr_Constraint =>
      if node_child(cond, "expr") is Some(expr) {
        eval_condition_scope(expr, state, spec, findings)
      } else {
        condition_from_eval_result(normal_result(state, []))
      }
    @untyped_cst.Expr_Is =>
      match (node_child(cond, "expr"), node_child(cond, "pat")) {
        (Some(expr), Some(pat)) => {
          let matched = eval_expr(expr, state, spec, findings)
          {
            normal: match matched.normal {
              Some(path) =>
                Some({
                  base_state: path.state,
                  true_state: bind_pattern(pat, path.value, path.state),
                  bound_roots: pattern_bound_roots(pat),
                  value: path.value,
                })
              None => None
            },
            exits: flow_without_normal(matched),
          }
        }
        _ => condition_from_eval_result(normal_result(state, []))
      }
    @untyped_cst.Expr_RegexMatch =>
      match (node_child(cond, "expr"), node_child(cond, "pat")) {
        (Some(expr), Some(pat)) => {
          let matched = eval_expr(expr, state, spec, findings)
          let bindings = node_child_items(cond, "bindings")
          let roots = merge_root_names(
            regex_pattern_bound_roots(pat),
            regex_bindings_bound_roots(bindings),
          )
          {
            normal: match matched.normal {
              Some(path) => {
                let pattern_state = bind_regex_pattern(
                  pat,
                  path.value,
                  path.state,
                )
                Some({
                  base_state: path.state,
                  true_state: bind_regex_bindings(
                    bindings,
                    path.value,
                    pattern_state,
                  ),
                  bound_roots: roots,
                  value: path.value,
                })
              }
              None => None
            },
            exits: flow_without_normal(matched),
          }
        }
        _ => condition_from_eval_result(normal_result(state, []))
      }
    @untyped_cst.Expr_Infix =>
      if is_logical_and_expr(cond) &&
        node_child(cond, "lhs") is Some(lhs) &&
        node_child(cond, "rhs") is Some(rhs) {
        eval_and_condition_scope(lhs, rhs, state, spec, findings)
      } else {
        condition_from_eval_result(eval_expr(cond, state, spec, findings))
      }
    _ => condition_from_eval_result(eval_expr(cond, state, spec, findings))
  }
}

///|
fn eval_and_condition_scope(
  lhs : @untyped_cst.CstNode,
  rhs : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> ConditionEval raise {
  let left = eval_condition_scope(lhs, state, spec, findings)
  match left.normal {
    Some(left_path) => {
      let right = eval_condition_scope(
        rhs,
        left_path.true_state,
        spec,
        findings,
      )
      let right_exits = restore_result_scoped_roots(
        right.exits,
        left_path.base_state,
        left_path.bound_roots,
      )
      {
        normal: match right.normal {
          Some(right_path) =>
            Some({
              base_state: restore_scoped_roots(
                left_path.base_state,
                right_path.base_state,
                left_path.bound_roots,
              ),
              true_state: right_path.true_state,
              bound_roots: merge_root_names(
                left_path.bound_roots,
                right_path.bound_roots,
              ),
              value: tree_merge(left_path.value, right_path.value),
            })
          None => None
        },
        exits: flow_join(left.exits, right_exits),
      }
    }
    None => left
  }
}

///|
fn is_logical_and_expr(expr : @untyped_cst.CstNode) -> Bool {
  if node_child(expr, "op") is Some(op) {
    node_var_name(op) == Some("&&")
  } else {
    false
  }
}

///|
fn eval_lex_top_pattern_exprs(
  patterns : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for pattern in patterns {
    let result = match lex_top_pattern_kind(pattern) {
      Some(@untyped_cst.LexTopPattern_Pattern) =>
        eval_lex_pattern_exprs(pattern, current, spec, findings)
      Some(@untyped_cst.LexTopPattern_Binder)
      | Some(@untyped_cst.LexTopPattern_Wildcard) => normal_result(current, [])
      _ => normal_result(current, [])
    }
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

///|
fn eval_lex_pattern_exprs(
  pattern : @untyped_cst.CstNode,
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  match pattern.kind {
    LexPattern_Alias =>
      if node_child(pattern, "pat") is Some(pat) {
        eval_lex_pattern_exprs(pat, state, spec, findings)
      } else {
        normal_result(state, [])
      }
    LexPattern_RegexInterp =>
      eval_interp_elems(
        node_child_items(pattern, "elems"),
        state,
        spec,
        findings,
      )
    LexPattern_Sequence => {
      let mut current = state
      let mut value : TaintTree = []
      let mut exits = empty_flow_summary()
      for pat in pattern_body_items(pattern) {
        let result = eval_lex_pattern_exprs(pat, current, spec, findings)
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
    LexPattern_ConstantRef | LexPattern_Literal => normal_result(state, [])
    _ => normal_result(state, [])
  }
}

///|
fn eval_interp_elems(
  elems : Array[@untyped_cst.CstNode],
  state : TaintState,
  spec : TaintSpec,
  findings : Array[SinkFinding],
) -> EvalResult raise {
  let mut current = state
  let mut value : TaintTree = []
  let mut exits = empty_flow_summary()
  for elem in elems {
    match elem.kind {
      @untyped_cst.InterpSegment_Source =>
        if node_child(elem, "expr") is Some(expr) {
          let result = eval_expr(expr, current, spec, findings)
          exits = flow_join(exits, flow_without_normal(result))
          match result.normal {
            Some(path) => {
              current = path.state
              value = tree_merge(value, path.value)
            }
            None => return exits
          }
        }
      @untyped_cst.InterpSegment_Literal => ()
      _ => ()
    }
  }
  flow_join(exits, normal_result(current, value))
}

///|
fn lex_top_patterns_bound_roots(
  patterns : Array[@untyped_cst.CstNode],
) -> Array[String] {
  let roots : Array[String] = []
  for pattern in patterns {
    add_lex_top_pattern_bound_roots(roots, pattern)
  }
  roots
}

///|
fn add_lex_top_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match lex_top_pattern_kind(pattern) {
    Some(@untyped_cst.LexTopPattern_Binder) =>
      add_binder_root_name(roots, pattern)
    Some(@untyped_cst.LexTopPattern_Pattern) =>
      add_lex_pattern_bound_roots(roots, pattern)
    Some(@untyped_cst.LexTopPattern_Wildcard) => ()
    _ => ()
  }
}

///|
fn lex_top_pattern_items(
  pattern : @untyped_cst.CstNode,
) -> Array[@untyped_cst.CstNode] {
  if pattern.kind is @untyped_cst.Pattern_Tuple &&
    @cst.raw_child(pattern, "pattern_group") is None {
    pattern_body_items(pattern)
  } else {
    [pattern]
  }
}

///|
fn lex_top_pattern_kind(
  pattern : @untyped_cst.CstNode,
) -> @untyped_cst.NodeKind? {
  @cst.raw_child(pattern, "lex_top_pattern").map(item => item.kind)
}

///|
fn add_lex_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match pattern.kind {
    LexPattern_Alias => {
      if node_child(pattern, "pat") is Some(pat) {
        add_lex_pattern_bound_roots(roots, pat)
      }
      add_binder_root_name(roots, pattern)
    }
    LexPattern_Sequence =>
      for pat in pattern_body_items(pattern) {
        add_lex_pattern_bound_roots(roots, pat)
      }
    LexPattern_ConstantRef | LexPattern_Literal | LexPattern_RegexInterp => ()
    _ => ()
  }
}

///|
fn bind_lex_top_patterns(
  patterns : Array[@untyped_cst.CstNode],
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  let mut next = state
  for pattern in patterns {
    next = match lex_top_pattern_kind(pattern) {
      Some(@untyped_cst.LexTopPattern_Binder) =>
        bind_binder(pattern, value, next)
      Some(@untyped_cst.LexTopPattern_Pattern) =>
        bind_lex_pattern(pattern, value, next)
      Some(@untyped_cst.LexTopPattern_Wildcard) => next
      _ => next
    }
  }
  next
}

///|
fn bind_lex_pattern(
  pattern : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern.kind {
    LexPattern_Alias => {
      let next = if node_child(pattern, "pat") is Some(pat) {
        bind_lex_pattern(pat, value, state)
      } else {
        state
      }
      bind_binder(pattern, value, next)
    }
    LexPattern_Sequence => {
      let mut next = state
      for pat in pattern_body_items(pattern) {
        next = bind_lex_pattern(pat, value, next)
      }
      next
    }
    LexPattern_ConstantRef | LexPattern_Literal | LexPattern_RegexInterp =>
      state
    _ => state
  }
}

///|
fn lex_scan_pattern_bound_roots(
  pattern : @untyped_cst.CstNode,
) -> Array[String] {
  let roots : Array[String] = []
  add_lex_scan_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_lex_scan_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match
    @cst.raw_child(pattern, "lex_scan_case_pattern").map(item => item.kind) {
    Some(@untyped_cst.LexScanCasePattern_Binder) =>
      add_binder_root_name(roots, pattern)
    Some(@untyped_cst.LexScanCasePattern_Pattern) =>
      add_regex_pattern_bound_roots(roots, pattern)
    Some(@untyped_cst.LexScanCasePattern_Wildcard) => ()
    _ => ()
  }
}

///|
fn bind_lex_scan_pattern(
  pattern : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match
    @cst.raw_child(pattern, "lex_scan_case_pattern").map(item => item.kind) {
    Some(@untyped_cst.LexScanCasePattern_Binder) =>
      bind_binder(pattern, value, state)
    Some(@untyped_cst.LexScanCasePattern_Pattern) =>
      bind_regex_pattern(pattern, value, state)
    Some(@untyped_cst.LexScanCasePattern_Wildcard) => state
    _ => state
  }
}

///|
fn regex_pattern_bound_roots(pattern : @untyped_cst.CstNode) -> Array[String] {
  let roots : Array[String] = []
  add_regex_pattern_bound_roots(roots, pattern)
  roots
}

///|
fn add_regex_pattern_bound_roots(
  roots : Array[String],
  pattern : @untyped_cst.CstNode,
) -> Unit {
  match pattern.kind {
    RegexPattern_Alias => {
      if node_child(pattern, "pat") is Some(pat) {
        add_regex_pattern_bound_roots(roots, pat)
      }
      add_binder_root_name(roots, pattern)
    }
    RegexPattern_Alternation | RegexPattern_Sequence => {
      if node_child(pattern, "lhs") is Some(pat1) {
        add_regex_pattern_bound_roots(roots, pat1)
      }
      if node_child(pattern, "rhs") is Some(pat2) {
        add_regex_pattern_bound_roots(roots, pat2)
      }
    }
    RegexPattern_Placeholder =>
      if node_child(pattern, "pattern") is Some(inner) {
        add_regex_pattern_bound_roots(roots, inner)
      }
    RegexPattern_Literal | RegexPattern_Reference => ()
    _ => ()
  }
}

///|
fn regex_bindings_bound_roots(
  bindings : Array[@untyped_cst.CstNode],
) -> Array[String] {
  let roots : Array[String] = []
  for binding in bindings {
    if node_optional_child(binding, "binder") is Some(binder) {
      add_binder_root_name(roots, binder)
    }
  }
  roots
}

///|
fn bind_regex_pattern(
  pattern : @untyped_cst.CstNode,
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  match pattern.kind {
    RegexPattern_Alias => {
      let next = if node_child(pattern, "pat") is Some(pat) {
        bind_regex_pattern(pat, value, state)
      } else {
        state
      }
      bind_binder(pattern, value, next)
    }
    RegexPattern_Alternation =>
      match (node_child(pattern, "lhs"), node_child(pattern, "rhs")) {
        (Some(pat1), Some(pat2)) =>
          state_merge(
            bind_regex_pattern(pat1, value, state),
            bind_regex_pattern(pat2, value, state),
          )
        _ => state
      }
    RegexPattern_Sequence =>
      match (node_child(pattern, "lhs"), node_child(pattern, "rhs")) {
        (Some(pat1), Some(pat2)) =>
          bind_regex_pattern(
            pat2,
            value,
            bind_regex_pattern(pat1, value, state),
          )
        _ => state
      }
    RegexPattern_Placeholder =>
      if node_child(pattern, "pattern") is Some(inner) {
        bind_regex_pattern(inner, value, state)
      } else {
        state
      }
    RegexPattern_Literal | RegexPattern_Reference => state
    _ => state
  }
}

///|
fn bind_regex_bindings(
  bindings : Array[@untyped_cst.CstNode],
  value : TaintTree,
  state : TaintState,
) -> TaintState {
  let mut next = state
  for binding in bindings {
    if node_optional_child(binding, "binder") is Some(binder) {
      next = bind_binder(binder, value, next)
    }
  }
  next
}
