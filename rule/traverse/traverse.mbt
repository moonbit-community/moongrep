///|
pub fn count_supported_name_in_expr(expr : @syntax.Expr, name : String) -> Int {
  if @id.normalize_identifier_name_from_expr(expr) is Some(found) {
    if found == name {
      1
    } else {
      0
    }
  } else {
    count_supported_name_in_expr_children(expr, name)
  }
}

///|
fn count_supported_name_in_expr_children(
  expr : @syntax.Expr,
  name : String,
) -> Int {
  match expr {
    Apply(func~, args~, ..) =>
      count_supported_name_in_expr(func, name) +
      count_supported_name_in_arguments(args, name)
    DotApply(self~, method_name~, args~, ..) =>
      count_supported_name_in_expr(self, name) +
      count_supported_name_in_label(method_name, name) +
      count_supported_name_in_arguments(args, name)
    Field(record~, accessor~, ..) =>
      count_supported_name_in_expr(record, name) +
      count_supported_name_in_accessor(accessor, name)
    Infix(op~, lhs~, rhs~, ..) =>
      count_supported_name_in_var(op, name) +
      count_supported_name_in_expr(lhs, name) +
      count_supported_name_in_expr(rhs, name)
    Unary(op~, expr~, ..) =>
      count_supported_name_in_var(op, name) +
      count_supported_name_in_expr(expr, name)
    Assign(var_~, expr~, augmented_by~, ..) =>
      count_supported_name_in_var(var_, name) +
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_optional_var(augmented_by, name)
    ArrayAugmentedSet(op~, array~, index~, value~, ..) =>
      count_supported_name_in_var(op, name) +
      count_supported_name_in_expr(array, name) +
      count_supported_name_in_expr(index, name) +
      count_supported_name_in_expr(value, name)
    Array(exprs~, ..) | Tuple(exprs~, ..) =>
      count_supported_name_in_expr_list(exprs, name)
    ArraySpread(elems~, ..) =>
      count_supported_name_in_spreadable_elems(elems, name)
    ArrayGet(array~, index~, ..) =>
      count_supported_name_in_expr(array, name) +
      count_supported_name_in_expr(index, name)
    ArraySet(array~, index~, value~, ..) =>
      count_supported_name_in_expr(array, name) +
      count_supported_name_in_expr(index, name) +
      count_supported_name_in_expr(value, name)
    ArrayGetSlice(array~, start_index~, end_index~, ..) =>
      count_supported_name_in_expr(array, name) +
      count_supported_name_in_optional_expr(start_index, name) +
      count_supported_name_in_optional_expr(end_index, name)
    Group(expr~, ..) | Constraint(expr~, ..) | As(expr~, ..) =>
      count_supported_name_in_expr(expr, name)
    If(cond~, ifso~, ifnot~, ..) =>
      count_supported_name_in_expr(cond, name) +
      count_supported_name_in_expr(ifso, name) +
      count_supported_name_in_optional_expr(ifnot, name)
    Guard(cond~, otherwise~, body~, ..) =>
      count_supported_name_in_expr(cond, name) +
      count_supported_name_in_optional_expr(otherwise, name) +
      count_supported_name_in_expr(body, name)
    Let(pattern~, expr~, body~, ..) =>
      count_supported_name_in_pattern(pattern, name) +
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_expr(body, name)
    LetMut(binder~, expr~, body~, ..) =>
      count_supported_name_in_binder(binder, name) +
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_expr(body, name)
    For(
      binders~,
      condition~,
      continue_block~,
      body~,
      for_else~,
      where_clause~,
      label~,
      ..
    ) =>
      count_supported_name_in_binder_expr_pairs(binders, name) +
      count_supported_name_in_optional_expr(condition, name) +
      count_supported_name_in_binder_expr_pairs(continue_block, name) +
      count_supported_name_in_expr(body, name) +
      count_supported_name_in_optional_expr(for_else, name) +
      count_supported_name_in_optional_where_clause(where_clause, name) +
      count_supported_name_in_optional_label(label, name)
    ForEach(
      binders~,
      expr~,
      init~,
      continue_block~,
      body~,
      else_block~,
      where_clause~,
      label~,
      ..
    ) =>
      count_supported_name_in_optional_binders(binders, name) +
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_binder_expr_pairs(init, name) +
      count_supported_name_in_binder_expr_pairs(continue_block, name) +
      count_supported_name_in_expr(body, name) +
      count_supported_name_in_optional_expr(else_block, name) +
      count_supported_name_in_optional_where_clause(where_clause, name) +
      count_supported_name_in_optional_label(label, name)
    Return(return_value~, ..) =>
      count_supported_name_in_optional_expr(return_value, name)
    Raise(err_value~, ..) => count_supported_name_in_expr(err_value, name)
    Pipe(lhs~, rhs~, ..) | RevPipe(lhs~, rhs~, ..) | Implies(lhs~, rhs~, ..) =>
      count_supported_name_in_expr(lhs, name) +
      count_supported_name_in_expr(rhs, name)
    Interp(elems~, ..) => count_supported_name_in_interp_elems(elems, name)
    Record(fields~, ..) => count_supported_name_in_field_defs(fields, name)
    RecordUpdate(record~, fields~, ..) =>
      count_supported_name_in_expr(record, name) +
      count_supported_name_in_field_defs(fields, name)
    Mutate(record~, accessor~, field~, augmented_by~, ..) =>
      count_supported_name_in_expr(record, name) +
      count_supported_name_in_accessor(accessor, name) +
      count_supported_name_in_expr(field, name) +
      count_supported_name_in_optional_var(augmented_by, name)
    Match(expr~, cases~, ..) =>
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_cases(cases, name)
    Is(expr~, pat~, ..) =>
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_pattern(pat, name)
    IsLexMatch(expr~, strategy~, pat~, ..) =>
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_optional_label(strategy, name) +
      count_supported_name_in_lex_top_patterns(pat, name)
    LexMatch(strategy~, expr~, cases~, ..) =>
      count_supported_name_in_optional_label(strategy, name) +
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_lex_cases(cases, name)
    ListComprehension(kind~, guard_~, body~, ..) =>
      count_supported_name_in_list_comprehension_kind(kind, name) +
      count_supported_name_in_optional_expr(guard_, name) +
      count_supported_name_in_expr(body, name)
    Try(body~, catch_~, try_else~, ..) =>
      count_supported_name_in_expr(body, name) +
      count_supported_name_in_cases(catch_, name) +
      count_supported_name_in_optional_cases(try_else, name)
    TryOperator(body~, ..) => count_supported_name_in_expr(body, name)
    While(loop_cond~, loop_body~, while_else~, label~, ..) =>
      count_supported_name_in_expr(loop_cond, name) +
      count_supported_name_in_expr(loop_body, name) +
      count_supported_name_in_optional_expr(while_else, name) +
      count_supported_name_in_optional_label(label, name)
    Break(arg~, label~, ..) =>
      count_supported_name_in_optional_expr(arg, name) +
      count_supported_name_in_optional_label(label, name)
    Continue(args~, label~, ..) =>
      count_supported_name_in_expr_list(args, name) +
      count_supported_name_in_optional_label(label, name)
    Defer(expr~, body~, ..) =>
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_expr(body, name)
    ProofAssert(expr~, ..) => count_supported_name_in_expr(expr, name)
    ProofLet(binder~, expr~, ..) =>
      count_supported_name_in_binder(binder, name) +
      count_supported_name_in_expr(expr, name)
    Quantifier(binder~, body~, ..) =>
      count_supported_name_in_binder(binder, name) +
      count_supported_name_in_expr(body, name)
    RegexMatch(expr~, pat~, bindings~, ..) =>
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_regex_pattern(pat, name) +
      count_supported_name_in_regex_bindings(bindings, name)
    StaticAssert(body~, ..) => count_supported_name_in_expr(body, name)
    TemplateWriting(expr~, template~, ..) =>
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_expr(template, name)
    Function(func~, ..) => count_supported_name_in_func(func, name)
    LetFn(name=binder, func~, body~, ..) =>
      count_supported_name_in_binder(binder, name) +
      count_supported_name_in_func(func, name) +
      count_supported_name_in_expr(body, name)
    LetAnd(bindings~, body~, ..) =>
      count_supported_name_in_let_and_bindings(bindings, name) +
      count_supported_name_in_expr(body, name)
    Map(elems~, ..) => count_supported_name_in_map_expr_elems(elems, name)
    MultilineString(elems~, ..) =>
      count_supported_name_in_multiline_string_elems(elems, name)
    Constr(..) | Constant(..) | Hole(..) | Method(..) | Unit(..) => 0
    _ => 0
  }
}

