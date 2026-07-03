///|
// AST structural matching used to try every pattern at every collected
// expression. These buckets keep the same observable behavior while skipping
// patterns whose root AST node kind cannot match the candidate expression.
//
// The optimization is deliberately conservative:
//
// * Plain expression captures such as `$(x:exp)`, special whole-expression
//   placeholders such as `__TARGET__` and `__SOURCE__`, and double-underscore
//   ignore placeholders can match many root constructors, so they go into the
//   wildcard bucket.
// * Identifier and constant root captures are precise enough to bucket as
//   `Expr_Ident` and `Expr_Constant`.
// * Literal structural patterns are bucketed by their untyped root node kind,
//   for example `Expr_Apply`, `Expr_Infix`, or `Expr_Field`.
//
// Each bucket stores the original pattern index. When a candidate expression is
// checked, wildcard patterns and the matching keyed bucket are merged by that
// index before matching. This preserves rule semantics: the first matching
// pattern in the YAML `patterns` array still wins and is reported as the same
// `pattern_index`.
//
// `inside-expr` uses the same root-key idea only as a fast outer-expression
// filter. Once the outer pattern binds `__TARGET__`, matching inside the target
// subtree still uses the inner pattern buckets and inherited bindings from the
// outer match.

///|
priv struct IndexedCompiledRulePattern {
  pattern_index : Int
  pattern : CompiledRulePattern
}

///|
priv struct KeyedCompiledRulePatterns {
  key : @untyped_ast.NodeKind
  patterns : Array[IndexedCompiledRulePattern]
}

///|
// Wildcard patterns are always eligible. Keyed patterns are only eligible when
// the candidate expression has the same root constructor key.
priv struct ExprPatternBuckets {
  wildcard : Array[IndexedCompiledRulePattern]
  keyed : Array[KeyedCompiledRulePatterns]
}

