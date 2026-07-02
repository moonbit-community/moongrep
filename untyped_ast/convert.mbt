///|
fn node(
  kind : String,
  loc : @basic.Location,
  children : Array[(String, Value)],
) -> Node {
  { kind, loc, children: AstFields(FixedArray::from_array(children)) }
}

///|
fn node0(kind : String, loc : @basic.Location) -> Node {
  node(kind, loc, [])
}

///|
fn node1(kind : String, loc : @basic.Location, value : Value) -> Node {
  node(kind, loc, [("value", value)])
}

///|
fn node_value(n : Node) -> Value {
  AstNode(n)
}

///|
fn string_value(s : String) -> Value {
  AstString(s)
}

///|
fn bool_value(b : Bool) -> Value {
  AstBool(b)
}

///|
fn number_value(n : Double) -> Value {
  AstNumber(n, repr=None)
}

///|
fn[T] option_value(opt : T?, f : (T) -> Value) -> Value {
  if opt is Some(value) {
    f(value)
  } else {
    AstNull
  }
}

///|
fn[T] list_children(list : @list.List[T], f : (T) -> Value) -> NodeChildren {
  let values : Array[Value] = []
  list.each(fn(item) { values.push(f(item)) })
  AstItems(FixedArray::from_array(values))
}

///|
fn[T] list_node(
  kind : String,
  loc : @basic.Location,
  list : @list.List[T],
  f : (T) -> Value,
) -> Node {
  { kind, loc, children: list_children(list, f) }
}

///|
fn empty_list_node(kind : String, loc : @basic.Location) -> Node {
  { kind, loc, children: AstItems([]) }
}

///|
fn doc_string_value(doc : @syntax.DocString) -> Value {
  let mut docs = doc.content
  match docs {
    @list.Empty => AstString("")
    @list.More(head, tail~) => {
      docs = tail
      let buf = StringBuilder::new()
      buf.write_string(head)
      for item in docs {
        buf.write_string("\n")
        buf.write_string(item)
      } nobreak {
        AstString(buf.to_string())
      }
    }
  }
}

///|
fn string_literal_value(s : String) -> Value {
  string_value(s)
}

///|
fn char_literal_value(c : String) -> Value {
  string_value(c)
}

///|
fn byte_literal_value(b : String) -> Value {
  string_value(b)
}

///|
fn bytes_literal_value(b : String) -> Value {
  string_value(b)
}

///|
fn long_ident_node(item : @syntax.LongIdent, loc : @basic.Location) -> Node {
  match item {
    Ident(name~) => node1("LongIdent::Ident", loc, string_value(name))
    Dot(pkg~, id~) =>
      node("LongIdent::Dot", loc, [
        ("pkg", string_value(pkg)),
        ("id", string_value(id)),
      ])
  }
}

///|
fn constr_id_node(item : @syntax.ConstrId) -> Node {
  node("ConstrId", item.loc, [
    ("id", node_value(long_ident_node(item.id, item.loc))),
  ])
}

///|
fn func_stubs_node(item : @syntax.FuncStubs, loc : @basic.Location) -> Node {
  match item {
    Import(module_name~, func_name~, language~) =>
      node("FuncStubs::Import", loc, [
        ("module_name", string_literal_value(module_name)),
        ("func_name", string_literal_value(func_name)),
        ("language", option_value(language, string_literal_value)),
      ])
    Embedded(language~, code~) =>
      node("FuncStubs::Embedded", loc, [
        ("language", option_value(language, string_literal_value)),
        ("code", node_value(embedded_code_node(code, loc))),
      ])
  }
}

///|
fn embedded_code_node(
  item : @syntax.EmbeddedCode,
  loc : @basic.Location,
) -> Node {
  match item {
    CodeString(s) =>
      node1("EmbeddedCode::CodeString", loc, string_literal_value(s))
    CodeMultilineString(strings) =>
      node1(
        "EmbeddedCode::CodeMultilineString",
        loc,
        node_value(
          list_node(
            "EmbeddedCode::CodeMultilineString::LiteralList", loc, strings, string_value,
          ),
        ),
      )
  }
}

///|
fn trait_method_decl_node(item : @syntax.TraitMethodDecl) -> Node {
  node("TraitMethodDecl", item.loc, [
    ("name", node_value(binder_node(item.name))),
    ("has_error", AstNull),
    ("is_async", option_value(item.is_async, async_value)),
    (
      "quantifiers",
      node_value(
        list_node(
          "TraitMethodDecl::QuantifierList",
          item.loc,
          item.quantifiers,
          type_var_binder_value,
        ),
      ),
    ),
    (
      "params",
      node_value(
        list_node(
          "TraitMethodDecl::ParamList",
          item.loc,
          item.params,
          parameter_value,
        ),
      ),
    ),
    ("return_type", option_value(item.return_type, type_value)),
    ("error_type", node_value(error_type_node(item.error_type, item.loc))),
    (
      "has_default",
      option_value(item.has_default, fn(loc) {
        node_value(node0("TraitMethodDecl::HasDefault", loc))
      }),
    ),
    (
      "attrs",
      node_value(
        list_node(
          "TraitMethodDecl::AttrList",
          item.loc,
          item.attrs,
          attribute_value,
        ),
      ),
    ),
  ])
}

///|
fn type_var_constraint_node(item : @syntax.TypeVarConstraint) -> Node {
  node("TypeVarConstraint", item.loc, [
    ("trait", node_value(long_ident_node(item.trait_, item.loc))),
  ])
}

///|
fn type_decl_binder_node(item : @syntax.TypeDeclBinder) -> Node {
  node("TypeDeclBinder", item.loc, [
    ("name", option_value(item.name, string_value)),
  ])
}

///|
fn[T] list_loc_or(
  list : @list.List[T],
  default : @basic.Location,
  loc_of : (T) -> @basic.Location,
) -> @basic.Location {
  match list {
    @list.Empty => default
    @list.More(item, tail=@list.Empty) => loc_of(item)
    @list.More(first, tail~) =>
      loc_of(first).merge(loc_of(tail.last().unwrap()))
  }
}

///|
fn type_desc_node(item : @syntax.TypeDesc, loc : @basic.Location) -> Node {
  match item {
    Abstract => node0("TypeDesc::Abstract", loc)
    ExtensibleEnum(constrs) => {
      let constrs_loc = list_loc_or(constrs, loc, fn(constr) { constr.loc })
      node1(
        "TypeDesc::ExtensibleEnum",
        constrs_loc,
        node_value(
          list_node(
            "TypeDesc::ExtensibleEnum::ConstrList", constrs_loc, constrs, constr_decl_value,
          ),
        ),
      )
    }
    Error(exception_decl) =>
      node1(
        "TypeDesc::Error",
        loc,
        node_value(exception_decl_node(exception_decl, loc)),
      )
    Variant(constrs) => {
      let constrs_loc = list_loc_or(constrs, loc, fn(constr) { constr.loc })
      node1(
        "TypeDesc::Variant",
        constrs_loc,
        node_value(
          list_node(
            "TypeDesc::Variant::ConstrList", constrs_loc, constrs, constr_decl_value,
          ),
        ),
      )
    }
    ExtendEnum(target~, constructors~) => {
      let constrs_loc = list_loc_or(constructors, loc, fn(constr) { constr.loc })
      node("TypeDesc::ExtendEnum", loc, [
        ("target", node_value(type_name_node(target))),
        (
          "constructors",
          node_value(
            list_node(
              "TypeDesc::ExtendEnum::ConstrList", constrs_loc, constructors, constr_decl_value,
            ),
          ),
        ),
      ])
    }
    Record(fields~, constr_decl~) => {
      let children : Array[(String, Value)] = [
        (
          "value",
          node_value(
            list_node(
              "TypeDesc::Record::FieldList", loc, fields, field_decl_value,
            ),
          ),
        ),
      ]
      if constr_decl is Some(decl) {
        children.push(("constr_decl", node_value(fun_decl_node(decl))))
      }
      node("TypeDesc::Record", loc, children)
    }
    TupleStruct(tys) => {
      let tys_loc = list_loc_or(tys, loc, fn(ty) { ty.loc() })
      node1(
        "TypeDesc::TupleStruct",
        tys_loc,
        node_value(
          list_node("TypeDesc::TupleStruct::TypeList", tys_loc, tys, type_value),
        ),
      )
    }
    Alias(ty) => node1("TypeDesc::Alias", ty.loc(), type_value(ty))
  }
}

///|
fn deriving_directive_node(item : @syntax.DerivingDirective) -> Node {
  node("DerivingDirective", item.loc, [
    ("type_name", node_value(type_name_node(item.type_name))),
    (
      "args",
      node_value(
        list_node(
          "DerivingDirective::ArgList",
          item.loc,
          item.args,
          argument_value,
        ),
      ),
    ),
  ])
}