///|
fn count_supported_name_in_arguments(
  args : @list.List[@syntax.Argument],
  name : String,
) -> Int {
  let mut total = 0
  for arg in args {
    total += count_supported_name_in_argument_kind(arg.kind, name)
    total += count_supported_name_in_expr(arg.value, name)
  }
  total
}

///|
fn count_supported_name_in_argument_kind(
  kind : @syntax.ArgumentKind,
  name : String,
) -> Int {
  match kind {
    Positional => 0
    Labelled(label) | LabelledPun(label) =>
      count_supported_name_in_label(label, name)
    LabelledOption(label~, ..) | LabelledOptionPun(label~, ..) =>
      count_supported_name_in_label(label, name)
  }
}

///|
fn count_supported_name_in_accessor(
  accessor : @syntax.Accessor,
  name : String,
) -> Int {
  match accessor {
    Label(label) => count_supported_name_in_label(label, name)
    _ => 0
  }
}

///|
fn count_supported_name_in_var(v : @syntax.Var, name : String) -> Int {
  if @id.normalize_identifier_name_from_var(v) is Some(found) {
    if found == name {
      1
    } else {
      0
    }
  } else {
    0
  }
}

///|
fn count_supported_name_in_optional_var(v : @syntax.Var?, name : String) -> Int {
  if v is Some(v) {
    count_supported_name_in_var(v, name)
  } else {
    0
  }
}

///|
fn count_supported_name_in_binder(
  binder : @syntax.Binder,
  name : String,
) -> Int {
  if @id.normalize_identifier_name_from_binder(binder) is Some(found) {
    if found == name {
      1
    } else {
      0
    }
  } else {
    0
  }
}

///|
fn count_supported_name_in_label(label : @syntax.Label, name : String) -> Int {
  if @id.normalize_identifier_name_from_label(label) is Some(found) {
    if found == name {
      1
    } else {
      0
    }
  } else {
    0
  }
}

///|
fn count_supported_name_in_optional_label(
  label : @syntax.Label?,
  name : String,
) -> Int {
  if label is Some(label) {
    count_supported_name_in_label(label, name)
  } else {
    0
  }
}

///|
fn count_supported_name_in_pattern(
  pattern : @syntax.Pattern,
  name : String,
) -> Int {
  if @id.normalize_identifier_name_from_pattern(pattern) is Some(found) {
    if found == name {
      1
    } else {
      0
    }
  } else {
    match pattern {
      Alias(pat~, alias_~, ..) =>
        count_supported_name_in_pattern(pat, name) +
        count_supported_name_in_binder(alias_, name)
      Tuple(pats~, ..) => count_supported_name_in_patterns(pats, name)
      Or(pat1~, pat2~, ..) =>
        count_supported_name_in_pattern(pat1, name) +
        count_supported_name_in_pattern(pat2, name)
      Range(lhs~, rhs~, ..) =>
        count_supported_name_in_pattern(lhs, name) +
        count_supported_name_in_pattern(rhs, name)
      _ => 0
    }
  }
}

///|
fn count_supported_name_in_expr_list(
  exprs : @list.List[@syntax.Expr],
  name : String,
) -> Int {
  let mut total = 0
  for expr in exprs {
    total += count_supported_name_in_expr(expr, name)
  }
  total
}

///|
fn count_supported_name_in_spreadable_elems(
  elems : @list.List[@syntax.SpreadableElem],
  name : String,
) -> Int {
  let mut total = 0
  for elem in elems {
    total += match elem {
      Regular(expr) | Spread(expr~, ..) =>
        count_supported_name_in_expr(expr, name)
    }
  }
  total
}

///|
fn count_supported_name_in_optional_expr(
  expr : @syntax.Expr?,
  name : String,
) -> Int {
  if expr is Some(expr) {
    count_supported_name_in_expr(expr, name)
  } else {
    0
  }
}

///|
fn count_supported_name_in_optional_where_clause(
  clause : @syntax.WhereClause?,
  name : String,
) -> Int {
  if clause is Some(clause) {
    count_supported_name_in_where_clause(clause, name)
  } else {
    0
  }
}

///|
fn count_supported_name_in_where_clause(
  clause : @syntax.WhereClause,
  name : String,
) -> Int {
  count_supported_name_in_field_defs(clause.fields, name)
}

///|
fn count_supported_name_in_binder_expr_pairs(
  pairs : @list.List[(@syntax.Binder, @syntax.Expr)],
  name : String,
) -> Int {
  let mut total = 0
  for pair in pairs {
    let (binder, expr) = pair
    total += count_supported_name_in_binder(binder, name)
    total += count_supported_name_in_expr(expr, name)
  }
  total
}

///|
fn count_supported_name_in_optional_binders(
  binders : @list.List[@syntax.Binder?],
  name : String,
) -> Int {
  let mut total = 0
  for binder in binders {
    if binder is Some(binder) {
      total += count_supported_name_in_binder(binder, name)
    }
  }
  total
}

