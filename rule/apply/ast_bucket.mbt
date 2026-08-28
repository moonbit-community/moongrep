///|
// CST structural matching used to try every pattern at every collected
// expression. These buckets keep the same observable behavior while skipping
// patterns whose root CST node kind cannot match the candidate expression.
//
// The optimization is deliberately conservative:
//
// * Plain expression captures such as `$(x:exp)`, special whole-expression
//   placeholders such as `__TARGET__` and `__SOURCE__`, and `$_` ignore
//   placeholders can match many root constructors, so they go into the wildcard
//   bucket.
// * Identifier and constant root captures are precise enough to bucket as
//   `Expr_Ident` and `Expr_Constant`.
// * Literal structural patterns are bucketed by their semantic root node kind,
//   for example `Expr_Apply`, `Expr_Infix`, or `Expr_Field`.
//
// Each bucket stores the original pattern index. When a candidate expression is
// checked, wildcard patterns and the matching keyed bucket are merged by that
// index before matching. This preserves rule semantics: the first matching
// pattern in the YAML `patterns` array still wins and is reported as the same
// `pattern_index`.
//
// Ordered `inside-expr` and `inside-toplevel` alternatives use these buckets as
// a fast outer-context filter too. Wildcard and matching keyed alternatives are
// merged by YAML index before matching, so the first successful shape and guard
// still selects `__TARGET__`. Matching inside that target subtree then uses the
// inner pattern buckets and inherited bindings from the selected outer match.

///|
priv struct IndexedCompiledRulePattern {
  pattern_index : Int
  pattern : CompiledRulePattern
}

///|
priv struct KeyedCompiledRulePatterns {
  key : ExprRootKey
  patterns : Array[IndexedCompiledRulePattern]
}

///|
priv enum ExprRootKey {
  IdentRoot
  ConstantRoot
  OtherRoot(@untyped_cst.NodeKind)
} derive(Eq)

///|
// Wildcard patterns are always eligible. Keyed patterns are only eligible when
// the candidate expression has the same root constructor key.
priv struct ExprPatternBuckets {
  wildcard : Array[IndexedCompiledRulePattern]
  keyed : Array[KeyedCompiledRulePatterns]
  sequence : Array[IndexedCompiledRulePattern]
}

///|
fn cst_bucket_contains_name(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn cst_bucket_is_ignore_placeholder(name : String) -> Bool {
  name == "$_"
}

///|
fn node_root_key(node : @untyped_cst.CstNode) -> ExprRootKey {
  match node.kind {
    @untyped_cst.Expr_Ident => IdentRoot
    @untyped_cst.Expr_Constant => ConstantRoot
    _ => OtherRoot(node.kind)
  }
}

///|
// Root identifiers may be literal identifiers or one of the inline placeholder
// names compiled from rule syntax. Return `None` for literal identifiers so the
// caller can bucket them as ordinary `Ident` patterns.
fn compiled_root_ident_key(
  compiled : @matching.CompiledExprPattern,
  name : String,
) -> ExprRootKey?? {
  let logical = cst_bucket_metavar_name(name)
  if cst_bucket_is_ignore_placeholder(name) ||
    compiled.target_metavar == Some(name) ||
    compiled.source_metavar == Some(name) ||
    (
      logical is Some(value) &&
      cst_bucket_contains_name(compiled.expr_metavars, value)
    ) {
    Some(None)
  } else if logical is Some(value) &&
    cst_bucket_contains_name(compiled.identifier_metavars, value) {
    Some(Some(IdentRoot))
  } else if logical is Some(value) &&
    cst_bucket_contains_name(compiled.constant_metavars, value) {
    Some(Some(ConstantRoot))
  } else {
    None
  }
}

///|
fn cst_bucket_metavar_name(raw : String) -> String? {
  let mut start = -1
  for index in 0..<raw.length() {
    if raw[index] == '$' {
      start = index
    }
  }
  if start < 0 {
    return None
  }
  let component = raw[start:]
  if component.has_prefix("$$$") || component == "$_" {
    return None
  }
  if component.has_prefix("$(") && component.has_suffix(")") {
    let end = component.length() - 1
    for index in 2..<end {
      if component[index] == ':' {
        let name = component[2:index].trim()
        if !name.is_empty() {
          return Some(name.to_owned())
        }
        return None
      }
    }
    None
  } else if component.has_prefix("$") && component.length() > 1 {
    Some(component[1:].to_owned())
  } else {
    None
  }
}

///|
// Computes the conservative root key for a compiled pattern. A wildcard key
// means "do not filter by root"; every other key is safe to compare directly
// with `expr_root_key(candidate)`.
fn compiled_pattern_root_key(pattern : CompiledRulePattern) -> ExprRootKey? {
  let compiled = pattern.compiled
  if compiled.cst.kind is @untyped_cst.Expression {
    // A parsed multi-statement fragment can match a sequence or the contents
    // of an explicit block.
    None
  } else if compiled.cst.kind is @untyped_cst.Expr_Ident {
    if @cst.normalized_expr_identifier_name(compiled.cst) is Some(name) {
      if compiled_root_ident_key(compiled, name) is Some(key) {
        key
      } else {
        Some(node_root_key(compiled.cst))
      }
    } else {
      Some(node_root_key(compiled.cst))
    }
  } else {
    Some(node_root_key(compiled.cst))
  }
}

///|
fn compiled_pattern_matches_sequence(pattern : CompiledRulePattern) -> Bool {
  pattern.compiled.cst.kind
  is (@untyped_cst.Expression | @untyped_cst.Expr_Let | @untyped_cst.Expr_Guard)
}

///|
fn ExprPatternBuckets::patterns_for_candidate(
  self : ExprPatternBuckets,
  candidate : @cst.ExprMatchCandidate,
) -> Array[IndexedCompiledRulePattern] {
  match candidate {
    @cst.Direct(node) => self.patterns_for_node(node)
    @cst.Sequence(_) => self.sequence
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
  let sequence : Array[IndexedCompiledRulePattern] = []
  for index in 0..<patterns.length() {
    let indexed = { pattern_index: index, pattern: patterns[index], }
    if compiled_pattern_matches_sequence(patterns[index]) {
      sequence.push(indexed)
    }
    let key = compiled_pattern_root_key(patterns[index])
    if key is Some(key) {
      push_keyed_pattern(keyed, key, indexed)
    } else {
      wildcard.push(indexed)
    }
  }
  { wildcard, keyed, sequence, }
}

///|
fn ExprPatternBuckets::patterns_for_node(
  self : ExprPatternBuckets,
  node : @untyped_cst.CstNode,
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
  key : ExprRootKey,
  indexed : IndexedCompiledRulePattern,
) -> Unit {
  for index in 0..<keyed.length() {
    if keyed[index].key == key {
      keyed[index].patterns.push(indexed)
      return
    }
  }
  keyed.push({ key, patterns: [indexed], })
}

///|
fn keyed_patterns_for_key(
  keyed : Array[KeyedCompiledRulePatterns],
  key : ExprRootKey,
) -> Array[IndexedCompiledRulePattern]? {
  for entry in keyed {
    if entry.key == key {
      return Some(entry.patterns)
    }
  }
  None
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