///|
fn exception_decl_node(
  item : @syntax.ExceptionDecl,
  loc : @basic.Location,
) -> Node {
  match item {
    NoPayload => node0("ExceptionDecl::NoPayload", loc)
    EnumPayload(constrs) =>
      node1(
        "ExceptionDecl::EnumPayload",
        loc,
        node_value(
          list_node(
            "ExceptionDecl::EnumPayload::ConstrList", loc, constrs, constr_decl_value,
          ),
        ),
      )
  }
}

///|
fn constr_decl_node(item : @syntax.ConstrDecl) -> Node {
  node("ConstrDecl", item.loc, [
    ("name", node_value(constr_name_node(item.name))),
    (
      "args",
      option_value(item.args, fn(args) {
        node_value(
          list_node("ConstrDecl::ArgList", item.loc, args, constr_param_value),
        )
      }),
    ),
    (
      "tag",
      option_value(item.tag, fn(tag) {
        let (s, l) = tag
        node_value(node1("ConstrDecl::Tag", l, string_value(s)))
      }),
    ),
    (
      "attrs",
      node_value(
        list_node("ConstrDecl::AttrList", item.loc, item.attrs, attribute_value),
      ),
    ),
    ("doc", doc_string_value(item.doc)),
  ])
}

///|
fn constr_name_node(item : @syntax.ConstrName) -> Node {
  node("ConstrName", item.loc, [("name", string_value(item.name))])
}

///|
fn constr_param_node(item : @syntax.ConstrParam) -> Node {
  let loc = if item.label is Some(label) {
    label.loc.merge(item.ty.loc())
  } else {
    item.ty.loc()
  }
  node("ConstrParam", loc, [
    ("ty", type_value(item.ty)),
    ("mut", bool_value(item.mut_)),
    ("label", option_value(item.label, label_value)),
  ])
}

///|
fn field_decl_node(item : @syntax.FieldDecl) -> Node {
  node("FieldDecl", item.loc, [
    ("name", node_value(field_name_node(item.name))),
    ("ty", type_value(item.ty)),
    ("mut", bool_value(item.mut_)),
    ("vis", node_value(visibility_node(item.vis, item.loc))),
    (
      "attrs",
      node_value(
        list_node("FieldDecl::AttrList", item.loc, item.attrs, attribute_value),
      ),
    ),
    ("doc", doc_string_value(item.doc)),
  ])
}

///|
fn field_name_node(item : @syntax.FieldName) -> Node {
  node("FieldName", item.loc, [("label", string_value(item.label))])
}

///|
fn where_clause_node(item : @syntax.WhereClause) -> Node {
  node("WhereClause", item.loc, [
    (
      "fields",
      node_value(
        list_node(
          "WhereClause::FieldList",
          item.loc,
          item.fields,
          field_def_value,
        ),
      ),
    ),
  ])
}

///|
pub fn from_expr(item : @syntax.Expr) -> Node {
  expr_node(item)
}

