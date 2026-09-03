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
