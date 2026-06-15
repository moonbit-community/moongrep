///|
pub fn rule_is_relevant_to_source(rule : CompiledRule, source : String) -> Bool {
  prefilter_matches_source(rule.prefilter, source)
}

///|
pub fn prefilter_rules_for_source(
  rules : Array[CompiledRule],
  source : String,
) -> Array[CompiledRule] {
  let relevant : Array[CompiledRule] = []
  for rule in rules {
    if rule_is_relevant_to_source(rule, source) {
      relevant.push(rule)
    }
  }
  relevant
}

///|
fn prefilter_matches_source(prefilter : RulePrefilter, source : String) -> Bool {
  if prefilter.alternatives.is_empty() {
    return true
  }
  for alternative in prefilter.alternatives {
    if alternative.is_empty() {
      return true
    }
    let mut matched = true
    for literal in alternative {
      if !literal_matches_source(literal, source) {
        matched = false
        break
      }
    }
    if matched {
      return true
    }
  }
  false
}

///|
fn literal_matches_source(literal : String, source : String) -> Bool {
  source.contains(literal)
}

///|
fn contains_string(values : Array[String], value : String) -> Bool {
  for item in values {
    if item == value {
      return true
    }
  }
  false
}

///|
fn push_literal(literals : Array[String], value : String) -> Unit {
  if value.length() > 0 {
    literals.push(value)
  }
}

///|
fn concat_string_arrays(
  left : Array[String],
  right : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  for item in left {
    result.push(item)
  }
  for item in right {
    result.push(item)
  }
  result
}

///|
fn unique_literals(values : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for value in values {
    if !contains_string(result, value) {
      result.push(value)
    }
  }
  result
}

///|
fn compile_rule_prefilter(definition : CompiledRuleDefinition) -> RulePrefilter {
  match definition {
    Structural(rule) => compile_structural_prefilter(rule)
    Taint(rule) => compile_taint_prefilter(rule)
  }
}

///|
fn compile_structural_prefilter(rule : CompiledStructuralRule) -> RulePrefilter {
  let alternatives : Array[Array[String]] = []
  let inside_literals : Array[String] = match rule.inside_expr {
    None => []
    Some(pattern) => required_literals_from_compiled_pattern(pattern)
  }
  for pattern in rule.patterns {
    alternatives.push(
      unique_literals(
        concat_string_arrays(
          inside_literals,
          required_literals_from_compiled_pattern(pattern),
        ),
      ),
    )
  }
  { alternatives, }
}

///|
fn compile_taint_prefilter(rule : CompiledTaintRule) -> RulePrefilter {
  let alternatives : Array[Array[String]] = []
  for source in rule.sources {
    let source_literals = required_literals_from_compiled_pattern(
      source.pattern,
    )
    for sink in rule.sinks {
      let sink_literals = required_literals_from_compiled_pattern(sink.pattern)
      alternatives.push(
        unique_literals(concat_string_arrays(source_literals, sink_literals)),
      )
    }
  }
  { alternatives, }
}

///|
fn required_literals_from_compiled_pattern(
  pattern : CompiledRulePattern,
) -> Array[String] {
  let literals : Array[String] = []
  collect_expr_literals(pattern.compiled.ast, pattern.compiled, literals)
  unique_literals(literals)
}

///|
fn is_filter_placeholder(
  name : String,
  compiled : @matching.CompiledExprPattern,
) -> Bool {
  is_underscore_placeholder(name) ||
  compiled.target_metavar == Some(name) ||
  compiled.source_metavar == Some(name) ||
  contains_string(compiled.subtree_metavars, name) ||
  contains_string(compiled.identifier_metavars, name)
}