///|
fn expr_node(item : @syntax.Expr) -> Node {
  match item {
    Apply(func~, args~, loc~) =>
      node("Expr::Apply", loc, [
        ("func", expr_value(func)),
        (
          "args",
          node_value(
            list_node("Expr::Apply::ArgumentList", loc, args, argument_value),
          ),
        ),
        ("attr", node_value(apply_attr_node(loc))),
      ])
    Infix(op~, lhs~, rhs~, loc~) =>
      node("Expr::Infix", loc, [
        ("op", node_value(var_node(op))),
        ("lhs", expr_value(lhs)),
        ("rhs", expr_value(rhs)),
      ])
    Unary(op~, expr~, loc~) =>
      node("Expr::Unary", loc, [
        ("op", node_value(var_node(op))),
        ("expr", expr_value(expr)),
      ])
    Array(exprs~, loc~) =>
      node("Expr::Array", loc, [
        (
          "exprs",
          node_value(list_node("Expr::Array::ExprList", loc, exprs, expr_value)),
        ),
      ])
    ArraySpread(elems~, loc~) =>
      node("Expr::ArraySpread", loc, [
        (
          "elems",
          node_value(
            list_node(
              "Expr::ArraySpread::ElemList", loc, elems, spreadable_elem_value,
            ),
          ),
        ),
      ])
    ListComprehension(kind~, guard_~, body~, loc~) =>
      node("Expr::ListComprehension", loc, [
        ("kind", node_value(list_comprehension_kind_node(kind, loc))),
        ("guard", option_value(guard_, expr_value)),
        ("body", expr_value(body)),
      ])
    ArrayGet(array~, index~, loc~) =>
      node("Expr::ArrayGet", loc, [
        ("array", expr_value(array)),
        ("index", expr_value(index)),
      ])
    ArrayGetSlice(array~, start_index~, end_index~, index_loc~, loc~) => {
      ignore(index_loc)
      node("Expr::ArrayGetSlice", loc, [
        ("array", expr_value(array)),
        ("start_index", option_value(start_index, expr_value)),
        ("end_index", option_value(end_index, expr_value)),
      ])
    }
    ArraySet(array~, index~, value~, loc~) =>
      node("Expr::ArraySet", loc, [
        ("array", expr_value(array)),
        ("index", expr_value(index)),
        ("value", expr_value(value)),
      ])
    ArrayAugmentedSet(op~, array~, index~, value~, loc~) =>
      node("Expr::ArrayAugmentedSet", loc, [
        ("op", node_value(var_node(op))),
        ("array", expr_value(array)),
        ("index", expr_value(index)),
        ("value", expr_value(value)),
      ])
    Constant(c~, loc~) =>
      node("Expr::Constant", loc, [("constant", constant_value(c, loc))])
    MultilineString(elems~, loc~) =>
      node("Expr::MultilineString", loc, [
        (
          "elems",
          node_value(
            list_node("Expr::MultilineString::ElemList", loc, elems, fn(elem) {
              node_value(multiline_string_elem_node(elem, loc))
            }),
          ),
        ),
      ])
    Interp(elems~, loc~) =>
      node("Expr::Interp", loc, [
        (
          "elems",
          node_value(
            list_node("Expr::Interp::ElemList", loc, elems, interp_elem_value),
          ),
        ),
      ])
    Constraint(expr~, ty~, loc~) =>
      node("Expr::Constraint", loc, [
        ("expr", expr_value(expr)),
        ("ty", type_value(ty)),
      ])
    Constr(constr~, loc~) =>
      node("Expr::Constr", loc, [
        ("constr", node_value(constructor_node(constr))),
      ])
    While(loop_cond~, loop_body~, while_else~, label~, loc~) =>
      node("Expr::While", loc, [
        ("loop_cond", expr_value(loop_cond)),
        ("loop_body", expr_value(loop_body)),
        ("while_else", option_value(while_else, expr_value)),
        ("label", option_value(label, label_value)),
      ])
    Function(func~, loc~) =>
      node("Expr::Function", loc, [("func", node_value(func_node(func)))])
    Ident(id~, loc~) =>
      node("Expr::Ident", loc, [("id", node_value(var_node(id)))])
    If(cond~, ifso~, ifnot~, loc~) =>
      node("Expr::If", loc, [
        ("cond", expr_value(cond)),
        ("ifso", expr_value(ifso)),
        ("ifnot", option_value(ifnot, expr_value)),
      ])
    Guard(cond~, otherwise~, body~, loc~) =>
      node("Expr::Guard", loc, [
        ("cond", expr_value(cond)),
        ("otherwise", option_value(otherwise, expr_value)),
        ("body", expr_value(body)),
      ])
    Is(expr~, pat~, loc~) =>
      node("Expr::Is", loc, [
        ("expr", expr_value(expr)),
        ("pat", pattern_value(pat)),
      ])
    IsLexMatch(expr~, strategy~, pat~, pat_loc~, loc~) =>
      node("Expr::IsLexmatch", loc, [
        ("expr", expr_value(expr)),
        ("strategy", option_value(strategy, label_value)),
        (
          "pat",
          node_value(
            list_node("Expr::IsLexmatch::PatternList", pat_loc, pat, fn(p) {
              node_value(lex_top_pattern_node(p, pat_loc))
            }),
          ),
        ),
      ])
    RegexMatch(expr~, pat~, bindings~, loc~) =>
      node("Expr::RegexMatch", loc, [
        ("expr", expr_value(expr)),
        ("pat", node_value(regex_pattern_node(pat))),
        (
          "bindings",
          node_value(
            list_node("Expr::RegexMatch::BindingList", loc, bindings, fn(
              binding,
            ) {
              let (label, binder) = binding
              node_value(
                node("Expr::RegexMatch::Binding", label.loc, [
                  ("label", label_value(label)),
                  ("binder", option_value(binder, binder_value)),
                ]),
              )
            }),
          ),
        ),
      ])
    Defer(expr~, body~, loc~) =>
      node("Expr::Defer", loc, [
        ("expr", expr_value(expr)),
        ("body", expr_value(body)),
      ])
    LetFn(name~, func~, body~, loc~) =>
      node("Expr::LetFn", loc, [
        ("name", binder_value(name)),
        ("func", node_value(func_node(func))),
        ("body", expr_value(body)),
      ])
    LetAnd(bindings~, body~, loc~) =>
      node("Expr::LetAnd", loc, [
        (
          "bindings",
          node_value(
            list_node("Expr::LetAnd::BindingList", loc, bindings, fn(binding) {
              let (binder, ty, func) = binding
              node_value(
                node("LetAnd::Binding", loc, [
                  ("binder", binder_value(binder)),
                  ("type", option_value(ty, type_value)),
                  ("func", node_value(func_node(func))),
                ]),
              )
            }),
          ),
        ),
        ("body", expr_value(body)),
      ])
    Let(pattern~, expr~, body~, loc~) =>
      node("Expr::Let", loc, [
        ("pattern", pattern_value(pattern)),
        ("expr", expr_value(expr)),
        ("body", expr_value(body)),
      ])
    Sequence(exprs~, last_expr~, loc~) =>
      node("Expr::Sequence", loc, [
        (
          "exprs",
          node_value(
            list_node("Expr::Sequence::ExprList", loc, exprs, expr_value),
          ),
        ),
        ("last_expr", expr_value(last_expr)),
      ])
    Tuple(exprs~, loc~) =>
      node("Expr::Tuple", loc, [
        (
          "exprs",
          node_value(list_node("Expr::Tuple::ExprList", loc, exprs, expr_value)),
        ),
      ])
    Record(type_name~, fields~, trailing~, loc~) =>
      node("Expr::Record", loc, [
        ("type_name", option_value(type_name, type_name_value)),
        (
          "fields",
          node_value(
            list_node("Expr::Record::FieldList", loc, fields, field_def_value),
          ),
        ),
        ("trailing", node_value(trailing_mark_node(trailing, loc))),
      ])
    RecordUpdate(type_name~, record~, fields~, loc~) =>
      node("Expr::RecordUpdate", loc, [
        ("type_name", option_value(type_name, type_name_value)),
        ("record", expr_value(record)),
        (
          "fields",
          node_value(
            list_node(
              "Expr::RecordUpdate::FieldList", loc, fields, field_def_value,
            ),
          ),
        ),
      ])
    Field(record~, accessor~, loc~) =>
      node("Expr::Field", loc, [
        ("record", expr_value(record)),
        ("accessor", node_value(accessor_node(accessor))),
      ])
    Method(type_name~, method_name~, loc~) =>
      node("Expr::Method", loc, [
        ("type_name", type_name_value(type_name)),
        ("method_name", label_value(method_name)),
      ])
    DotApply(self~, method_name~, args~, return_self~, loc~) =>
      node("Expr::DotApply", loc, [
        ("self", expr_value(self)),
        ("method_name", label_value(method_name)),
        (
          "args",
          node_value(
            list_node("Expr::DotApply::ArgList", loc, args, argument_value),
          ),
        ),
        ("return_self", bool_value(return_self)),
        ("attr", node_value(apply_attr_node(loc))),
      ])
    As(expr~, trait_~, loc~) =>
      node("Expr::As", loc, [
        ("expr", expr_value(expr)),
        ("trait", type_name_value(trait_)),
      ])
    Mutate(record~, accessor~, field~, augmented_by~, loc~) =>
      node("Expr::Mutate", loc, [
        ("record", expr_value(record)),
        ("accessor", node_value(accessor_node(accessor))),
        ("field", expr_value(field)),
        ("augmented_by", option_value(augmented_by, var_value)),
      ])
    Match(expr~, cases~, match_loc~, loc~) => {
      ignore(match_loc)
      node("Expr::Match", loc, [
        ("expr", expr_value(expr)),
        (
          "cases",
          node_value(list_node("Expr::Match::CaseList", loc, cases, case_value)),
        ),
      ])
    }
    LexMatch(strategy~, expr~, match_loc~, cases~, loc~) => {
      ignore(match_loc)
      node("Expr::Lexmatch", loc, [
        ("strategy", option_value(strategy, label_value)),
        ("expr", expr_value(expr)),
        (
          "cases",
          node_value(
            list_node("Expr::Lexmatch::CaseList", loc, cases, fn(case) {
              node_value(lex_case_node(case, loc))
            }),
          ),
        ),
      ])
    }
    LetMut(binder~, ty~, expr~, body~, loc~) =>
      node("Expr::LetMut", loc, [
        ("binder", binder_value(binder)),
        ("ty", option_value(ty, type_value)),
        ("expr", expr_value(expr)),
        ("body", expr_value(body)),
      ])
    Pipe(lhs~, rhs~, loc~) =>
      node("Expr::Pipe", loc, [
        ("lhs", expr_value(lhs)),
        ("rhs", expr_value(rhs)),
      ])
    RevPipe(lhs~, rhs~, loc~) =>
      node("Expr::RevPipe", loc, [
        ("lhs", expr_value(lhs)),
        ("rhs", expr_value(rhs)),
      ])
    Assign(var_~, expr~, augmented_by~, loc~) =>
      node("Expr::Assign", loc, [
        ("var", var_value(var_)),
        ("expr", expr_value(expr)),
        ("augmented_by", option_value(augmented_by, var_value)),
      ])
    Hole(loc~, kind~) =>
      node("Expr::Hole", loc, [("kind", node_value(hole_node(kind, loc)))])
    Return(return_value~, loc~) =>
      node("Expr::Return", loc, [
        ("return_value", option_value(return_value, expr_value)),
      ])
    Raise(err_value~, loc~) =>
      node("Expr::Raise", loc, [("err_value", expr_value(err_value))])
    Quantifier(kind~, binder~, binder_ty~, body~, loc~) =>
      node("Expr::Quantifier", loc, [
        ("kind", predicate_quantifier_kind_value(kind)),
        ("binder", binder_value(binder)),
        ("binder_ty", type_value(binder_ty)),
        ("body", expr_value(body)),
      ])
    Implies(lhs~, rhs~, loc~) =>
      node("Expr::Implies", loc, [
        ("lhs", expr_value(lhs)),
        ("rhs", expr_value(rhs)),
      ])
    ProofAssert(expr~, loc~) =>
      node("Expr::ProofAssert", loc, [("expr", expr_value(expr))])
    ProofLet(binder~, expr~, loc~) =>
      node("Expr::ProofLet", loc, [
        ("binder", binder_value(binder)),
        ("expr", expr_value(expr)),
      ])
    Unit(loc~, faked~) =>
      node("Expr::Unit", loc, [("faked", bool_value(faked))])
    Break(arg~, label~, loc~) =>
      node("Expr::Break", loc, [
        ("arg", option_value(arg, expr_value)),
        ("label", option_value(label, label_value)),
      ])
    Continue(args~, label~, loc~) =>
      node("Expr::Continue", loc, [
        (
          "args",
          node_value(
            list_node("Expr::Continue::ExprList", loc, args, expr_value),
          ),
        ),
        ("label", option_value(label, label_value)),
      ])
    For(
      binders~,
      condition~,
      continue_block~,
      body~,
      for_else~,
      where_clause~,
      label~,
      loc~
    ) =>
      node("Expr::For", loc, [
        (
          "binders",
          node_value(
            for_binding_list_node("Expr::For::BindingList", loc, binders),
          ),
        ),
        ("condition", option_value(condition, expr_value)),
        (
          "continue_block",
          node_value(
            for_binding_list_node(
              "Expr::For::ContBindingList", loc, continue_block,
            ),
          ),
        ),
        ("body", expr_value(body)),
        ("for_else", option_value(for_else, expr_value)),
        ("where_clause", option_value(where_clause, where_clause_value)),
        ("label", option_value(label, label_value)),
      ])
    ForEach(
      binders~,
      expr~,
      init~,
      continue_block~,
      body~,
      else_block~,
      where_clause~,
      label~,
      loc~
    ) =>
      node("Expr::ForEach", loc, [
        (
          "binders",
          node_value(
            list_node("Expr::ForEach::BinderList", loc, binders, fn(b) {
              option_value(b, binder_value)
            }),
          ),
        ),
        ("expr", expr_value(expr)),
        (
          "init",
          node_value(
            foreach_binding_list_node("Expr::ForEach::Init", loc, init),
          ),
        ),
        (
          "continue_block",
          node_value(
            foreach_binding_list_node(
              "Expr::ForEach::ContinueBlock", loc, continue_block,
            ),
          ),
        ),
        ("body", expr_value(body)),
        ("else_block", option_value(else_block, expr_value)),
        ("where_clause", option_value(where_clause, where_clause_value)),
        ("label", option_value(label, label_value)),
      ])
    Try(
      body~,
      catch_~,
      try_else~,
      has_try~,
      try_loc~,
      catch_loc~,
      else_loc~,
      loc~
    ) => {
      ignore(try_loc)
      ignore(catch_loc)
      node("Expr::Try", loc, [
        ("body", expr_value(body)),
        (
          "catch",
          node_value(list_node("Expr::Try::CaseList", loc, catch_, case_value)),
        ),
        ("catch_all", bool_value(false)),
        (
          "try_else",
          option_value(try_else, fn(cases) {
            node_value(
              list_node("Expr::Try::CaseList", else_loc, cases, case_value),
            )
          }),
        ),
        ("has_try", bool_value(has_try)),
      ])
    }
    TryOperator(body~, kind~, try_loc~, loc~) => {
      ignore(try_loc)
      node("Expr::TryOperator", loc, [
        ("body", expr_value(body)),
        ("kind", node_value(try_operator_kind_node(kind, loc))),
      ])
    }
    Map(elems~, loc~) =>
      node("Expr::Map", loc, [
        (
          "elems",
          node_value(
            list_node("Expr::Map::ElemList", loc, elems, map_expr_elem_value),
          ),
        ),
      ])
    Group(expr~, group~, loc~) =>
      node("Expr::Group", loc, [
        ("expr", expr_value(expr)),
        ("group", node_value(group_node(group, loc))),
      ])
    TemplateWriting(expr~, template~, loc~) =>
      node("Expr::TemplateWriting", loc, [
        ("expr", expr_value(expr)),
        ("template", expr_value(template)),
        ("loc", node_value(json_location_node(loc))),
      ])
    StaticAssert(asserts~, body~) => {
      let loc = body.loc()
      node("Expr::StaticAssert", loc, [
        (
          "asserts",
          node_value(
            list_node(
              "Expr::StaticAssert::StaticAssertionList", loc, asserts, static_assertion_value,
            ),
          ),
        ),
        ("body", expr_value(body)),
      ])
    }
  }
}