///|
fn ast_bucket_contains_name(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn ast_bucket_is_ignore_placeholder(name : String) -> Bool {
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

///|
fn expr_root_key(expr : @syntax.Expr) -> @untyped_ast.NodeKind {
  @untyped_ast.from_expr(expr).kind
}

///|
fn node_root_key(node : @untyped_ast.Node) -> @untyped_ast.NodeKind {
  node.kind
}

///|
// Root identifiers may be literal identifiers or one of the inline placeholder
// names compiled from rule syntax. Return `None` for literal identifiers so the
// caller can bucket them as ordinary `Ident` patterns.
fn compiled_root_ident_key(
  compiled : @matching.CompiledExprPattern,
  name : String,
) -> @untyped_ast.NodeKind?? {
  if ast_bucket_is_ignore_placeholder(name) ||
    compiled.target_metavar == Some(name) ||
    compiled.source_metavar == Some(name) ||
    ast_bucket_contains_name(compiled.expr_metavars, name) {
    Some(None)
  } else if ast_bucket_contains_name(compiled.identifier_metavars, name) {
    Some(Some(Expr_Ident))
  } else if ast_bucket_contains_name(compiled.constant_metavars, name) {
    Some(Some(Expr_Constant))
  } else {
    None
  }
}

///|
// Computes the conservative root key for a compiled pattern. A wildcard key
// means "do not filter by root"; every other key is safe to compare directly
// with `expr_root_key(candidate)`.
fn compiled_pattern_root_key(
  pattern : CompiledRulePattern,
) -> @untyped_ast.NodeKind? {
  let compiled = pattern.compiled
  if compiled.ast.kind == Expr_Ident {
    if ast_bucket_expr_ident_name(compiled.ast) is Some(name) {
      if compiled_root_ident_key(compiled, name) is Some(key) {
        key
      } else {
        Some(node_root_key(compiled.ast))
      }
    } else {
      Some(node_root_key(compiled.ast))
    }
  } else {
    Some(node_root_key(compiled.ast))
  }
}

///|
// Used by `inside-expr` before running the full outer pattern matcher.
fn ast_bucket_root_key_matches(
  pattern_key : @untyped_ast.NodeKind?,
  expr : @syntax.Expr,
) -> Bool {
  match pattern_key {
    None => true
    Some(key) => key == expr_root_key(expr)
  }
}

///|
// Precomputes pattern buckets once per structural rule. Arrays are appended in
// source order, so each individual bucket is sorted by `pattern_index`.
fn ExprPatternBuckets::from_patterns(
  patterns : Array[CompiledRulePattern],
) -> ExprPatternBuckets {
  let wildcard : Array[IndexedCompiledRulePattern] = []
  let keyed : Array[KeyedCompiledRulePatterns] = []
  for index in 0..<patterns.length() {
    let indexed = { pattern_index: index, pattern: patterns[index] }
    let key = compiled_pattern_root_key(patterns[index])
    match key {
      None => wildcard.push(indexed)
      Some(key) => push_keyed_pattern(keyed, key, indexed)
    }
  }
  { wildcard, keyed }
}

///|
// Returns only the patterns that could match `expr`, merged in original rule
// order so caller-visible matching priority does not change.
fn ExprPatternBuckets::patterns_for_expr(
  self : ExprPatternBuckets,
  expr : @syntax.Expr,
) -> Array[IndexedCompiledRulePattern] {
  self.patterns_for_node(@untyped_ast.from_expr(expr))
}

///|
fn ExprPatternBuckets::patterns_for_node(
  self : ExprPatternBuckets,
  node : @untyped_ast.Node,
) -> Array[IndexedCompiledRulePattern] {
  let keyed = if keyed_patterns_for_key(self.keyed, node_root_key(node))
    is Some(items) {
    items
  } else {
    []
  }
  merge_indexed_patterns(self.wildcard, keyed)
}

///|
fn push_keyed_pattern(
  keyed : Array[KeyedCompiledRulePatterns],
  key : @untyped_ast.NodeKind,
  indexed : IndexedCompiledRulePattern,
) -> Unit {
  for index in 0..<keyed.length() {
    if keyed[index].key == key {
      keyed[index].patterns.push(indexed)
      return
    }
  }
  keyed.push({ key, patterns: [indexed] })
}

///|
fn keyed_patterns_for_key(
  keyed : Array[KeyedCompiledRulePatterns],
  key : @untyped_ast.NodeKind,
) -> Array[IndexedCompiledRulePattern]? {
  for entry in keyed {
    if entry.key == key {
      return Some(entry.patterns)
    }
  }
  None
}

///|
fn ast_bucket_child(
  node : @untyped_ast.Node,
  name : String,
) -> @untyped_ast.Node? {
  for entry in node.children {
    let (child_name, value) = entry
    if child_name == Some(name) {
      return Some(value)
    }
  }
  None
}

///|
fn ast_bucket_leaf_string(node : @untyped_ast.Node) -> String? {
  match node.kind {
    Leaf(PString(value)) => Some(value)
    _ => None
  }
}

///|
fn ast_bucket_expr_ident_name(node : @untyped_ast.Node) -> String? {
  guard ast_bucket_child(node, "id") is Some(var_node) else { return None }
  guard ast_bucket_child(var_node, "name") is Some(long_ident) else {
    return None
  }
  match long_ident.kind {
    LongIdent_Ident =>
      if ast_bucket_child(long_ident, "value") is Some(value) {
        ast_bucket_leaf_string(value)
      } else {
        None
      }
    LongIdent_Dot =>
      match
        (
          ast_bucket_child(long_ident, "pkg"),
          ast_bucket_child(long_ident, "id"),
        ) {
        (Some(pkg), Some(id)) =>
          match (ast_bucket_leaf_string(pkg), ast_bucket_leaf_string(id)) {
            (Some(pkg), Some(id)) => Some("@\{pkg}.\{id}")
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
// Merges two already-sorted buckets without reordering pattern priority.
fn merge_indexed_patterns(
  left : Array[IndexedCompiledRulePattern],
  right : Array[IndexedCompiledRulePattern],
) -> Array[IndexedCompiledRulePattern] {
  let result : Array[IndexedCompiledRulePattern] = []
  let mut left_index = 0
  let mut right_index = 0
  while left_index < left.length() || right_index < right.length() {
    if right_index >= right.length() ||
      (
        left_index < left.length() &&
        left[left_index].pattern_index < right[right_index].pattern_index
      ) {
      result.push(left[left_index])
      left_index += 1
    } else {
      result.push(right[right_index])
      right_index += 1
    }
  }
  result
}