///|
fn is_underscore_placeholder(name : String) -> Bool {
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
fn collect_var_literal(
  var_ : @syntax.Var,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match @ident.normalize_identifier_name_from_var(var_) {
    Some(name) =>
      if !is_filter_placeholder(name, compiled) {
        push_literal(literals, name)
      }
    None => ()
  }
}

///|
fn collect_binder_literal(
  binder : @syntax.Binder,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match @ident.normalize_identifier_name_from_binder(binder) {
    Some(name) =>
      if !is_filter_placeholder(name, compiled) {
        push_literal(literals, name)
      }
    None => ()
  }
}

///|
fn collect_label_literal(
  label : @syntax.Label,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match @ident.normalize_identifier_name_from_label(label) {
    Some(name) =>
      if !is_filter_placeholder(name, compiled) {
        push_literal(literals, name)
      }
    None => ()
  }
}

///|
fn collect_constant_literal(
  c : @syntax.Constant,
  literals : Array[String],
) -> Unit {
  match c {
    BigInt(value)
    | Byte(value)
    | Bytes(value)
    | Char(value)
    | Double(value)
    | Float(value)
    | Int64(value)
    | Regex(value)
    | String(value)
    | UInt(value)
    | UInt64(value) => push_literal(literals, value)
    Int(value) => if value.length() >= 2 { push_literal(literals, value) }
    Bool(value) => push_literal(literals, "\{value}")
  }
}

///|
fn collect_expr_literals(
  expr : @syntax.Expr,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match expr {
    Ident(id~, ..) => collect_var_literal(id, compiled, literals)
    Constant(c~, ..) => collect_constant_literal(c, literals)
    Apply(func~, args~, ..) => {
      collect_expr_literals(func, compiled, literals)
      collect_argument_literals(args, compiled, literals)
    }
    DotApply(self~, method_name~, args~, ..) => {
      collect_expr_literals(self, compiled, literals)
      collect_label_literal(method_name, compiled, literals)
      collect_argument_literals(args, compiled, literals)
    }
    Field(record~, accessor~, ..) => {
      collect_expr_literals(record, compiled, literals)
      collect_accessor_literals(accessor, compiled, literals)
    }
    Infix(op~, lhs~, rhs~, ..) => {
      collect_var_literal(op, compiled, literals)
      collect_expr_literals(lhs, compiled, literals)
      collect_expr_literals(rhs, compiled, literals)
    }
    Unary(op~, expr~, ..) => {
      collect_var_literal(op, compiled, literals)
      collect_expr_literals(expr, compiled, literals)
    }
    Assign(var_~, expr~, augmented_by~, ..) => {
      collect_var_literal(var_, compiled, literals)
      collect_expr_literals(expr, compiled, literals)
      match augmented_by {
        Some(op) => collect_var_literal(op, compiled, literals)
        None => ()
      }
    }
    ArrayAugmentedSet(op~, array~, index~, value~, ..) => {
      collect_var_literal(op, compiled, literals)
      collect_expr_literals(array, compiled, literals)
      collect_expr_literals(index, compiled, literals)
      collect_expr_literals(value, compiled, literals)
    }
    Array(exprs~, ..) | Tuple(exprs~, ..) =>
      collect_expr_list_literals(exprs, compiled, literals)
    ArraySpread(elems~, ..) =>
      collect_spreadable_elem_literals(elems, compiled, literals)
    Sequence(exprs~, last_expr~, ..) => {
      collect_expr_list_literals(exprs, compiled, literals)
      collect_expr_literals(last_expr, compiled, literals)
    }
    ArrayGet(array~, index~, ..) => {
      collect_expr_literals(array, compiled, literals)
      collect_expr_literals(index, compiled, literals)
    }
    ArraySet(array~, index~, value~, ..) => {
      collect_expr_literals(array, compiled, literals)
      collect_expr_literals(index, compiled, literals)
      collect_expr_literals(value, compiled, literals)
    }
    ArrayGetSlice(array~, start_index~, end_index~, ..) => {
      collect_expr_literals(array, compiled, literals)
      collect_optional_expr_literals(start_index, compiled, literals)
      collect_optional_expr_literals(end_index, compiled, literals)
    }
    Group(expr~, ..)
    | Constraint(expr~, ..)
    | As(expr~, ..)
    | TryOperator(body=expr, ..)
    | Raise(err_value=expr, ..) =>
      collect_expr_literals(expr, compiled, literals)
    Break(arg~, label~, ..) => {
      collect_optional_expr_literals(arg, compiled, literals)
      collect_optional_label_literal(label, compiled, literals)
    }
    Continue(args~, label~, ..) => {
      collect_expr_list_literals(args, compiled, literals)
      collect_optional_label_literal(label, compiled, literals)
    }
    Defer(expr~, body~, ..) => {
      collect_expr_literals(expr, compiled, literals)
      collect_expr_literals(body, compiled, literals)
    }
    Return(return_value~, ..) =>
      collect_optional_expr_literals(return_value, compiled, literals)
    If(cond~, ifso~, ifnot~, ..) => {
      collect_expr_literals(cond, compiled, literals)
      collect_expr_literals(ifso, compiled, literals)
      collect_optional_expr_literals(ifnot, compiled, literals)
    }
    For(binders~, condition~, continue_block~, body~, for_else~, label~, ..) => {
      collect_binder_expr_pairs_literals(binders, compiled, literals)
      collect_optional_expr_literals(condition, compiled, literals)
      collect_binder_expr_pairs_literals(continue_block, compiled, literals)
      collect_expr_literals(body, compiled, literals)
      collect_optional_expr_literals(for_else, compiled, literals)
      collect_optional_label_literal(label, compiled, literals)
    }
    ForEach(binders~, expr~, body~, else_block~, label~, ..) => {
      collect_optional_binders_literals(binders, compiled, literals)
      collect_expr_literals(expr, compiled, literals)
      collect_expr_literals(body, compiled, literals)
      collect_optional_expr_literals(else_block, compiled, literals)
      collect_optional_label_literal(label, compiled, literals)
    }
    Guard(cond~, otherwise~, body~, ..) => {
      collect_expr_literals(cond, compiled, literals)
      collect_optional_expr_literals(otherwise, compiled, literals)
      collect_expr_literals(body, compiled, literals)
    }
    Interp(elems~, ..) =>
      collect_interp_elem_literals(elems, compiled, literals)
    Is(expr~, pat~, ..) => {
      collect_expr_literals(expr, compiled, literals)
      collect_pattern_literals(pat, compiled, literals)
    }
    Let(pattern~, expr=bound_expr, body~, ..) => {
      collect_pattern_literals(pattern, compiled, literals)
      collect_expr_literals(bound_expr, compiled, literals)
      collect_expr_literals(body, compiled, literals)
    }
    LetMut(binder~, expr=bound_expr, body~, ..) => {
      collect_binder_literal(binder, compiled, literals)
      collect_expr_literals(bound_expr, compiled, literals)
      collect_expr_literals(body, compiled, literals)
    }
    Function(func~, ..) => collect_func_literals(func, compiled, literals)
    LetFn(name=binder, func~, body~, ..) => {
      collect_binder_literal(binder, compiled, literals)
      collect_func_literals(func, compiled, literals)
      collect_expr_literals(body, compiled, literals)
    }
    LetAnd(bindings~, body~, ..) => {
      collect_let_and_binding_literals(bindings, compiled, literals)
      collect_expr_literals(body, compiled, literals)
    }
    Map(elems~, ..) => collect_map_expr_elem_literals(elems, compiled, literals)
    Match(expr~, cases~, ..) => {
      collect_expr_literals(expr, compiled, literals)
      collect_case_literals(cases, compiled, literals)
    }
    Method(method_name~, ..) =>
      collect_label_literal(method_name, compiled, literals)
    MultilineString(elems~, ..) =>
      collect_multiline_string_elem_literals(elems, compiled, literals)
    Mutate(record~, accessor~, field~, augmented_by~, ..) => {
      collect_expr_literals(record, compiled, literals)
      collect_accessor_literals(accessor, compiled, literals)
      collect_expr_literals(field, compiled, literals)
      match augmented_by {
        Some(op) => collect_var_literal(op, compiled, literals)
        None => ()
      }
    }
    Pipe(lhs~, rhs~, ..) | RevPipe(lhs~, rhs~, ..) | Implies(lhs~, rhs~, ..) => {
      collect_expr_literals(lhs, compiled, literals)
      collect_expr_literals(rhs, compiled, literals)
    }
    Record(fields~, ..) =>
      collect_field_def_literals(fields, compiled, literals)
    RecordUpdate(record~, fields~, ..) => {
      collect_expr_literals(record, compiled, literals)
      collect_field_def_literals(fields, compiled, literals)
    }
    Try(body~, catch_~, try_else~, ..) => {
      collect_expr_literals(body, compiled, literals)
      collect_case_literals(catch_, compiled, literals)
      collect_optional_case_list_literals(try_else, compiled, literals)
    }
    While(loop_cond~, loop_body~, while_else~, label~, ..) => {
      collect_expr_literals(loop_cond, compiled, literals)
      collect_expr_literals(loop_body, compiled, literals)
      collect_optional_expr_literals(while_else, compiled, literals)
      collect_optional_label_literal(label, compiled, literals)
    }
    Constr(constr~, ..) => push_literal(literals, constr.name.name)
    _ => ()
  }
}

///|
fn collect_expr_list_literals(
  exprs : @list.List[@syntax.Expr],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for expr in exprs {
    collect_expr_literals(expr, compiled, literals)
  }
}

///|
fn collect_optional_expr_literals(
  expr : @syntax.Expr?,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match expr {
    Some(expr) => collect_expr_literals(expr, compiled, literals)
    None => ()
  }
}

///|
fn collect_optional_label_literal(
  label : @syntax.Label?,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match label {
    Some(label) => collect_label_literal(label, compiled, literals)
    None => ()
  }
}

///|
fn collect_argument_literals(
  args : @list.List[@syntax.Argument],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for argument in args {
    match argument.kind {
      Labelled(label)
      | LabelledPun(label)
      | LabelledOption(label~, ..)
      | LabelledOptionPun(label~, ..) =>
        collect_label_literal(label, compiled, literals)
      Positional => ()
    }
    collect_expr_literals(argument.value, compiled, literals)
  }
}

///|
fn collect_accessor_literals(
  accessor : @syntax.Accessor,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match accessor {
    Label(label) => collect_label_literal(label, compiled, literals)
    Index(tuple_index~, ..) => push_literal(literals, "\{tuple_index}")
    Newtype(..) => ()
  }
}

///|
fn collect_spreadable_elem_literals(
  elems : @list.List[@syntax.SpreadableElem],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for elem in elems {
    match elem {
      Regular(expr) | Spread(expr~, ..) =>
        collect_expr_literals(expr, compiled, literals)
    }
  }
}

///|
fn collect_binder_expr_pairs_literals(
  pairs : @list.List[(@syntax.Binder, @syntax.Expr)],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for pair in pairs {
    let (binder, expr) = pair
    collect_binder_literal(binder, compiled, literals)
    collect_expr_literals(expr, compiled, literals)
  }
}

///|
fn collect_optional_binders_literals(
  binders : @list.List[@syntax.Binder?],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for binder in binders {
    match binder {
      Some(binder) => collect_binder_literal(binder, compiled, literals)
      None => ()
    }
  }
}

///|
fn collect_case_literals(
  cases : @list.List[@syntax.Case],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for case in cases {
    collect_pattern_literals(case.pattern, compiled, literals)
    collect_optional_expr_literals(case.guard_, compiled, literals)
    collect_expr_literals(case.body, compiled, literals)
  }
}

///|
fn collect_optional_case_list_literals(
  cases : @list.List[@syntax.Case]?,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match cases {
    Some(cases) => collect_case_literals(cases, compiled, literals)
    None => ()
  }
}

///|
fn collect_field_def_literals(
  fields : @list.List[@syntax.FieldDef],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for field in fields {
    collect_label_literal(field.label, compiled, literals)
    collect_expr_literals(field.expr, compiled, literals)
  }
}

///|
fn collect_map_expr_elem_literals(
  elems : @list.List[@syntax.MapExprElem],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for elem in elems {
    collect_constant_literal(elem.key, literals)
    collect_expr_literals(elem.expr, compiled, literals)
  }
}

///|
fn collect_interp_elem_literals(
  elems : @list.List[@syntax.InterpElem],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for elem in elems {
    match elem {
      Expr(expr~, ..) => collect_expr_literals(expr, compiled, literals)
      Literal(repr~, ..) => push_literal(literals, repr)
      Source(_) => ()
    }
  }
}

///|
fn collect_multiline_string_elem_literals(
  elems : @list.List[@syntax.MultilineStringElem],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for elem in elems {
    match elem {
      String(value) => push_literal(literals, value)
      Interp(elems) => collect_interp_elem_literals(elems, compiled, literals)
    }
  }
}

///|
fn collect_let_and_binding_literals(
  bindings : @list.List[(@syntax.Binder, @syntax.Type?, @syntax.Func)],
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for binding in bindings {
    let (binder, _ty, func) = binding
    collect_binder_literal(binder, compiled, literals)
    collect_func_literals(func, compiled, literals)
  }
}

///|
fn collect_pattern_literals(
  pattern : @syntax.Pattern,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match pattern {
    Var(binder) => collect_binder_literal(binder, compiled, literals)
    Constant(c~, ..) => collect_constant_literal(c, literals)
    Alias(pat~, alias_~, ..) => {
      collect_pattern_literals(pat, compiled, literals)
      collect_binder_literal(alias_, compiled, literals)
    }
    Tuple(pats~, ..) =>
      for item in pats {
        collect_pattern_literals(item, compiled, literals)
      }
    Or(pat1~, pat2~, ..) | Range(lhs=pat1, rhs=pat2, ..) => {
      collect_pattern_literals(pat1, compiled, literals)
      collect_pattern_literals(pat2, compiled, literals)
    }
    Constraint(pat~, ..) => collect_pattern_literals(pat, compiled, literals)
    _ => ()
  }
}

///|
fn collect_func_literals(
  func : @syntax.Func,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  for parameter in func.parameters {
    collect_parameter_literals(parameter, compiled, literals)
  }
  collect_expr_literals(func.body, compiled, literals)
}

///|
fn collect_parameter_literals(
  parameter : @syntax.Parameter,
  compiled : @matching.CompiledExprPattern,
  literals : Array[String],
) -> Unit {
  match parameter {
    Positional(binder~, ..)
    | Labelled(binder~, ..)
    | QuestionOptional(binder~, ..) =>
      collect_binder_literal(binder, compiled, literals)
    Optional(binder~, default~, ..) => {
      collect_binder_literal(binder, compiled, literals)
      collect_expr_literals(default, compiled, literals)
    }
    DiscardPositional(..) => ()
  }
}