///|
fn expr_value(expr : @syntax.Expr) -> Value {
  node_value(expr_node(expr))
}

///|
fn parameter_node(item : @syntax.Parameter) -> Node {
  match item {
    DiscardPositional(ty~, loc~) =>
      node("Parameter::DiscardPositional", loc, [
        ("ty", option_value(ty, type_value)),
      ])
    Positional(binder~, ty~) => {
      let loc = if ty is Some(ty) {
        binder.loc.merge(ty.loc())
      } else {
        binder.loc
      }
      node("Parameter::Positional", loc, [
        ("binder", binder_value(binder)),
        ("ty", option_value(ty, type_value)),
      ])
    }
    Labelled(binder~, ty~) => {
      let loc = if ty is Some(ty) {
        binder.loc.merge(ty.loc())
      } else {
        binder.loc
      }
      node("Parameter::Labelled", loc, [
        ("binder", binder_value(binder)),
        ("ty", option_value(ty, type_value)),
      ])
    }
    Optional(binder~, default~, ty~) => {
      let loc = binder.loc.merge(default.loc())
      node("Parameter::Optional", loc, [
        ("binder", binder_value(binder)),
        ("default", expr_value(default)),
        ("ty", option_value(ty, type_value)),
      ])
    }
    QuestionOptional(binder~, ty~) => {
      let loc = if ty is Some(ty) {
        binder.loc.merge(ty.loc())
      } else {
        binder.loc
      }
      node("Parameter::QuestionOptional", loc, [
        ("binder", binder_value(binder)),
        ("ty", option_value(ty, type_value)),
      ])
    }
  }
}

///|
fn parameter_value(parameter : @syntax.Parameter) -> Value {
  node_value(parameter_node(parameter))
}

///|
fn test_name_value(item : @syntax.TestName) -> Value {
  option_value(item, fn(test_name) {
    let (s, loc) = test_name
    node_value(node1("TestName", loc, string_literal_value(s)))
  })
}

///|
fn attribute_node(item : @attribute.Attribute) -> Node {
  node("Attribute", item.loc, [("raw", string_value(item.raw))])
}

///|
fn attribute_value(attr : @attribute.Attribute) -> Value {
  node_value(attribute_node(attr))
}

///|
fn type_decl_node(item : @syntax.TypeDecl) -> Node {
  node("TypeDecl", item.loc, [
    ("tycon", string_value(item.tycon)),
    (
      "params",
      node_value(
        list_node(
          "TypeDecl::ParamList",
          item.loc,
          item.params,
          type_decl_binder_value,
        ),
      ),
    ),
    ("components", node_value(type_desc_node(item.components, item.loc))),
    (
      "attrs",
      node_value(
        list_node("TypeDecl::AttrList", item.loc, item.attrs, attribute_value),
      ),
    ),
    ("doc", doc_string_value(item.doc)),
    ("type_vis", node_value(visibility_node(item.type_vis, item.loc))),
    ("is_declare", bool_value(item.is_declare)),
    (
      "deriving",
      node_value(
        list_node(
          "TypeDecl::DerivingList",
          item.loc,
          item.deriving,
          deriving_directive_value,
        ),
      ),
    ),
  ])
}

///|
fn fun_decl_node(item : @syntax.FunDecl) -> Node {
  node("FunDecl", item.loc, [
    ("type_name", option_value(item.type_name, type_name_value)),
    ("name", binder_value(item.name)),
    ("has_error", AstNull),
    ("is_async", option_value(item.is_async, async_value)),
    (
      "decl_params",
      option_value(item.decl_params, fn(params) {
        node_value(
          list_node(
            "FunDecl::ParameterList",
            item.params_loc,
            params,
            parameter_value,
          ),
        )
      }),
    ),
    (
      "quantifiers",
      node_value(
        list_node(
          "FunDecl::QuantifierList",
          item.params_loc,
          item.quantifiers,
          type_var_binder_value,
        ),
      ),
    ),
    ("return_type", option_value(item.return_type, type_value)),
    ("error_type", node_value(error_type_node(item.error_type, item.loc))),
    ("vis", node_value(visibility_node(item.vis, item.params_loc))),
    (
      "attrs",
      node_value(
        list_node(
          "FunDecl::AttrList",
          item.params_loc,
          item.attrs,
          attribute_value,
        ),
      ),
    ),
    ("doc", doc_string_value(item.doc)),
  ])
}

///|
fn decl_body_node(item : @syntax.DeclBody, loc : @basic.Location) -> Node {
  match item {
    DeclBody(expr~) =>
      node("DeclBody::DeclBody", loc, [
        (
          "local_types",
          node_value(empty_list_node("DeclBody::DeclBody::LocalTypeList", loc)),
        ),
        ("expr", expr_value(expr)),
      ])
    DeclStubs(stubs) =>
      node1("DeclBody::DeclStubs", loc, node_value(func_stubs_node(stubs, loc)))
    DeclNone => node0("DeclBody::DeclNone", loc)
  }
}

///|
fn label_node(item : @syntax.Label) -> Node {
  node("Label", item.loc, [("name", string_value(item.name))])
}

///|
fn label_value(label : @syntax.Label) -> Value {
  node_value(label_node(label))
}

///|
fn alias_target_node(item : @syntax.AliasTarget) -> Node {
  node("AliasTarget", item.loc(), [
    ("binder", binder_value(item.binder)),
    ("target", option_value(item.target, label_value)),
  ])
}

///|
fn binder_node(item : @syntax.Binder) -> Node {
  node("Binder", item.loc, [("name", string_value(item.name))])
}

///|
fn binder_value(binder : @syntax.Binder) -> Value {
  node_value(binder_node(binder))
}

///|
pub fn from_type(item : @syntax.Type) -> Node {
  type_node(item)
}

