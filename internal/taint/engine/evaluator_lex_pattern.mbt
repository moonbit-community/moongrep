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