///|
fn count_supported_name_in_interp_elems(
  elems : @list.List[@syntax.InterpElem],
  name : String,
) -> Int {
  let mut total = 0
  for elem in elems {
    total += match elem {
      Expr(expr~, ..) => count_supported_name_in_expr(expr, name)
      Literal(..) | Source(_) => 0
    }
  }
  total
}

///|
fn count_supported_name_in_multiline_string_elems(
  elems : @list.List[@syntax.MultilineStringElem],
  name : String,
) -> Int {
  let mut total = 0
  for elem in elems {
    total += match elem {
      Interp(elems) => count_supported_name_in_interp_elems(elems, name)
      String(_) => 0
    }
  }
  total
}

///|
fn count_supported_name_in_lex_cases(
  cases : @list.List[@syntax.LexCase],
  name : String,
) -> Int {
  let mut total = 0
  for case in cases {
    total += count_supported_name_in_lex_top_patterns(case.pat, name)
    total += count_supported_name_in_optional_expr(case.guard_, name)
    total += count_supported_name_in_expr(case.body, name)
  }
  total
}

///|
fn count_supported_name_in_lex_top_patterns(
  patterns : @list.List[@syntax.LexTopPattern],
  name : String,
) -> Int {
  let mut total = 0
  for pattern in patterns {
    total += match pattern {
      Binder(binder) => count_supported_name_in_binder(binder, name)
      Pattern(pattern) => count_supported_name_in_lex_pattern(pattern, name)
      Wildcard(..) => 0
    }
  }
  total
}

///|
fn count_supported_name_in_lex_pattern(
  pattern : @syntax.LexPattern,
  name : String,
) -> Int {
  match pattern {
    Alias(pat~, binder~, ..) =>
      count_supported_name_in_lex_pattern(pat, name) +
      count_supported_name_in_binder(binder, name)
    RegexInterp(elems~, ..) => count_supported_name_in_interp_elems(elems, name)
    Sequence(pats~, ..) => {
      let mut total = 0
      for pat in pats {
        total += count_supported_name_in_lex_pattern(pat, name)
      }
      total
    }
    ConstantRef(lid~, ..) => count_supported_name_in_long_ident(lid, name)
    Regex(..) => 0
  }
}

///|
fn count_supported_name_in_list_comprehension_kind(
  kind : @syntax.ListComprehensionKind,
  name : String,
) -> Int {
  match kind {
    For(binders~, condition~, continue_block~, ..) =>
      count_supported_name_in_binder_expr_pairs(binders, name) +
      count_supported_name_in_optional_expr(condition, name) +
      count_supported_name_in_binder_expr_pairs(continue_block, name)
    Foreach(binders~, expr~, init~, continue_block~) =>
      count_supported_name_in_optional_binders(binders, name) +
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_binder_expr_pairs(init, name) +
      count_supported_name_in_binder_expr_pairs(continue_block, name)
  }
}

///|
fn count_supported_name_in_regex_pattern(
  pattern : @syntax.RegexPattern,
  name : String,
) -> Int {
  match pattern {
    Alias(pat~, binder~, ..) =>
      count_supported_name_in_regex_pattern(pat, name) +
      count_supported_name_in_binder(binder, name)
    Alternation(pat1~, pat2~, ..) | Sequence(pat1~, pat2~, ..) =>
      count_supported_name_in_regex_pattern(pat1, name) +
      count_supported_name_in_regex_pattern(pat2, name)
    Reference(lid~, ..) => count_supported_name_in_long_ident(lid, name)
    Literal(..) => 0
  }
}

///|
fn count_supported_name_in_regex_bindings(
  bindings : @list.List[(@syntax.Label, @syntax.Binder?)],
  name : String,
) -> Int {
  let mut total = 0
  for binding in bindings {
    let (label, binder) = binding
    total += count_supported_name_in_label(label, name)
    if binder is Some(binder) {
      total += count_supported_name_in_binder(binder, name)
    }
  }
  total
}

///|
fn count_supported_name_in_long_ident(
  lid : @syntax.LongIdent,
  name : String,
) -> Int {
  match lid {
    Ident(name=found) => if found == name { 1 } else { 0 }
    Dot(id~, ..) => if id == name { 1 } else { 0 }
  }
}

///|
fn count_supported_name_in_patterns(
  patterns : @list.List[@syntax.Pattern],
  name : String,
) -> Int {
  let mut total = 0
  for pattern in patterns {
    total += count_supported_name_in_pattern(pattern, name)
  }
  total
}

///|
fn count_supported_name_in_cases(
  cases : @list.List[@syntax.Case],
  name : String,
) -> Int {
  let mut total = 0
  for case in cases {
    total += count_supported_name_in_pattern(case.pattern, name)
    total += count_supported_name_in_optional_expr(case.guard_, name)
    total += count_supported_name_in_expr(case.body, name)
  }
  total
}

///|
fn count_supported_name_in_optional_cases(
  cases : @list.List[@syntax.Case]?,
  name : String,
) -> Int {
  if cases is Some(cases) {
    count_supported_name_in_cases(cases, name)
  } else {
    0
  }
}

///|
fn count_supported_name_in_field_defs(
  fields : @list.List[@syntax.FieldDef],
  name : String,
) -> Int {
  let mut total = 0
  for field in fields {
    total += count_supported_name_in_label(field.label, name)
    total += count_supported_name_in_expr(field.expr, name)
  }
  total
}

///|
fn count_supported_name_in_map_expr_elems(
  elems : @list.List[@syntax.MapExprElem],
  name : String,
) -> Int {
  let mut total = 0
  for elem in elems {
    total += count_supported_name_in_expr(elem.expr, name)
  }
  total
}

///|
fn count_supported_name_in_func(func : @syntax.Func, name : String) -> Int {
  let mut total = 0
  for param in func.parameters {
    total += count_supported_name_in_parameter(param, name)
  }
  total + count_supported_name_in_expr(func.body, name)
}

///|
fn count_supported_name_in_parameter(
  param : @syntax.Parameter,
  name : String,
) -> Int {
  match param {
    DiscardPositional(..) => 0
    Labelled(binder~, ..)
    | Optional(binder~, ..)
    | Positional(binder~, ..)
    | QuestionOptional(binder~, ..) =>
      count_supported_name_in_binder(binder, name)
  }
}

///|
fn count_supported_name_in_let_and_bindings(
  bindings : @list.List[(@syntax.Binder, @syntax.Type?, @syntax.Func)],
  name : String,
) -> Int {
  let mut total = 0
  for binding in bindings {
    let (binder, _ty, func) = binding
    total += count_supported_name_in_binder(binder, name)
    total += count_supported_name_in_func(func, name)
  }
  total
}

///|
pub fn collect_impl_exprs(
  node : @syntax.Impl,
  exprs : Array[@syntax.Expr],
) -> Unit {
  match node {
    TopExpr(expr~, ..) => collect_exprs(expr, exprs)
    TopFuncDef(decl_body=DeclBody(expr~), ..) => collect_exprs(expr, exprs)
    TopImpl(body=DeclBody(expr~), ..) => collect_exprs(expr, exprs)
    TopLetDef(expr~, ..) => collect_exprs(expr, exprs)
    TopTest(expr~, ..) => collect_exprs(expr, exprs)
    TopView(body~, ..) => collect_exprs(body, exprs)
    _ => ()
  }
}