///|
fn type_node(item : @syntax.Type) -> Node {
  match item {
    Any(loc~) => node0("Type::Any", loc)
    Arrow(args~, res~, err~, is_async~, loc~) =>
      node("Type::Arrow", loc, [
        (
          "args",
          node_value(list_node("Type::Arrow::ArgList", loc, args, type_value)),
        ),
        ("res", type_value(res)),
        ("err", node_value(error_type_node(err, loc))),
        ("is_async", option_value(is_async, async_value)),
      ])
    Tuple(tys~, loc~) =>
      node("Type::Tuple", loc, [
        (
          "tys",
          node_value(list_node("Type::Tuple::TypeList", loc, tys, type_value)),
        ),
      ])
    Name(constr_id~, tys~, loc~) =>
      node("Type::Name", loc, [
        ("constr_id", node_value(constr_id_node(constr_id))),
        (
          "tys",
          node_value(list_node("Type::Name::TypeList", loc, tys, type_value)),
        ),
      ])
    Option(ty~, loc~, question_loc~) => {
      ignore(question_loc)
      node("Type::Option", loc, [("ty", type_value(ty))])
    }
    Object(constr_id) =>
      node1(
        "Type::Object",
        constr_id.loc,
        node_value(constr_id_node(constr_id)),
      )
  }
}

///|
fn type_value(ty : @syntax.Type) -> Value {
  node_value(type_node(ty))
}

///|
fn visibility_node(item : @syntax.Visibility, loc : @basic.Location) -> Node {
  match item {
    Default => node0("Visibility::Default", loc)
    Priv(loc~) => node0("Visibility::Priv", loc)
    Pub(attr~, loc~) =>
      node("Visibility::Pub", loc, [("attr", option_value(attr, string_value))])
  }
}

///|
fn trait_decl_node(item : @syntax.TraitDecl) -> Node {
  node("TraitDecl", item.loc, [
    ("name", binder_value(item.name)),
    (
      "supers",
      node_value(
        list_node(
          "TraitDecl::SuperList",
          item.loc,
          item.supers,
          type_var_constraint_value,
        ),
      ),
    ),
    (
      "methods",
      node_value(
        list_node(
          "TraitDecl::MethodList",
          item.loc,
          item.methods,
          trait_method_decl_value,
        ),
      ),
    ),
    ("vis", node_value(visibility_node(item.vis, item.loc))),
    ("is_declare", bool_value(item.is_declare)),
    (
      "attrs",
      node_value(
        list_node("TraitDecl::AttrList", item.loc, item.attrs, attribute_value),
      ),
    ),
    ("doc", doc_string_value(item.doc)),
  ])
}

///|
fn type_name_node(item : @syntax.TypeName) -> Node {
  node("TypeName", item.loc, [
    ("name", node_value(long_ident_node(item.name, item.loc))),
    ("is_object", bool_value(item.is_object)),
  ])
}

///|
fn type_name_value(type_name : @syntax.TypeName) -> Value {
  node_value(type_name_node(type_name))
}

///|
fn type_var_binder_node(item : @syntax.TypeVarBinder) -> Node {
  let constraints_loc = list_loc_or(item.constraints, item.name_loc, fn(c) {
    c.loc
  })
  let loc = item.name_loc.merge(constraints_loc)
  node("TypeVarBinder", loc, [
    ("name", string_value(item.name)),
    (
      "constraints",
      node_value(
        list_node(
          "TypeVarBinder::TypeVarConstraintList",
          constraints_loc,
          item.constraints,
          type_var_constraint_value,
        ),
      ),
    ),
  ])
}

///|
fn error_type_node(item : @syntax.ErrorType, loc : @basic.Location) -> Node {
  match item {
    ErrorType(ty~) =>
      node("ErrorType::ErrorType", ty.loc(), [("ty", type_value(ty))])
    DefaultErrorType(loc~) => node0("ErrorType::DefaultErrorType", loc)
    NoErrorType => node0("ErrorType::NoErrorType", loc)
    Noraise(loc~) => node0("ErrorType::Noraise", loc)
    MaybeError(ty~) =>
      node("ErrorType::MaybeError", ty.loc(), [("ty", type_value(ty))])
  }
}

///|
fn using_name_value(item : (@syntax.AliasTarget, @syntax.UsingKind)) -> Value {
  let (target, kind) = item
  let loc = target.loc()
  let kind_str = match kind {
    Value => "value"
    Type => "type"
    Trait => "trait"
  }
  node_value(
    node("UsingName", loc, [
      ("name", node_value(alias_target_node(target))),
      ("kind", string_value(kind_str)),
    ]),
  )
}

///|
fn argument_node(item : @syntax.Argument) -> Node {
  node("Argument", item.value.loc(), [
    ("value", expr_value(item.value)),
    ("kind", node_value(argument_kind_node(item.kind, item.value.loc()))),
  ])
}

///|
fn argument_value(argument : @syntax.Argument) -> Value {
  node_value(argument_node(argument))
}

///|
fn argument_kind_node(
  item : @syntax.ArgumentKind,
  loc : @basic.Location,
) -> Node {
  match item {
    Positional => node0("ArgumentKind::Positional", loc)
    Labelled(label) =>
      node1("ArgumentKind::Labelled", label.loc, label_value(label))
    LabelledPun(label) =>
      node1("ArgumentKind::LabelledPun", label.loc, label_value(label))
    LabelledOption(label~, question_loc~) => {
      ignore(question_loc)
      node("ArgumentKind::LabelledOption", label.loc, [
        ("label", label_value(label)),
      ])
    }
    LabelledOptionPun(label~, question_loc~) => {
      ignore(question_loc)
      node("ArgumentKind::LabelledOptionPun", label.loc, [
        ("label", label_value(label)),
      ])
    }
  }
}

///|
fn apply_attr_node(loc : @basic.Location) -> Node {
  node0("ApplyAttr::NoAttr", loc)
}

///|
fn var_node(item : @syntax.Var) -> Node {
  node("Var", item.loc, [
    ("name", node_value(long_ident_node(item.name, item.loc))),
  ])
}

///|
fn var_value(var_ : @syntax.Var) -> Value {
  node_value(var_node(var_))
}

///|
fn constant_value(item : @syntax.Constant, loc : @basic.Location) -> Value {
  node_value(constant_node(item, loc))
}

///|
fn constant_node(item : @syntax.Constant, loc : @basic.Location) -> Node {
  match item {
    Bool(b) => node1("Constant::Bool", loc, bool_value(b))
    Byte(b) => node1("Constant::Byte", loc, byte_literal_value(b))
    Bytes(b) => node1("Constant::Bytes", loc, bytes_literal_value(b))
    Char(c) => node1("Constant::Char", loc, char_literal_value(c))
    Int(s) => node1("Constant::Int", loc, string_value(s))
    Int64(s) => node1("Constant::Int64", loc, string_value(s))
    UInt(s) => node1("Constant::UInt", loc, string_value(s))
    UInt64(s) => node1("Constant::UInt64", loc, string_value(s))
    Float(s) => node1("Constant::Float", loc, string_value(s))
    Double(s) => node1("Constant::Double", loc, string_value(s))
    String(s) => node1("Constant::String", loc, string_literal_value(s))
    Regex(s) => node1("Constant::Regex", loc, string_literal_value(s))
    BigInt(s) => node1("Constant::BigInt", loc, string_value(s))
  }
}

///|
fn spreadable_elem_node(item : @syntax.SpreadableElem) -> Node {
  match item {
    Regular(expr) =>
      node1("SpreadableElem::Regular", expr.loc(), expr_value(expr))
    Spread(expr~, loc~) =>
      node("SpreadableElem::Spread", loc, [("expr", expr_value(expr))])
  }
}

///|
fn spreadable_elem_value(elem : @syntax.SpreadableElem) -> Value {
  node_value(spreadable_elem_node(elem))
}

///|
fn multiline_string_elem_node(
  item : @syntax.MultilineStringElem,
  loc : @basic.Location,
) -> Node {
  match item {
    String(s) => node1("MultilineString::String", loc, string_value(s))
    Interp(elems) =>
      node1(
        "MultilineString::Interp",
        loc,
        node_value(
          list_node(
            "MultilineString::Interp::ElemList", loc, elems, interp_elem_value,
          ),
        ),
      )
  }
}

///|
fn interp_elem_node(item : @syntax.InterpElem) -> Node {
  match item {
    Literal(repr~, loc~) =>
      node("InterpElem::Literal", loc, [("repr", string_literal_value(repr))])
    Expr(expr~, loc~) =>
      node("InterpElem::Expr", loc, [("expr", expr_value(expr))])
    Source({ source, loc }) =>
      node("InterpElem::Source", loc, [("source", string_value(source))])
  }
}

///|
fn interp_elem_value(elem : @syntax.InterpElem) -> Value {
  node_value(interp_elem_node(elem))
}

///|
fn constructor_node(item : @syntax.Constructor) -> Node {
  node("Constructor", item.loc, [
    ("name", node_value(constr_name_node(item.name))),
    (
      "extra_info",
      node_value(constructor_extra_info_node(item.extra_info, item.loc)),
    ),
  ])
}

