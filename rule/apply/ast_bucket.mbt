///|
// AST structural matching used to try every pattern at every collected
// expression. These buckets keep the same observable behavior while skipping
// patterns whose root AST constructor cannot match the candidate expression.
//
// The optimization is deliberately conservative:
//
// * Plain expression captures such as `$(x:exp)`, special whole-expression
//   placeholders such as `__TARGET__` and `__SOURCE__`, and double-underscore
//   ignore placeholders can match many root constructors, so they go into the
//   wildcard bucket.
// * Identifier and constant root captures are precise enough to bucket as
//   `Ident` and `Constant`.
// * Literal structural patterns are bucketed by their parsed root
//   `@syntax.Expr` constructor, for example `Apply`, `Infix`, or `Field`.
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
// Wildcard patterns are always eligible. Keyed patterns are only eligible when
// the candidate expression has the same root constructor key.
priv struct ExprPatternBuckets {
  wildcard : Array[IndexedCompiledRulePattern]
  keyed : Map[String, Array[IndexedCompiledRulePattern]]
}

///|
// The key must stay disjoint from real `@syntax.Expr` constructor names.
fn ast_bucket_wildcard_key() -> String {
  "*"
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
// Maps a candidate expression to the exact structural root used for bucketing.
// This must stay aligned with root cases handled by `matching.match_expr`.
fn expr_root_key(expr : @syntax.Expr) -> String {
  match expr {
    Apply(..) => "Apply"
    Array(..) => "Array"
    ArrayAugmentedSet(..) => "ArrayAugmentedSet"
    ArrayGet(..) => "ArrayGet"
    ArrayGetSlice(..) => "ArrayGetSlice"
    ArraySet(..) => "ArraySet"
    ArraySpread(..) => "ArraySpread"
    As(..) => "As"
    Assign(..) => "Assign"
    Break(..) => "Break"
    Constant(..) => "Constant"
    Constr(..) => "Constr"
    Constraint(..) => "Constraint"
    Continue(..) => "Continue"
    Defer(..) => "Defer"
    DotApply(..) => "DotApply"
    Field(..) => "Field"
    For(..) => "For"
    ForEach(..) => "ForEach"
    Function(..) => "Function"
    Group(..) => "Group"
    Guard(..) => "Guard"
    Hole(..) => "Hole"
    Ident(..) => "Ident"
    If(..) => "If"
    Implies(..) => "Implies"
    Infix(..) => "Infix"
    Interp(..) => "Interp"
    Is(..) => "Is"
    IsLexMatch(..) => "IsLexMatch"
    Let(..) => "Let"
    LetAnd(..) => "LetAnd"
    LetFn(..) => "LetFn"
    LetMut(..) => "LetMut"
    LexMatch(..) => "LexMatch"
    ListComprehension(..) => "ListComprehension"
    Map(..) => "Map"
    Match(..) => "Match"
    Method(..) => "Method"
    MultilineString(..) => "MultilineString"
    Mutate(..) => "Mutate"
    Pipe(..) => "Pipe"
    ProofAssert(..) => "ProofAssert"
    ProofLet(..) => "ProofLet"
    Quantifier(..) => "Quantifier"
    Raise(..) => "Raise"
    Record(..) => "Record"
    RecordUpdate(..) => "RecordUpdate"
    RegexMatch(..) => "RegexMatch"
    Return(..) => "Return"
    RevPipe(..) => "RevPipe"
    Sequence(..) => "Sequence"
    StaticAssert(..) => "StaticAssert"
    TemplateWriting(..) => "TemplateWriting"
    Try(..) => "Try"
    TryOperator(..) => "TryOperator"
    Tuple(..) => "Tuple"
    Unary(..) => "Unary"
    Unit(..) => "Unit"
    While(..) => "While"
  }
}

///|
// Root identifiers may be literal identifiers or one of the inline placeholder
// names compiled from rule syntax. Return `None` for literal identifiers so the
// caller can bucket them as ordinary `Ident` patterns.
fn compiled_root_ident_key(
  compiled : @matching.CompiledExprPattern,
  name : String,
) -> String? {
  if ast_bucket_is_ignore_placeholder(name) ||
    compiled.target_metavar == Some(name) ||
    compiled.source_metavar == Some(name) ||
    ast_bucket_contains_name(compiled.expr_metavars, name) {
    Some(ast_bucket_wildcard_key())
  } else if ast_bucket_contains_name(compiled.identifier_metavars, name) {
    Some("Ident")
  } else if ast_bucket_contains_name(compiled.constant_metavars, name) {
    Some("Constant")
  } else {
    None
  }
}

///|
// Computes the conservative root key for a compiled pattern. A wildcard key
// means "do not filter by root"; every other key is safe to compare directly
// with `expr_root_key(candidate)`.
fn compiled_pattern_root_key(pattern : CompiledRulePattern) -> String {
  let compiled = pattern.compiled
  match compiled.ast {
    Ident(id~, ..) =>
      if @id.normalize_identifier_name_from_var(id) is Some(name) {
        if compiled_root_ident_key(compiled, name) is Some(key) {
          key
        } else {
          expr_root_key(compiled.ast)
        }
      } else {
        expr_root_key(compiled.ast)
      }
    _ => expr_root_key(compiled.ast)
  }
}

///|
// Used by `inside-expr` before running the full outer pattern matcher.
fn ast_bucket_root_key_matches(
  pattern_key : String,
  expr : @syntax.Expr,
) -> Bool {
  pattern_key == ast_bucket_wildcard_key() || pattern_key == expr_root_key(expr)
}

///|
// Precomputes pattern buckets once per structural rule. Arrays are appended in
// source order, so each individual bucket is sorted by `pattern_index`.
fn ExprPatternBuckets::from_patterns(
  patterns : Array[CompiledRulePattern],
) -> ExprPatternBuckets {
  let wildcard : Array[IndexedCompiledRulePattern] = []
  let keyed : Map[String, Array[IndexedCompiledRulePattern]] = {}
  for index in 0..<patterns.length() {
    let indexed = { pattern_index: index, pattern: patterns[index] }
    let key = compiled_pattern_root_key(patterns[index])
    if key == ast_bucket_wildcard_key() {
      wildcard.push(indexed)
    } else if keyed.get(key) is Some(items) {
      items.push(indexed)
      keyed[key] = items
    } else {
      keyed[key] = [indexed]
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
  let keyed = if self.keyed.get(expr_root_key(expr)) is Some(items) {
    items
  } else {
    []
  }
  merge_indexed_patterns(self.wildcard, keyed)
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