///|
pub(all) struct ScopedExpr {
  expr : @syntax.Expr
  shadowed_names : Array[String]
}

///|
pub fn collect_scoped_exprs(
  expr : @syntax.Expr,
  exprs : Array[ScopedExpr],
) -> Unit {
  collect_scoped_exprs_with_shadow(expr, [], exprs)
}

///|
fn collect_scoped_exprs_with_shadow(
  expr : @syntax.Expr,
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  exprs.push({ expr, shadowed_names: copy_names(shadowed) })
  match expr {
    Apply(func~, args~, ..) => {
      collect_scoped_exprs_with_shadow(func, shadowed, exprs)
      collect_scoped_argument_exprs(args, shadowed, exprs)
    }
    DotApply(self~, args~, ..) => {
      collect_scoped_exprs_with_shadow(self, shadowed, exprs)
      collect_scoped_argument_exprs(args, shadowed, exprs)
    }
    Field(record~, ..) =>
      collect_scoped_exprs_with_shadow(record, shadowed, exprs)
    Infix(lhs~, rhs~, ..) => {
      collect_scoped_exprs_with_shadow(lhs, shadowed, exprs)
      collect_scoped_exprs_with_shadow(rhs, shadowed, exprs)
    }
    Unary(expr~, ..) | Assign(expr~, ..) =>
      collect_scoped_exprs_with_shadow(expr, shadowed, exprs)
    Array(exprs=items, ..) | Tuple(exprs=items, ..) =>
      collect_scoped_expr_list(items, shadowed, exprs)
    Sequence(exprs=items, last_expr~, ..) => {
      collect_scoped_expr_list(items, shadowed, exprs)
      collect_scoped_exprs_with_shadow(last_expr, shadowed, exprs)
    }
    ArrayGet(array~, index~, ..) => {
      collect_scoped_exprs_with_shadow(array, shadowed, exprs)
      collect_scoped_exprs_with_shadow(index, shadowed, exprs)
    }
    ArraySet(array~, index~, value~, ..)
    | ArrayAugmentedSet(array~, index~, value~, ..) => {
      collect_scoped_exprs_with_shadow(array, shadowed, exprs)
      collect_scoped_exprs_with_shadow(index, shadowed, exprs)
      collect_scoped_exprs_with_shadow(value, shadowed, exprs)
    }
    ArraySpread(elems~, ..) =>
      collect_scoped_spreadable_elem_exprs(elems, shadowed, exprs)
    ArrayGetSlice(array~, start_index~, end_index~, ..) => {
      collect_scoped_exprs_with_shadow(array, shadowed, exprs)
      collect_scoped_optional_expr(start_index, shadowed, exprs)
      collect_scoped_optional_expr(end_index, shadowed, exprs)
    }
    Group(expr~, ..) | Constraint(expr~, ..) | As(expr~, ..) =>
      collect_scoped_exprs_with_shadow(expr, shadowed, exprs)
    If(cond~, ifso~, ifnot~, ..) => {
      collect_scoped_exprs_with_shadow(cond, shadowed, exprs)
      collect_scoped_exprs_with_shadow(ifso, shadowed, exprs)
      collect_scoped_optional_expr(ifnot, shadowed, exprs)
    }
    Guard(cond~, otherwise~, body~, ..) => {
      collect_scoped_exprs_with_shadow(cond, shadowed, exprs)
      collect_scoped_optional_expr(otherwise, shadowed, exprs)
      collect_scoped_exprs_with_shadow(body, shadowed, exprs)
    }
    Let(pattern~, expr=bound_expr, body~, ..) => {
      collect_scoped_exprs_with_shadow(bound_expr, shadowed, exprs)
      let body_shadowed = shadowed_with_pattern(shadowed, pattern)
      collect_scoped_exprs_with_shadow(body, body_shadowed, exprs)
    }
    LetMut(binder~, expr=bound_expr, body~, ..) => {
      collect_scoped_exprs_with_shadow(bound_expr, shadowed, exprs)
      let body_shadowed = shadowed_with_binder(shadowed, binder)
      collect_scoped_exprs_with_shadow(body, body_shadowed, exprs)
    }
    For(
      binders~,
      condition~,
      continue_block~,
      body~,
      for_else~,
      where_clause~,
      ..
    ) => {
      collect_scoped_binder_expr_pairs(binders, shadowed, exprs)
      let loop_shadowed = shadowed_with_binder_expr_pair_binders(
        shadowed, binders,
      )
      collect_scoped_optional_expr(condition, loop_shadowed, exprs)
      collect_scoped_binder_expr_pairs(continue_block, loop_shadowed, exprs)
      collect_scoped_exprs_with_shadow(body, loop_shadowed, exprs)
      collect_scoped_optional_expr(for_else, loop_shadowed, exprs)
      collect_scoped_optional_where_clause_exprs(
        where_clause, loop_shadowed, exprs,
      )
    }
    ForEach(
      binders~,
      expr=iter,
      init~,
      continue_block~,
      body~,
      else_block~,
      where_clause~,
      ..
    ) => {
      collect_scoped_exprs_with_shadow(iter, shadowed, exprs)
      collect_scoped_binder_expr_pairs(init, shadowed, exprs)
      let loop_shadowed = shadowed_with_optional_binders(shadowed, binders)
      add_binder_expr_pair_names(loop_shadowed, init)
      collect_scoped_binder_expr_pairs(continue_block, loop_shadowed, exprs)
      collect_scoped_exprs_with_shadow(body, loop_shadowed, exprs)
      collect_scoped_optional_expr(else_block, loop_shadowed, exprs)
      collect_scoped_optional_where_clause_exprs(
        where_clause, loop_shadowed, exprs,
      )
    }
    Return(return_value~, ..) =>
      collect_scoped_optional_expr(return_value, shadowed, exprs)
    Raise(err_value~, ..) =>
      collect_scoped_exprs_with_shadow(err_value, shadowed, exprs)
    Pipe(lhs~, rhs~, ..) | RevPipe(lhs~, rhs~, ..) | Implies(lhs~, rhs~, ..) => {
      collect_scoped_exprs_with_shadow(lhs, shadowed, exprs)
      collect_scoped_exprs_with_shadow(rhs, shadowed, exprs)
    }
    Interp(elems~, ..) =>
      collect_scoped_interp_elem_exprs(elems, shadowed, exprs)
    Record(fields~, ..) =>
      collect_scoped_field_def_exprs(fields, shadowed, exprs)
    RecordUpdate(record~, fields~, ..) => {
      collect_scoped_exprs_with_shadow(record, shadowed, exprs)
      collect_scoped_field_def_exprs(fields, shadowed, exprs)
    }
    Mutate(record~, field~, ..) => {
      collect_scoped_exprs_with_shadow(record, shadowed, exprs)
      collect_scoped_exprs_with_shadow(field, shadowed, exprs)
    }
    Match(expr=matched, cases~, ..) => {
      collect_scoped_exprs_with_shadow(matched, shadowed, exprs)
      collect_scoped_case_exprs(cases, shadowed, exprs)
    }
    Is(expr=matched, ..) =>
      collect_scoped_exprs_with_shadow(matched, shadowed, exprs)
    IsLexMatch(expr=matched, pat~, ..) => {
      collect_scoped_exprs_with_shadow(matched, shadowed, exprs)
      collect_scoped_lex_top_pattern_exprs(pat, shadowed, exprs)
    }
    LexMatch(expr=matched, cases~, ..) => {
      collect_scoped_exprs_with_shadow(matched, shadowed, exprs)
      collect_scoped_lex_case_exprs(cases, shadowed, exprs)
    }
    ListComprehension(kind~, guard_~, body~, ..) => {
      let body_shadowed = collect_scoped_list_comprehension_kind_exprs(
        kind, shadowed, exprs,
      )
      collect_scoped_optional_expr(guard_, body_shadowed, exprs)
      collect_scoped_exprs_with_shadow(body, body_shadowed, exprs)
    }
    Try(body~, catch_~, try_else~, ..) => {
      collect_scoped_exprs_with_shadow(body, shadowed, exprs)
      collect_scoped_case_exprs(catch_, shadowed, exprs)
      if try_else is Some(cases) {
        collect_scoped_case_exprs(cases, shadowed, exprs)
      }
    }
    TryOperator(body~, ..) =>
      collect_scoped_exprs_with_shadow(body, shadowed, exprs)
    While(loop_cond~, loop_body~, while_else~, ..) => {
      collect_scoped_exprs_with_shadow(loop_cond, shadowed, exprs)
      collect_scoped_exprs_with_shadow(loop_body, shadowed, exprs)
      collect_scoped_optional_expr(while_else, shadowed, exprs)
    }
    Break(arg~, ..) => collect_scoped_optional_expr(arg, shadowed, exprs)
    Continue(args~, ..) => collect_scoped_expr_list(args, shadowed, exprs)
    Defer(expr=deferred, body~, ..) => {
      collect_scoped_exprs_with_shadow(deferred, shadowed, exprs)
      collect_scoped_exprs_with_shadow(body, shadowed, exprs)
    }
    ProofAssert(expr=asserted, ..) | ProofLet(expr=asserted, ..) =>
      collect_scoped_exprs_with_shadow(asserted, shadowed, exprs)
    Quantifier(binder~, body~, ..) => {
      let body_shadowed = shadowed_with_binder(shadowed, binder)
      collect_scoped_exprs_with_shadow(body, body_shadowed, exprs)
    }
    RegexMatch(expr=matched, pat~, ..) => {
      collect_scoped_exprs_with_shadow(matched, shadowed, exprs)
      collect_scoped_regex_pattern_exprs(pat, shadowed, exprs)
    }
    StaticAssert(body~, ..) =>
      collect_scoped_exprs_with_shadow(body, shadowed, exprs)
    TemplateWriting(expr=writer, template~, ..) => {
      collect_scoped_exprs_with_shadow(writer, shadowed, exprs)
      collect_scoped_exprs_with_shadow(template, shadowed, exprs)
    }
    Function(func~, ..) => collect_scoped_func_exprs(func, shadowed, exprs)
    LetFn(name=binder, func~, body~, ..) => {
      let name_shadowed = shadowed_with_binder(shadowed, binder)
      collect_scoped_func_exprs(func, name_shadowed, exprs)
      collect_scoped_exprs_with_shadow(body, name_shadowed, exprs)
    }
    LetAnd(bindings~, body~, ..) => {
      let binding_shadowed = shadowed_with_let_and_binders(shadowed, bindings)
      for binding in bindings {
        let (_binder, _ty, func) = binding
        collect_scoped_func_exprs(func, binding_shadowed, exprs)
      }
      collect_scoped_exprs_with_shadow(body, binding_shadowed, exprs)
    }
    Map(elems~, ..) =>
      for elem in elems {
        collect_scoped_exprs_with_shadow(elem.expr, shadowed, exprs)
      }
    MultilineString(elems~, ..) =>
      collect_scoped_multiline_string_elem_exprs(elems, shadowed, exprs)
    _ => ()
  }
}