///|
fn constructor_extra_info_node(
  item : @syntax.ConstructorExtraInfo,
  loc : @basic.Location,
) -> Node {
  match item {
    TypeName(type_name) =>
      node1(
        "ConstructorExtraInfo::TypeName",
        type_name.loc,
        type_name_value(type_name),
      )
    TypeNameWithConstrPackage(type_name~, pkg~) =>
      node("ConstructorExtraInfo::TypeNameWithConstrPackage", loc, [
        ("type_name", type_name_value(type_name)),
        ("pkg", string_value(pkg)),
      ])
    Package(s) => node1("ConstructorExtraInfo::Package", loc, string_value(s))
    NoExtraInfo => node0("ConstructorExtraInfo::NoExtraInfo", loc)
  }
}

///|
fn func_node(item : @syntax.Func) -> Node {
  node("Func::Lambda", item.loc, [
    (
      "parameters",
      node_value(
        list_node(
          "Func::Lambda::ParameterList",
          item.params_loc,
          item.parameters,
          parameter_value,
        ),
      ),
    ),
    ("body", expr_value(item.body)),
    ("return_type", option_value(item.return_type, type_value)),
    ("error_type", node_value(error_type_node(item.error_type, item.loc))),
    ("kind", node_value(fn_kind_node(item.kind, item.loc))),
    ("has_error", AstNull),
    ("is_async", option_value(item.is_async, async_value)),
  ])
}

///|
fn fn_kind_node(item : @syntax.FnKind, loc : @basic.Location) -> Node {
  match item {
    Lambda => node0("FnKind::Lambda", loc)
    Arrow => node0("FnKind::Arrow", loc)
  }
}

///|
fn field_def_node(item : @syntax.FieldDef) -> Node {
  node("FieldDef", item.loc, [
    ("label", label_value(item.label)),
    ("expr", expr_value(item.expr)),
    ("is_pun", bool_value(item.is_pun)),
  ])
}

///|
fn field_def_value(field : @syntax.FieldDef) -> Value {
  node_value(field_def_node(field))
}

///|
fn trailing_mark_node(
  item : @syntax.TrailingMark,
  loc : @basic.Location,
) -> Node {
  match item {
    Comma => node0("Trailing::Comma", loc)
    Semi => node0("Trailing::Semi", loc)
    None => node0("Trailing::None", loc)
  }
}

///|
fn accessor_node(item : @syntax.Accessor) -> Node {
  match item {
    Label(label) => node1("Accessor::Label", label.loc, label_value(label))
    Index(tuple_index~, loc~) =>
      node("Accessor::Index", loc, [
        ("tuple_index", number_value(tuple_index.to_double())),
      ])
    Newtype(loc~) => node0("Accessor::Newtype", loc)
  }
}

///|
fn case_node(item : @syntax.Case) -> Node {
  let pattern_loc = item.pattern.loc()
  let body_loc = item.body.loc()
  let loc = pattern_loc.merge(body_loc)
  node("Case", loc, [
    ("pattern", pattern_value(item.pattern)),
    ("guard", option_value(item.guard_, expr_value)),
    ("body", expr_value(item.body)),
  ])
}

///|
fn case_value(case : @syntax.Case) -> Value {
  node_value(case_node(case))
}

///|
pub fn from_pattern(item : @syntax.Pattern) -> Node {
  pattern_node(item)
}

///|
fn pattern_node(item : @syntax.Pattern) -> Node {
  match item {
    Alias(pat~, alias_~, loc~) =>
      node("Pattern::Alias", loc, [
        ("pat", pattern_value(pat)),
        ("alias", binder_value(alias_)),
      ])
    Any(loc~) => node0("Pattern::Any", loc)
    Array(pats~, loc~) =>
      node("Pattern::Array", loc, [
        ("pats", node_value(array_patterns_node(pats, loc))),
      ])
    Constant(c~, loc~) =>
      node("Pattern::Constant", loc, [("constant", constant_value(c, loc))])
    Constraint(pat~, ty~, loc~) =>
      node("Pattern::Constraint", loc, [
        ("pat", pattern_value(pat)),
        ("ty", type_value(ty)),
      ])
    Constr(constr~, args~, is_open~, loc~) =>
      node("Pattern::Constr", loc, [
        ("constr", node_value(constructor_node(constr))),
        (
          "args",
          option_value(args, fn(args) {
            node_value(
              list_node(
                "Pattern::Constr::ArgList", loc, args, constr_pat_arg_value,
              ),
            )
          }),
        ),
        ("is_open", bool_value(is_open)),
      ])
    Or(pat1~, pat2~, loc~) =>
      node("Pattern::Or", loc, [
        ("pat1", pattern_value(pat1)),
        ("pat2", pattern_value(pat2)),
      ])
    Tuple(pats~, loc~) =>
      node("Pattern::Tuple", loc, [
        (
          "pats",
          node_value(
            list_node("Pattern::Tuple::PatternList", loc, pats, pattern_value),
          ),
        ),
      ])
    Var(binder) => node1("Pattern::Var", binder.loc, binder_value(binder))
    Record(fields~, is_closed~, loc~) =>
      node("Pattern::Record", loc, [
        (
          "fields",
          node_value(
            list_node(
              "Pattern::Record::FieldList", loc, fields, field_pat_value,
            ),
          ),
        ),
        ("is_closed", bool_value(is_closed)),
      ])
    Map(elems~, is_closed~, loc~) =>
      node("Pattern::Map", loc, [
        (
          "elems",
          node_value(
            list_node("Pattern::Map::ElemList", loc, elems, map_pat_elem_value),
          ),
        ),
        ("is_closed", bool_value(is_closed)),
      ])
    Range(lhs~, rhs~, kind~, loc~) =>
      node("Pattern::Range", loc, [
        ("lhs", pattern_value(lhs)),
        ("rhs", pattern_value(rhs)),
        ("kind", node_value(range_kind_node(kind, loc))),
      ])
    SpecialConstr(binder~, args~, loc~) =>
      node("Pattern::SpecialConstr", loc, [
        ("binder", binder_value(binder)),
        (
          "args",
          node_value(
            list_node(
              "Pattern::SpecialConstr::ArgList", loc, args, constr_pat_arg_value,
            ),
          ),
        ),
      ])
  }
}

///|
fn pattern_value(pattern : @syntax.Pattern) -> Value {
  node_value(pattern_node(pattern))
}

///|
fn range_kind_node(item : @syntax.RangeKind, loc : @basic.Location) -> Node {
  match item {
    Inclusive | InclusiveMissingEqual => node0("RangeKind::Inclusive", loc)
    Exclusive => node0("RangeKind::Exclusive", loc)
  }
}

///|
fn array_patterns_node(
  item : @syntax.ArrayPatterns,
  loc : @basic.Location,
) -> Node {
  match item {
    Closed(pats) =>
      node1(
        "ArrayPatterns::Closed",
        loc,
        node_value(
          list_node(
            "ArrayPatterns::Closed::PatternList", loc, pats, array_pattern_value,
          ),
        ),
      )
    Open(pats1, pats2, binder) =>
      node("ArrayPatterns::Open", loc, [
        (
          "0",
          node_value(
            list_node(
              "ArrayPatterns::Open::LPatternList", loc, pats1, array_pattern_value,
            ),
          ),
        ),
        (
          "1",
          node_value(
            list_node(
              "ArrayPatterns::Open::RPatternList", loc, pats2, array_pattern_value,
            ),
          ),
        ),
        ("2", node_value(dot_dot_binder_node(binder, loc))),
      ])
  }
}

///|
fn array_pattern_node(item : @syntax.ArrayPattern) -> Node {
  match item {
    Pattern(pattern) =>
      node1("ArrayPattern::Pattern", pattern.loc(), pattern_value(pattern))
    StringSpread(str~, loc~) =>
      node("ArrayPattern::StringSpread", loc, [
        ("str", string_literal_value(str)),
      ])
    BytesSpread(bytes~, loc~) =>
      node("ArrayPattern::BytesSpread", loc, [
        ("bytes", bytes_literal_value(bytes)),
      ])
    ConstSpread(binder~, pkg~, loc~) =>
      node("ArrayPattern::ConstSpread", loc, [
        ("binder", binder_value(binder)),
        ("pkg", option_value(pkg, string_value)),
      ])
  }
}

///|
fn array_pattern_value(pattern : @syntax.ArrayPattern) -> Value {
  node_value(array_pattern_node(pattern))
}

