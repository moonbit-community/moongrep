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