///|
fn collect_scoped_argument_exprs(
  args : @list.List[@syntax.Argument],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for arg in args {
    collect_scoped_exprs_with_shadow(arg.value, shadowed, exprs)
  }
}

///|
fn collect_scoped_expr_list(
  list : @list.List[@syntax.Expr],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for expr in list {
    collect_scoped_exprs_with_shadow(expr, shadowed, exprs)
  }
}

///|
fn collect_scoped_spreadable_elem_exprs(
  elems : @list.List[@syntax.SpreadableElem],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for elem in elems {
    match elem {
      Regular(expr) | Spread(expr~, ..) =>
        collect_scoped_exprs_with_shadow(expr, shadowed, exprs)
    }
  }
}

///|
fn collect_scoped_optional_expr(
  expr : @syntax.Expr?,
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  if expr is Some(expr) {
    collect_scoped_exprs_with_shadow(expr, shadowed, exprs)
  }
}

///|
fn collect_scoped_optional_where_clause_exprs(
  clause : @syntax.WhereClause?,
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  if clause is Some(clause) {
    collect_scoped_field_def_exprs(clause.fields, shadowed, exprs)
  }
}

///|
fn collect_scoped_binder_expr_pairs(
  pairs : @list.List[(@syntax.Binder, @syntax.Expr)],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for pair in pairs {
    let (_binder, expr) = pair
    collect_scoped_exprs_with_shadow(expr, shadowed, exprs)
  }
}

///|
fn collect_scoped_interp_elem_exprs(
  elems : @list.List[@syntax.InterpElem],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for elem in elems {
    match elem {
      Expr(expr~, ..) => collect_scoped_exprs_with_shadow(expr, shadowed, exprs)
      Literal(..) | Source(_) => ()
    }
  }
}

///|
fn collect_scoped_multiline_string_elem_exprs(
  elems : @list.List[@syntax.MultilineStringElem],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for elem in elems {
    match elem {
      Interp(elems) => collect_scoped_interp_elem_exprs(elems, shadowed, exprs)
      String(_) => ()
    }
  }
}

///|
fn collect_scoped_lex_case_exprs(
  cases : @list.List[@syntax.LexCase],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for case in cases {
    collect_scoped_lex_top_pattern_exprs(case.pat, shadowed, exprs)
    let case_shadowed = shadowed_with_lex_top_patterns(shadowed, case.pat)
    collect_scoped_optional_expr(case.guard_, case_shadowed, exprs)
    collect_scoped_exprs_with_shadow(case.body, case_shadowed, exprs)
  }
}