///|
fn dot_dot_binder_node(
  item : @syntax.DotDotBinder,
  loc : @basic.Location,
) -> Node {
  match item {
    Underscore => node0("DotDotBinder::Underscore", loc)
    NoBinder => node0("DotDotBinder::NoBinder", loc)
    BinderAs(binder) =>
      node1("DotDotBinder::BinderAs", binder.loc, binder_value(binder))
    Binder(binder) =>
      node1("DotDotBinder::Binder", binder.loc, binder_value(binder))
  }
}

///|
fn constr_pat_arg_node(item : @syntax.ConstrPatArg) -> Node {
  node("ConstrPatArg", item.pat.loc(), [
    ("pat", pattern_value(item.pat)),
    ("kind", node_value(argument_kind_node(item.kind, item.pat.loc()))),
  ])
}

///|
fn constr_pat_arg_value(arg : @syntax.ConstrPatArg) -> Value {
  node_value(constr_pat_arg_node(arg))
}

///|
fn field_pat_node(item : @syntax.FieldPat) -> Node {
  node("FieldPat", item.loc, [
    ("label", label_value(item.label)),
    ("pattern", pattern_value(item.pattern)),
    ("is_pun", bool_value(item.is_pun)),
  ])
}

///|
fn field_pat_value(field : @syntax.FieldPat) -> Value {
  node_value(field_pat_node(field))
}

///|
fn map_pat_elem_node(item : @syntax.MapPatElem) -> Node {
  node("MapPatElem", item.loc, [
    ("key", constant_value(item.key, item.key_loc)),
    ("pat", pattern_value(item.pat)),
    ("match_absent", bool_value(item.match_absent)),
  ])
}

///|
fn map_pat_elem_value(elem : @syntax.MapPatElem) -> Value {
  node_value(map_pat_elem_node(elem))
}

///|
fn map_expr_elem_node(item : @syntax.MapExprElem) -> Node {
  node("MapExprElem", item.loc, [
    ("key", constant_value(item.key, item.key_loc)),
    ("expr", expr_value(item.expr)),
  ])
}

///|
fn map_expr_elem_value(elem : @syntax.MapExprElem) -> Value {
  node_value(map_expr_elem_node(elem))
}

///|
fn static_assertion_node(item : @syntax.StaticAssertion) -> Node {
  node("StaticAssertion", item.loc, [
    ("ty", type_value(item.ty)),
    ("trait", node_value(long_ident_node(item.trait_, item.loc))),
    ("msg", string_value(item.msg)),
  ])
}

///|
fn static_assertion_value(assertion : @syntax.StaticAssertion) -> Value {
  node_value(static_assertion_node(assertion))
}

///|
fn lex_case_node(item : @syntax.LexCase, loc : @basic.Location) -> Node {
  node("LexCase", loc, [
    (
      "pat",
      node_value(
        list_node("LexCase::PatternList", item.pat_loc, item.pat, fn(ltp) {
          node_value(lex_top_pattern_node(ltp, item.pat_loc))
        }),
      ),
    ),
    ("guard", option_value(item.guard_, expr_value)),
    ("body", expr_value(item.body)),
  ])
}

///|
fn lex_top_pattern_node(
  item : @syntax.LexTopPattern,
  loc : @basic.Location,
) -> Node {
  match item {
    Pattern(pat) =>
      node1("LexTopPattern::Pattern", loc, node_value(lex_pattern_node(pat)))
    Binder(binder) => node1("LexTopPattern::Binder", loc, binder_value(binder))
    Wildcard(loc~) => node0("LexTopPattern::Wildcard", loc)
  }
}

///|
fn lex_pattern_node(item : @syntax.LexPattern) -> Node {
  match item {
    Regex(lit~, offset~, loc~) =>
      node("LexPattern::Regex", loc, [
        ("lit", string_value(lit)),
        ("offset", number_value(offset.to_double())),
      ])
    RegexInterp(elems~, loc~) =>
      node("LexPattern::RegexInterp", loc, [
        (
          "elems",
          node_value(
            list_node(
              "LexPattern::RegexInterp::InterpElemList", loc, elems, interp_elem_value,
            ),
          ),
        ),
      ])
    ConstantRef(lid~, loc~) =>
      node("LexPattern::ConstantRef", loc, [
        ("lid", node_value(long_ident_node(lid, loc))),
      ])
    Alias(pat~, binder~, loc~) =>
      node("LexPattern::Alias", loc, [
        ("pat", node_value(lex_pattern_node(pat))),
        ("binder", binder_value(binder)),
      ])
    Sequence(pats~, loc~) =>
      node("LexPattern::Sequence", loc, [
        (
          "pats",
          node_value(
            list_node(
              "LexPattern::Sequence::PatternList", loc, pats, lex_pattern_value,
            ),
          ),
        ),
      ])
  }
}

///|
fn lex_pattern_value(pattern : @syntax.LexPattern) -> Value {
  node_value(lex_pattern_node(pattern))
}

///|
fn regex_pattern_node(item : @syntax.RegexPattern) -> Node {
  match item {
    Literal(lit~, loc~) =>
      node("RegexPattern::Literal", loc, [("lit", string_value(lit))])
    Reference(lid~, loc~) =>
      node("RegexPattern::Reference", loc, [
        ("lid", node_value(long_ident_node(lid, loc))),
      ])
    Sequence(pat1~, pat2~, loc~) =>
      node("RegexPattern::Sequence", loc, [
        ("pat1", node_value(regex_pattern_node(pat1))),
        ("pat2", node_value(regex_pattern_node(pat2))),
      ])
    Alternation(pat1~, pat2~, loc~) =>
      node("RegexPattern::Alternation", loc, [
        ("pat1", node_value(regex_pattern_node(pat1))),
        ("pat2", node_value(regex_pattern_node(pat2))),
      ])
    Alias(pat~, binder~, loc~) =>
      node("RegexPattern::Alias", loc, [
        ("pat", node_value(regex_pattern_node(pat))),
        ("binder", binder_value(binder)),
      ])
  }
}

///|
fn predicate_quantifier_kind_value(
  item : @syntax.PredicateQuantifierKind,
) -> Value {
  match item {
    Forall => string_value("forall")
    Exists => string_value("exists")
  }
}

///|
fn list_comprehension_kind_node(
  item : @syntax.ListComprehensionKind,
  loc : @basic.Location,
) -> Node {
  match item {
    Foreach(binders~, expr~, init~, continue_block~) =>
      node("Expr::ListComprehension::Kind::Foreach", loc, [
        (
          "binders",
          node_value(
            list_node("Expr::ForEach::BinderList", loc, binders, fn(b) {
              option_value(b, binder_value)
            }),
          ),
        ),
        ("expr", expr_value(expr)),
        (
          "init",
          node_value(
            foreach_binding_list_node("Expr::ForEach::Init", loc, init),
          ),
        ),
        (
          "continue_block",
          node_value(
            foreach_binding_list_node(
              "Expr::ForEach::ContinueBlock", loc, continue_block,
            ),
          ),
        ),
      ])
    For(binders~, condition~, continue_block~, for_loc~) => {
      ignore(for_loc)
      node("Expr::ListComprehension::Kind::For", loc, [
        (
          "binders",
          node_value(
            for_binding_list_node("Expr::For::BindingList", loc, binders),
          ),
        ),
        ("condition", option_value(condition, expr_value)),
        (
          "continue_block",
          node_value(
            for_binding_list_node(
              "Expr::For::ContBindingList", loc, continue_block,
            ),
          ),
        ),
      ])
    }
  }
}

///|
fn try_operator_kind_node(
  item : @syntax.TryOperatorKind,
  loc : @basic.Location,
) -> Node {
  match item {
    Question => node0("TryOperatorKind::Question", loc)
    Exclamation => node0("TryOperatorKind::Exclamation", loc)
  }
}

///|
fn group_node(item : @syntax.Group, loc : @basic.Location) -> Node {
  match item {
    Brace => node0("Group::Brace", loc)
    Paren => node0("Group::Paren", loc)
  }
}

///|
fn hole_node(item : @syntax.Hole, loc : @basic.Location) -> Node {
  match item {
    Synthesized => node0("Hole::Synthesized", loc)
    Incomplete => node0("Hole::Incomplete", loc)
    Todo => node0("Hole::Todo", loc)
  }
}

///|
fn async_value(is_async : @basic.Location) -> Value {
  node_value(node0("Async", is_async))
}

///|
fn json_location_node(loc : @basic.Location) -> Node {
  node0("__LocationJson", loc)
}

