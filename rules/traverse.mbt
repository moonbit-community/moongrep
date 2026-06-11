///|
fn count_supported_name_in_expr(expr : @syntax.Expr, name : String) -> Int {
  match @ident.normalize_identifier_name_from_expr(expr) {
    Some(found) => if found == name { 1 } else { 0 }
    None => count_supported_name_in_expr_children(expr, name)
  }
}

///|
fn count_supported_name_in_expr_children(expr : @syntax.Expr, name : String) -> Int {
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
    Array(exprs~, ..) | Tuple(exprs~, ..) =>
      count_supported_name_in_expr_list(exprs, name)
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
    Let(pattern~, expr~, body~, ..) =>
      count_supported_name_in_pattern(pattern, name) +
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_expr(body, name)
    LetMut(binder~, expr~, body~, ..) =>
      count_supported_name_in_binder(binder, name) +
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_expr(body, name)
    For(binders~, condition~, continue_block~, body~, for_else~, label~, ..) =>
      count_supported_name_in_binder_expr_pairs(binders, name) +
      count_supported_name_in_optional_expr(condition, name) +
      count_supported_name_in_binder_expr_pairs(continue_block, name) +
      count_supported_name_in_expr(body, name) +
      count_supported_name_in_optional_expr(for_else, name) +
      count_supported_name_in_optional_label(label, name)
    ForEach(binders~, expr~, body~, else_block~, label~, ..) =>
      count_supported_name_in_optional_binders(binders, name) +
      count_supported_name_in_expr(expr, name) +
      count_supported_name_in_expr(body, name) +
      count_supported_name_in_optional_expr(else_block, name) +
      count_supported_name_in_optional_label(label, name)
    Return(return_value~, ..) => count_supported_name_in_optional_expr(return_value, name)
    Raise(err_value~, ..) => count_supported_name_in_expr(err_value, name)
    Pipe(lhs~, rhs~, ..) => count_supported_name_in_expr(lhs, name) + count_supported_name_in_expr(rhs, name)
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
    Function(func~, ..) => count_supported_name_in_func(func, name)
    LetFn(name=binder, func~, body~, ..) =>
      count_supported_name_in_binder(binder, name) +
      count_supported_name_in_func(func, name) +
      count_supported_name_in_expr(body, name)
    LetAnd(bindings~, body~, ..) =>
      count_supported_name_in_let_and_bindings(bindings, name) +
      count_supported_name_in_expr(body, name)
    Map(elems~, ..) => count_supported_name_in_map_expr_elems(elems, name)
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
fn count_supported_name_in_argument_kind(kind : @syntax.ArgumentKind, name : String) -> Int {
  match kind {
    Positional => 0
    Labelled(label) | LabelledPun(label) => count_supported_name_in_label(label, name)
    LabelledOption(label~, ..) | LabelledOptionPun(label~, ..) =>
      count_supported_name_in_label(label, name)
  }
}

///|
fn count_supported_name_in_accessor(accessor : @syntax.Accessor, name : String) -> Int {
  match accessor {
    Label(label) => count_supported_name_in_label(label, name)
    _ => 0
  }
}

///|
fn count_supported_name_in_var(v : @syntax.Var, name : String) -> Int {
  match @ident.normalize_identifier_name_from_var(v) {
    Some(found) => if found == name { 1 } else { 0 }
    None => 0
  }
}

///|
fn count_supported_name_in_optional_var(v : @syntax.Var?, name : String) -> Int {
  match v {
    Some(v) => count_supported_name_in_var(v, name)
    None => 0
  }
}

///|
fn count_supported_name_in_binder(binder : @syntax.Binder, name : String) -> Int {
  match @ident.normalize_identifier_name_from_binder(binder) {
    Some(found) => if found == name { 1 } else { 0 }
    None => 0
  }
}

///|
fn count_supported_name_in_label(label : @syntax.Label, name : String) -> Int {
  match @ident.normalize_identifier_name_from_label(label) {
    Some(found) => if found == name { 1 } else { 0 }
    None => 0
  }
}

///|
fn count_supported_name_in_optional_label(label : @syntax.Label?, name : String) -> Int {
  match label {
    Some(label) => count_supported_name_in_label(label, name)
    None => 0
  }
}

///|
fn count_supported_name_in_pattern(pattern : @syntax.Pattern, name : String) -> Int {
  match @ident.normalize_identifier_name_from_pattern(pattern) {
    Some(found) => if found == name { 1 } else { 0 }
    None =>
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
fn count_supported_name_in_expr_list(exprs : @list.List[@syntax.Expr], name : String) -> Int {
  let mut total = 0
  for expr in exprs {
    total += count_supported_name_in_expr(expr, name)
  }
  total
}

///|
fn count_supported_name_in_optional_expr(expr : @syntax.Expr?, name : String) -> Int {
  match expr {
    Some(expr) => count_supported_name_in_expr(expr, name)
    None => 0
  }
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
    match binder {
      Some(binder) => total += count_supported_name_in_binder(binder, name)
      None => ()
    }
  }
  total
}

///|
fn count_supported_name_in_patterns(patterns : @list.List[@syntax.Pattern], name : String) -> Int {
  let mut total = 0
  for pattern in patterns {
    total += count_supported_name_in_pattern(pattern, name)
  }
  total
}

///|
fn count_supported_name_in_cases(cases : @list.List[@syntax.Case], name : String) -> Int {
  let mut total = 0
  for case in cases {
    total += count_supported_name_in_pattern(case.pattern, name)
    total += count_supported_name_in_optional_expr(case.guard_, name)
    total += count_supported_name_in_expr(case.body, name)
  }
  total
}

///|
fn count_supported_name_in_optional_cases(cases : @list.List[@syntax.Case]?, name : String) -> Int {
  match cases {
    Some(cases) => count_supported_name_in_cases(cases, name)
    None => 0
  }
}

///|
fn count_supported_name_in_field_defs(fields : @list.List[@syntax.FieldDef], name : String) -> Int {
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
fn count_supported_name_in_parameter(param : @syntax.Parameter, name : String) -> Int {
  match param {
    DiscardPositional(..) => 0
    Labelled(binder~, ..) |
    Optional(binder~, ..) |
    Positional(binder~, ..) |
    QuestionOptional(binder~, ..) => count_supported_name_in_binder(binder, name)
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
fn traverse_impl_exprs(nodes : @list.List[@syntax.Impl]) -> Array[@syntax.Expr] {
  let exprs : Array[@syntax.Expr] = []
  for node in nodes {
    collect_impl_exprs(node, exprs)
  }
  exprs
}

///|
fn collect_impl_exprs(node : @syntax.Impl, exprs : Array[@syntax.Expr]) -> Unit {
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
fn collect_exprs(expr : @syntax.Expr, exprs : Array[@syntax.Expr]) -> Unit {
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
    ArraySet(array~, index~, value~, ..) => {
      collect_exprs(array, exprs)
      collect_exprs(index, exprs)
      collect_exprs(value, exprs)
    }
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
    Let(expr~, body~, ..) | LetMut(expr~, body~, ..) => {
      collect_exprs(expr, exprs)
      collect_exprs(body, exprs)
    }
    For(binders~, condition~, continue_block~, body~, for_else~, ..) => {
      collect_binder_expr_pairs(binders, exprs)
      collect_optional_expr(condition, exprs)
      collect_binder_expr_pairs(continue_block, exprs)
      collect_exprs(body, exprs)
      collect_optional_expr(for_else, exprs)
    }
    ForEach(expr~, body~, else_block~, ..) => {
      collect_exprs(expr, exprs)
      collect_exprs(body, exprs)
      collect_optional_expr(else_block, exprs)
    }
    Return(return_value~, ..) => collect_optional_expr(return_value, exprs)
    Raise(err_value~, ..) => collect_exprs(err_value, exprs)
    Pipe(lhs~, rhs~, ..) => {
      collect_exprs(lhs, exprs)
      collect_exprs(rhs, exprs)
    }
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
    Try(body~, catch_~, try_else~, ..) => {
      collect_exprs(body, exprs)
      collect_case_exprs(catch_, exprs)
      match try_else {
        Some(cases) => collect_case_exprs(cases, exprs)
        None => ()
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
    Map(elems~, ..) => {
      for elem in elems {
        collect_exprs(elem.expr, exprs)
      }
    }
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
fn collect_optional_expr(expr : @syntax.Expr?, exprs : Array[@syntax.Expr]) -> Unit {
  match expr {
    Some(expr) => collect_exprs(expr, exprs)
    None => ()
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