///|
fn collect_scoped_lex_top_pattern_exprs(
  patterns : @list.List[@syntax.LexTopPattern],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for pattern in patterns {
    match pattern {
      Pattern(pattern) =>
        collect_scoped_lex_pattern_exprs(pattern, shadowed, exprs)
      Binder(_) | Wildcard(..) => ()
    }
  }
}

///|
fn collect_scoped_lex_pattern_exprs(
  pattern : @syntax.LexPattern,
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  match pattern {
    Alias(pat~, ..) => collect_scoped_lex_pattern_exprs(pat, shadowed, exprs)
    RegexInterp(elems~, ..) =>
      collect_scoped_interp_elem_exprs(elems, shadowed, exprs)
    Sequence(pats~, ..) =>
      for pat in pats {
        collect_scoped_lex_pattern_exprs(pat, shadowed, exprs)
      }
    ConstantRef(..) | Regex(..) => ()
  }
}

///|
fn collect_scoped_list_comprehension_kind_exprs(
  kind : @syntax.ListComprehensionKind,
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Array[String] {
  match kind {
    For(binders~, condition~, continue_block~, ..) => {
      collect_scoped_binder_expr_pairs(binders, shadowed, exprs)
      let loop_shadowed = shadowed_with_binder_expr_pair_binders(
        shadowed, binders,
      )
      collect_scoped_optional_expr(condition, loop_shadowed, exprs)
      collect_scoped_binder_expr_pairs(continue_block, loop_shadowed, exprs)
      loop_shadowed
    }
    Foreach(binders~, expr=iter, init~, continue_block~) => {
      collect_scoped_exprs_with_shadow(iter, shadowed, exprs)
      collect_scoped_binder_expr_pairs(init, shadowed, exprs)
      let loop_shadowed = shadowed_with_optional_binders(shadowed, binders)
      add_binder_expr_pair_names(loop_shadowed, init)
      collect_scoped_binder_expr_pairs(continue_block, loop_shadowed, exprs)
      loop_shadowed
    }
  }
}

///|
fn collect_scoped_field_def_exprs(
  fields : @list.List[@syntax.FieldDef],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for field in fields {
    collect_scoped_exprs_with_shadow(field.expr, shadowed, exprs)
  }
}

///|
fn collect_scoped_case_exprs(
  cases : @list.List[@syntax.Case],
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  for case in cases {
    let case_shadowed = shadowed_with_pattern(shadowed, case.pattern)
    collect_scoped_optional_expr(case.guard_, case_shadowed, exprs)
    collect_scoped_exprs_with_shadow(case.body, case_shadowed, exprs)
  }
}

///|
fn collect_scoped_func_exprs(
  func : @syntax.Func,
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  let body_shadowed = shadowed_with_parameters(shadowed, func.parameters)
  collect_scoped_exprs_with_shadow(func.body, body_shadowed, exprs)
}

///|
fn collect_scoped_regex_pattern_exprs(
  pattern : @syntax.RegexPattern,
  shadowed : Array[String],
  exprs : Array[ScopedExpr],
) -> Unit {
  match pattern {
    Alias(pat~, ..) => collect_scoped_regex_pattern_exprs(pat, shadowed, exprs)
    Alternation(pat1~, pat2~, ..) | Sequence(pat1~, pat2~, ..) => {
      collect_scoped_regex_pattern_exprs(pat1, shadowed, exprs)
      collect_scoped_regex_pattern_exprs(pat2, shadowed, exprs)
    }
    Literal(..) | Reference(..) => ()
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
fn add_binder_name(names : Array[String], binder : @syntax.Binder) -> Unit {
  if @id.normalize_identifier_name_from_binder(binder) is Some(name) {
    add_unique_name(names, name)
  }
}

///|
fn shadowed_with_binder(
  shadowed : Array[String],
  binder : @syntax.Binder,
) -> Array[String] {
  let next = copy_names(shadowed)
  add_binder_name(next, binder)
  next
}

///|
fn shadowed_with_pattern(
  shadowed : Array[String],
  pattern : @syntax.Pattern,
) -> Array[String] {
  let next = copy_names(shadowed)
  add_pattern_names(next, pattern)
  next
}

///|
fn shadowed_with_parameters(
  shadowed : Array[String],
  parameters : @list.List[@syntax.Parameter],
) -> Array[String] {
  let next = copy_names(shadowed)
  for parameter in parameters {
    add_parameter_name(next, parameter)
  }
  next
}

///|
fn shadowed_with_binder_expr_pair_binders(
  shadowed : Array[String],
  pairs : @list.List[(@syntax.Binder, @syntax.Expr)],
) -> Array[String] {
  let next = copy_names(shadowed)
  add_binder_expr_pair_names(next, pairs)
  next
}

///|
fn shadowed_with_optional_binders(
  shadowed : Array[String],
  binders : @list.List[@syntax.Binder?],
) -> Array[String] {
  let next = copy_names(shadowed)
  for binder in binders {
    if binder is Some(binder) {
      add_binder_name(next, binder)
    }
  }
  next
}

///|
fn shadowed_with_let_and_binders(
  shadowed : Array[String],
  bindings : @list.List[(@syntax.Binder, @syntax.Type?, @syntax.Func)],
) -> Array[String] {
  let next = copy_names(shadowed)
  for binding in bindings {
    let (binder, _ty, _func) = binding
    add_binder_name(next, binder)
  }
  next
}

///|
fn shadowed_with_lex_top_patterns(
  shadowed : Array[String],
  patterns : @list.List[@syntax.LexTopPattern],
) -> Array[String] {
  let next = copy_names(shadowed)
  for pattern in patterns {
    add_lex_top_pattern_names(next, pattern)
  }
  next
}

///|
fn add_binder_expr_pair_names(
  names : Array[String],
  pairs : @list.List[(@syntax.Binder, @syntax.Expr)],
) -> Unit {
  for pair in pairs {
    let (binder, _expr) = pair
    add_binder_name(names, binder)
  }
}

///|
fn add_parameter_name(
  names : Array[String],
  parameter : @syntax.Parameter,
) -> Unit {
  match parameter {
    DiscardPositional(..) => ()
    Labelled(binder~, ..)
    | Optional(binder~, ..)
    | Positional(binder~, ..)
    | QuestionOptional(binder~, ..) => add_binder_name(names, binder)
  }
}

///|
fn add_pattern_names(names : Array[String], pattern : @syntax.Pattern) -> Unit {
  match pattern {
    Var(binder) => add_binder_name(names, binder)
    Alias(pat~, alias_~, ..) => {
      add_pattern_names(names, pat)
      add_binder_name(names, alias_)
    }
    Array(pats~, ..) => add_array_pattern_names(names, pats)
    Constr(args=Some(args), ..) =>
      for arg in args {
        add_pattern_names(names, arg.pat)
      }
    Constr(args=None, ..) => ()
    Constraint(pat~, ..) => add_pattern_names(names, pat)
    Map(elems~, ..) =>
      for elem in elems {
        add_pattern_names(names, elem.pat)
      }
    Or(pat1~, pat2~, ..) | Range(lhs=pat1, rhs=pat2, ..) => {
      add_pattern_names(names, pat1)
      add_pattern_names(names, pat2)
    }
    Record(fields~, ..) =>
      for field in fields {
        add_pattern_names(names, field.pattern)
      }
    SpecialConstr(binder~, args~, ..) => {
      add_binder_name(names, binder)
      for arg in args {
        add_pattern_names(names, arg.pat)
      }
    }
    Tuple(pats~, ..) =>
      for pat in pats {
        add_pattern_names(names, pat)
      }
    Any(..) | Constant(..) => ()
  }
}

///|
fn add_array_pattern_names(
  names : Array[String],
  patterns : @syntax.ArrayPatterns,
) -> Unit {
  match patterns {
    Closed(items) =>
      for item in items {
        add_array_pattern_item_names(names, item)
      }
    Open(prefix, suffix, rest) => {
      for item in prefix {
        add_array_pattern_item_names(names, item)
      }
      for item in suffix {
        add_array_pattern_item_names(names, item)
      }
      add_dot_dot_binder_name(names, rest)
    }
  }
}

///|
fn add_array_pattern_item_names(
  names : Array[String],
  pattern : @syntax.ArrayPattern,
) -> Unit {
  match pattern {
    Pattern(pattern) => add_pattern_names(names, pattern)
    ConstSpread(binder~, ..) => add_binder_name(names, binder)
    BytesSpread(..) | StringSpread(..) => ()
  }
}

///|
fn add_dot_dot_binder_name(
  names : Array[String],
  binder : @syntax.DotDotBinder,
) -> Unit {
  match binder {
    Binder(binder) | BinderAs(binder) => add_binder_name(names, binder)
    NoBinder | Underscore => ()
  }
}

///|
fn add_lex_top_pattern_names(
  names : Array[String],
  pattern : @syntax.LexTopPattern,
) -> Unit {
  match pattern {
    Binder(binder) => add_binder_name(names, binder)
    Pattern(pattern) => add_lex_pattern_names(names, pattern)
    Wildcard(..) => ()
  }
}

///|
fn add_lex_pattern_names(
  names : Array[String],
  pattern : @syntax.LexPattern,
) -> Unit {
  match pattern {
    Alias(pat~, binder~, ..) => {
      add_lex_pattern_names(names, pat)
      add_binder_name(names, binder)
    }
    Sequence(pats~, ..) =>
      for pat in pats {
        add_lex_pattern_names(names, pat)
      }
    ConstantRef(..) | Regex(..) | RegexInterp(..) => ()
  }
}

///|
pub fn collect_exprs(expr : @syntax.Expr, exprs : Array[@syntax.Expr]) -> Unit {
  exprs.push(expr)
  match expr {
    Apply(func~, args~, ..) => {
      collect_exprs(func, exprs)
      collect_argument_exprs(args, exprs)
    }
    DotApply(self~, args~, ..) => {
      collect_exprs(self, exprs)
      collect_argument_exprs(args, exprs)
    }
    Field(record~, ..) => collect_exprs(record, exprs)
    Infix(lhs~, rhs~, ..) => {
      collect_exprs(lhs, exprs)
      collect_exprs(rhs, exprs)
    }
    Unary(expr~, ..) => collect_exprs(expr, exprs)
    Assign(expr~, ..) => collect_exprs(expr, exprs)
    Array(exprs=items, ..) | Tuple(exprs=items, ..) =>
      collect_expr_list(items, exprs)
    Sequence(exprs=items, last_expr~, ..) => {
      collect_expr_list(items, exprs)
      collect_exprs(last_expr, exprs)
    }
    ArrayGet(array~, index~, ..) => {
      collect_exprs(array, exprs)
      collect_exprs(index, exprs)
    }
    ArraySet(array~, index~, value~, ..)
    | ArrayAugmentedSet(array~, index~, value~, ..) => {
      collect_exprs(array, exprs)
      collect_exprs(index, exprs)
      collect_exprs(value, exprs)
    }
    ArraySpread(elems~, ..) => collect_spreadable_elem_exprs(elems, exprs)
    ArrayGetSlice(array~, start_index~, end_index~, ..) => {
      collect_exprs(array, exprs)
      collect_optional_expr(start_index, exprs)
      collect_optional_expr(end_index, exprs)
    }
    Group(expr~, ..) | Constraint(expr~, ..) | As(expr~, ..) =>
      collect_exprs(expr, exprs)
    If(cond~, ifso~, ifnot~, ..) => {
      collect_exprs(cond, exprs)
      collect_exprs(ifso, exprs)
      collect_optional_expr(ifnot, exprs)
    }
    Guard(cond~, otherwise~, body~, ..) => {
      collect_exprs(cond, exprs)
      collect_optional_expr(otherwise, exprs)
      collect_exprs(body, exprs)
    }
    Let(expr~, body~, ..) | LetMut(expr~, body~, ..) => {
      collect_exprs(expr, exprs)
      collect_exprs(body, exprs)
    }
    For(
      binders~,
      condition~,
      continue_block~,
      body~,
      for_else~,
      where_clause~,
      ..
    ) => {
      collect_binder_expr_pairs(binders, exprs)
      collect_optional_expr(condition, exprs)
      collect_binder_expr_pairs(continue_block, exprs)
      collect_exprs(body, exprs)
      collect_optional_expr(for_else, exprs)
      collect_optional_where_clause_exprs(where_clause, exprs)
    }
    ForEach(
      expr~,
      init~,
      continue_block~,
      body~,
      else_block~,
      where_clause~,
      ..
    ) => {
      collect_exprs(expr, exprs)
      collect_binder_expr_pairs(init, exprs)
      collect_binder_expr_pairs(continue_block, exprs)
      collect_exprs(body, exprs)
      collect_optional_expr(else_block, exprs)
      collect_optional_where_clause_exprs(where_clause, exprs)
    }
    Return(return_value~, ..) => collect_optional_expr(return_value, exprs)
    Raise(err_value~, ..) => collect_exprs(err_value, exprs)
    Pipe(lhs~, rhs~, ..) | RevPipe(lhs~, rhs~, ..) | Implies(lhs~, rhs~, ..) => {
      collect_exprs(lhs, exprs)
      collect_exprs(rhs, exprs)
    }
    Interp(elems~, ..) => collect_interp_elem_exprs(elems, exprs)
    Record(fields~, ..) => collect_field_def_exprs(fields, exprs)
    RecordUpdate(record~, fields~, ..) => {
      collect_exprs(record, exprs)
      collect_field_def_exprs(fields, exprs)
    }
    Mutate(record~, field~, ..) => {
      collect_exprs(record, exprs)
      collect_exprs(field, exprs)
    }
    Match(expr~, cases~, ..) => {
      collect_exprs(expr, exprs)
      collect_case_exprs(cases, exprs)
    }
    Is(expr~, ..) => collect_exprs(expr, exprs)
    IsLexMatch(expr~, pat~, ..) => {
      collect_exprs(expr, exprs)
      collect_lex_top_pattern_exprs(pat, exprs)
    }
    LexMatch(expr~, cases~, ..) => {
      collect_exprs(expr, exprs)
      collect_lex_case_exprs(cases, exprs)
    }
    ListComprehension(kind~, guard_~, body~, ..) => {
      collect_list_comprehension_kind_exprs(kind, exprs)
      collect_optional_expr(guard_, exprs)
      collect_exprs(body, exprs)
    }
    Try(body~, catch_~, try_else~, ..) => {
      collect_exprs(body, exprs)
      collect_case_exprs(catch_, exprs)
      if try_else is Some(cases) {
        collect_case_exprs(cases, exprs)
      }
    }
    TryOperator(body~, ..) => collect_exprs(body, exprs)
    While(loop_cond~, loop_body~, while_else~, ..) => {
      collect_exprs(loop_cond, exprs)
      collect_exprs(loop_body, exprs)
      collect_optional_expr(while_else, exprs)
    }
    Break(arg~, ..) => collect_optional_expr(arg, exprs)
    Continue(args~, ..) => collect_expr_list(args, exprs)
    Defer(expr~, body~, ..) => {
      collect_exprs(expr, exprs)
      collect_exprs(body, exprs)
    }
    ProofAssert(expr~, ..) => collect_exprs(expr, exprs)
    ProofLet(expr~, ..) => collect_exprs(expr, exprs)
    Quantifier(body~, ..) => collect_exprs(body, exprs)
    RegexMatch(expr~, ..) => collect_exprs(expr, exprs)
    StaticAssert(body~, ..) => collect_exprs(body, exprs)
    TemplateWriting(expr~, template~, ..) => {
      collect_exprs(expr, exprs)
      collect_exprs(template, exprs)
    }
    Function(func~, ..) => collect_exprs(func.body, exprs)
    LetFn(func~, body~, ..) => {
      collect_exprs(func.body, exprs)
      collect_exprs(body, exprs)
    }
    LetAnd(bindings~, body~, ..) => {
      for binding in bindings {
        let (_binder, _ty, func) = binding
        collect_exprs(func.body, exprs)
      }
      collect_exprs(body, exprs)
    }
    Map(elems~, ..) =>
      for elem in elems {
        collect_exprs(elem.expr, exprs)
      }
    MultilineString(elems~, ..) =>
      collect_multiline_string_elem_exprs(elems, exprs)
    _ => ()
  }
}

///|
fn collect_argument_exprs(
  args : @list.List[@syntax.Argument],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for arg in args {
    collect_exprs(arg.value, exprs)
  }
}

///|
fn collect_expr_list(
  list : @list.List[@syntax.Expr],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for expr in list {
    collect_exprs(expr, exprs)
  }
}

///|
fn collect_spreadable_elem_exprs(
  elems : @list.List[@syntax.SpreadableElem],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for elem in elems {
    match elem {
      Regular(expr) | Spread(expr~, ..) => collect_exprs(expr, exprs)
    }
  }
}

///|
fn collect_optional_expr(
  expr : @syntax.Expr?,
  exprs : Array[@syntax.Expr],
) -> Unit {
  if expr is Some(expr) {
    collect_exprs(expr, exprs)
  }
}

///|
fn collect_optional_where_clause_exprs(
  clause : @syntax.WhereClause?,
  exprs : Array[@syntax.Expr],
) -> Unit {
  if clause is Some(clause) {
    collect_field_def_exprs(clause.fields, exprs)
  }
}

///|
fn collect_binder_expr_pairs(
  pairs : @list.List[(@syntax.Binder, @syntax.Expr)],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for pair in pairs {
    let (_binder, expr) = pair
    collect_exprs(expr, exprs)
  }
}

///|
fn collect_interp_elem_exprs(
  elems : @list.List[@syntax.InterpElem],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for elem in elems {
    match elem {
      Expr(expr~, ..) => collect_exprs(expr, exprs)
      Literal(..) | Source(_) => ()
    }
  }
}

///|
fn collect_multiline_string_elem_exprs(
  elems : @list.List[@syntax.MultilineStringElem],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for elem in elems {
    match elem {
      Interp(elems) => collect_interp_elem_exprs(elems, exprs)
      String(_) => ()
    }
  }
}

///|
fn collect_lex_case_exprs(
  cases : @list.List[@syntax.LexCase],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for case in cases {
    collect_lex_top_pattern_exprs(case.pat, exprs)
    collect_optional_expr(case.guard_, exprs)
    collect_exprs(case.body, exprs)
  }
}

///|
fn collect_lex_top_pattern_exprs(
  patterns : @list.List[@syntax.LexTopPattern],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for pattern in patterns {
    match pattern {
      Pattern(pattern) => collect_lex_pattern_exprs(pattern, exprs)
      Binder(_) | Wildcard(..) => ()
    }
  }
}

///|
fn collect_lex_pattern_exprs(
  pattern : @syntax.LexPattern,
  exprs : Array[@syntax.Expr],
) -> Unit {
  match pattern {
    Alias(pat~, ..) => collect_lex_pattern_exprs(pat, exprs)
    RegexInterp(elems~, ..) => collect_interp_elem_exprs(elems, exprs)
    Sequence(pats~, ..) =>
      for pat in pats {
        collect_lex_pattern_exprs(pat, exprs)
      }
    ConstantRef(..) | Regex(..) => ()
  }
}

///|
fn collect_list_comprehension_kind_exprs(
  kind : @syntax.ListComprehensionKind,
  exprs : Array[@syntax.Expr],
) -> Unit {
  match kind {
    For(binders~, condition~, continue_block~, ..) => {
      collect_binder_expr_pairs(binders, exprs)
      collect_optional_expr(condition, exprs)
      collect_binder_expr_pairs(continue_block, exprs)
    }
    Foreach(expr~, init~, continue_block~, ..) => {
      collect_exprs(expr, exprs)
      collect_binder_expr_pairs(init, exprs)
      collect_binder_expr_pairs(continue_block, exprs)
    }
  }
}

///|
fn collect_field_def_exprs(
  fields : @list.List[@syntax.FieldDef],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for field in fields {
    collect_exprs(field.expr, exprs)
  }
}

///|
fn collect_case_exprs(
  cases : @list.List[@syntax.Case],
  exprs : Array[@syntax.Expr],
) -> Unit {
  for case in cases {
    collect_optional_expr(case.guard_, exprs)
    collect_exprs(case.body, exprs)
  }
}