///|
fn for_binding_list_node(
  kind : String,
  loc : @basic.Location,
  bindings : @list.List[(@syntax.Binder, @syntax.Expr)],
) -> Node {
  list_node(kind, loc, bindings, fn(binding) {
    let (binder, expr) = binding
    let binding_kind = if kind == "Expr::For::ContBindingList" {
      "For::ContBinding"
    } else {
      "For::Binding"
    }
    node_value(
      node(binding_kind, loc, [
        ("binder", binder_value(binder)),
        ("expr", expr_value(expr)),
      ]),
    )
  })
}

///|
fn foreach_binding_list_node(
  kind : String,
  loc : @basic.Location,
  bindings : @list.List[(@syntax.Binder, @syntax.Expr)],
) -> Node {
  list_node(kind, loc, bindings, fn(binding) {
    let (binder, expr) = binding
    let (binding_kind, binder_field) = if kind == "Expr::ForEach::Init" {
      ("ForEach::Init", "init")
    } else {
      ("ForEach::ContinueBlock", "binder")
    }
    node_value(
      node(binding_kind, loc, [
        (binder_field, binder_value(binder)),
        ("expr", expr_value(expr)),
      ]),
    )
  })
}

///|
pub fn from_impl(item : @syntax.Impl) -> Node {
  impl_node(item)
}

///|
pub fn from_impls(impls : @list.List[@syntax.Impl]) -> Node {
  list_node("ImplList", @syntax.no_location, impls, impl_value)
}

///|
fn impl_node(item : @syntax.Impl) -> Node {
  match item {
    TopExpr(expr~, is_main~, is_async~, loc~) =>
      node("Impl::TopExpr", loc, [
        ("expr", expr_value(expr)),
        ("is_main", bool_value(is_main)),
        (
          "local_types",
          node_value(empty_list_node("Impl::TopExpr::LocalTypeList", loc)),
        ),
        ("is_async", option_value(is_async, async_value)),
      ])
    TopTest(expr~, name~, params~, is_async~, loc~, attrs~, doc~) =>
      node("Impl::TopTest", loc, [
        ("expr", expr_value(expr)),
        ("name", test_name_value(name)),
        (
          "params",
          option_value(params, fn(params) {
            node_value(
              list_node(
                "Impl::TopTest::ParamList", loc, params, parameter_value,
              ),
            )
          }),
        ),
        (
          "local_types",
          node_value(empty_list_node("Impl::TopTest::LocalTypeList", loc)),
        ),
        ("is_async", option_value(is_async, async_value)),
        (
          "attrs",
          node_value(
            list_node("Impl::TopTest::AttrList", loc, attrs, attribute_value),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
    TopTypeDef(type_decl) =>
      node1(
        "Impl::TopTypeDef",
        type_decl.loc,
        node_value(type_decl_node(type_decl)),
      )
    TopFuncDef(fun_decl~, decl_body~, where_clause~, loc~) =>
      node("Impl::TopFuncDef", loc, [
        ("fun_decl", node_value(fun_decl_node(fun_decl))),
        ("where_clause", option_value(where_clause, where_clause_value)),
        ("decl_body", node_value(decl_body_node(decl_body, loc))),
      ])
    TopLetDef(
      binder~,
      ty~,
      expr~,
      vis~,
      is_constant~,
      loc~,
      attrs~,
      doc~,
      is_declare~
    ) =>
      node("Impl::TopLetDef", loc, [
        ("binder", binder_value(binder)),
        ("ty", option_value(ty, type_value)),
        ("expr", expr_value(expr)),
        ("vis", node_value(visibility_node(vis, loc))),
        ("is_constant", bool_value(is_constant)),
        ("is_declare", bool_value(is_declare)),
        (
          "attrs",
          node_value(
            list_node("Impl::TopLetDef::AttrList", loc, attrs, attribute_value),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
    TopTrait(trait_decl) =>
      node1(
        "Impl::TopTrait",
        trait_decl.loc,
        node_value(trait_decl_node(trait_decl)),
      )
    TopImpl(
      self_ty~,
      trait_~,
      method_name~,
      quantifiers~,
      params~,
      ret_ty~,
      err_ty~,
      body~,
      vis~,
      loc~,
      attrs~,
      doc~
    ) =>
      node("Impl::TopImpl", loc, [
        ("self_ty", option_value(self_ty, type_value)),
        ("trait", type_name_value(trait_)),
        ("method_name", binder_value(method_name)),
        ("has_error", AstNull),
        (
          "quantifiers",
          node_value(
            list_node(
              "Impl::TopImpl::QuantifierList", loc, quantifiers, type_var_binder_value,
            ),
          ),
        ),
        (
          "params",
          node_value(
            list_node("Impl::TopImpl::ParamList", loc, params, parameter_value),
          ),
        ),
        ("ret_ty", option_value(ret_ty, type_value)),
        ("err_ty", node_value(error_type_node(err_ty, loc))),
        ("body", node_value(decl_body_node(body, loc))),
        ("vis", node_value(visibility_node(vis, loc))),
        (
          "attrs",
          node_value(
            list_node("Impl::TopImpl::AttrList", loc, attrs, attribute_value),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
    TopView(
      quantifiers~,
      source_ty~,
      view_type_name~,
      view_type_loc~,
      view_constrs~,
      view_func_name~,
      parameters~,
      params_loc~,
      body~,
      vis~,
      loc~,
      attrs~,
      doc~
    ) => {
      ignore(view_type_loc)
      node("Impl::TopView", loc, [
        (
          "quantifiers",
          node_value(
            list_node(
              "Impl::TopView::QuantifierList", loc, quantifiers, type_var_binder_value,
            ),
          ),
        ),
        ("source_ty", type_value(source_ty)),
        (
          "view_constrs",
          node_value(
            list_node(
              "Impl::TopView::ConstrList", params_loc, view_constrs, constr_decl_value,
            ),
          ),
        ),
        ("body", expr_value(body)),
        ("ty_name", string_value(view_type_name)),
        (
          "parameters",
          node_value(
            list_node(
              "Impl::TopView::ParameterList", loc, parameters, parameter_value,
            ),
          ),
        ),
        ("func_name", binder_value(view_func_name)),
        ("vis", node_value(visibility_node(vis, loc))),
        (
          "attrs",
          node_value(
            list_node("Impl::TopView::AttrList", loc, attrs, attribute_value),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
    }
    TopImplRelation(
      self_ty~,
      trait_~,
      quantifiers~,
      vis~,
      attrs~,
      loc~,
      doc~,
      is_declare~
    ) =>
      node("Impl::TopImplRelation", loc, [
        ("self_ty", type_value(self_ty)),
        ("trait", type_name_value(trait_)),
        (
          "quantifiers",
          node_value(
            list_node(
              "Impl::TopImplRelation::QuantifierList", loc, quantifiers, type_var_binder_value,
            ),
          ),
        ),
        ("vis", node_value(visibility_node(vis, loc))),
        ("is_declare", bool_value(is_declare)),
        (
          "attrs",
          node_value(
            list_node(
              "Impl::TopImplRelation::AttrList", loc, attrs, attribute_value,
            ),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
    TopUsing(pkg~, names~, vis~, attrs~, loc~, doc~) =>
      node("Impl::TopUsing", loc, [
        ("pkg", label_value(pkg)),
        (
          "names",
          node_value(
            list_node("Impl::TopUsing::NameList", loc, names, using_name_value),
          ),
        ),
        ("vis", node_value(visibility_node(vis, loc))),
        (
          "attrs",
          node_value(
            list_node("Impl::TopUsing::AttrList", loc, attrs, attribute_value),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
  }
}

///|
fn impl_value(item : @syntax.Impl) -> Value {
  node_value(impl_node(item))
}

///|
fn type_decl_binder_value(item : @syntax.TypeDeclBinder) -> Value {
  node_value(type_decl_binder_node(item))
}

///|
fn type_var_constraint_value(item : @syntax.TypeVarConstraint) -> Value {
  node_value(type_var_constraint_node(item))
}

///|
fn type_var_binder_value(item : @syntax.TypeVarBinder) -> Value {
  node_value(type_var_binder_node(item))
}

///|
fn trait_method_decl_value(item : @syntax.TraitMethodDecl) -> Value {
  node_value(trait_method_decl_node(item))
}

///|
fn deriving_directive_value(item : @syntax.DerivingDirective) -> Value {
  node_value(deriving_directive_node(item))
}

///|
fn constr_decl_value(item : @syntax.ConstrDecl) -> Value {
  node_value(constr_decl_node(item))
}

///|
fn constr_param_value(item : @syntax.ConstrParam) -> Value {
  node_value(constr_param_node(item))
}

///|
fn field_decl_value(item : @syntax.FieldDecl) -> Value {
  node_value(field_decl_node(item))
}

///|
fn where_clause_value(item : @syntax.WhereClause) -> Value {
  node_value(where_clause_node(item))
}
