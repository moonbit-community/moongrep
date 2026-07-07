///|
fn node(
  kind : NodeKind,
  loc : @basic.Location,
  children : Array[(String, Node)],
) -> Node {
  let converted : Array[(String?, Node)] = []
  children.each(fn(child) {
    let (name, value) = child
    converted.push((Some(name), value))
  })
  { kind, loc, children: FixedArray::from_array(converted) }
}

///|
fn node0(kind : NodeKind, loc : @basic.Location) -> Node {
  node(kind, loc, [])
}

///|
fn node1(kind : NodeKind, loc : @basic.Location, value : Node) -> Node {
  node(kind, loc, [("value", value)])
}

///|
fn node_value(n : Node) -> Node {
  n
}

///|
fn leaf_value(payload : NodePayload) -> Node {
  { kind: Leaf(payload), loc: @syntax.no_location, children: [] }
}

///|
fn null_value() -> Node {
  leaf_value(PNull)
}

///|
fn string_value(s : String) -> Node {
  leaf_value(PString(s))
}

///|
fn bool_value(b : Bool) -> Node {
  leaf_value(PBool(b))
}

///|
fn number_value(n : Double) -> Node {
  leaf_value(PNumber(n, repr=None))
}

///|
fn[T] option_value(opt : T?, f : (T) -> Node) -> Node {
  if opt is Some(value) {
    f(value)
  } else {
    null_value()
  }
}

///|
fn[T] list_children(
  list : @list.List[T],
  f : (T) -> Node,
) -> FixedArray[(String?, Node)] {
  let values : Array[(String?, Node)] = []
  list.each(fn(item) { values.push((None, f(item))) })
  FixedArray::from_array(values)
}

///|
fn[T] list_node(
  kind : NodeKind,
  loc : @basic.Location,
  list : @list.List[T],
  f : (T) -> Node,
) -> Node {
  { kind, loc, children: list_children(list, f) }
}

///|
fn empty_list_node(kind : NodeKind, loc : @basic.Location) -> Node {
  { kind, loc, children: [] }
}

///|
fn doc_string_value(doc : @syntax.DocString) -> Node {
  let mut docs = doc.content
  match docs {
    Empty => string_value("")
    More(head, tail~) => {
      docs = tail
      let buf = StringBuilder::new()
      buf.write_string(head)
      for item in docs {
        buf.write_string("\n")
        buf.write_string(item)
      } nobreak {
        string_value(buf.to_string())
      }
    }
  }
}

///|
fn string_literal_value(s : String) -> Node {
  string_value(s)
}

///|
fn char_literal_value(c : String) -> Node {
  string_value(c)
}

///|
fn byte_literal_value(b : String) -> Node {
  string_value(b)
}

///|
fn bytes_literal_value(b : String) -> Node {
  string_value(b)
}

///|
fn long_ident_node(item : @syntax.LongIdent, loc : @basic.Location) -> Node {
  match item {
    Ident(name~) => node1(LongIdent_Ident, loc, string_value(name))
    Dot(pkg~, id~) =>
      node(LongIdent_Dot, loc, [
        ("pkg", string_value(pkg)),
        ("id", string_value(id)),
      ])
  }
}

///|
fn constr_id_node(item : @syntax.ConstrId) -> Node {
  node(ConstrId, item.loc, [
    ("id", node_value(long_ident_node(item.id, item.loc))),
  ])
}

///|
fn func_stubs_node(item : @syntax.FuncStubs, loc : @basic.Location) -> Node {
  match item {
    Import(module_name~, func_name~, language~) =>
      node(FuncStubs_Import, loc, [
        ("module_name", string_literal_value(module_name)),
        ("func_name", string_literal_value(func_name)),
        ("language", option_value(language, string_literal_value)),
      ])
    Embedded(language~, code~) =>
      node(FuncStubs_Embedded, loc, [
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
      node1(EmbeddedCode_CodeString, loc, string_literal_value(s))
    CodeMultilineString(strings) =>
      node1(
        EmbeddedCode_CodeMultilineString,
        loc,
        node_value(
          list_node(
            EmbeddedCode_CodeMultilineString_LiteralList,
            loc,
            strings,
            string_value,
          ),
        ),
      )
  }
}

///|
fn trait_method_decl_node(item : @syntax.TraitMethodDecl) -> Node {
  node(TraitMethodDecl, item.loc, [
    ("name", node_value(binder_node(item.name))),
    ("has_error", null_value()),
    ("is_async", option_value(item.is_async, async_value)),
    (
      "quantifiers",
      node_value(
        list_node(
          TraitMethodDecl_QuantifierList,
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
          TraitMethodDecl_ParamList,
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
        node_value(node0(TraitMethodDecl_HasDefault, loc))
      }),
    ),
    (
      "attrs",
      node_value(
        list_node(
          TraitMethodDecl_AttrList,
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
  node(TypeVarConstraint, item.loc, [
    ("trait", node_value(long_ident_node(item.trait_, item.loc))),
  ])
}

///|
fn type_decl_binder_node(item : @syntax.TypeDeclBinder) -> Node {
  node(TypeDeclBinder, item.loc, [
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
    Empty => default
    More(item, tail=Empty) => loc_of(item)
    More(first, tail~) => loc_of(first).merge(loc_of(tail.last().unwrap()))
  }
}

///|
fn type_desc_node(item : @syntax.TypeDesc, loc : @basic.Location) -> Node {
  match item {
    Abstract => node0(TypeDesc_Abstract, loc)
    ExtensibleEnum(constrs) => {
      let constrs_loc = list_loc_or(constrs, loc, fn(constr) { constr.loc })
      node1(
        TypeDesc_ExtensibleEnum,
        constrs_loc,
        node_value(
          list_node(
            TypeDesc_ExtensibleEnum_ConstrList,
            constrs_loc,
            constrs,
            constr_decl_value,
          ),
        ),
      )
    }
    Error(exception_decl) =>
      node1(
        TypeDesc_Error,
        loc,
        node_value(exception_decl_node(exception_decl, loc)),
      )
    Variant(constrs) => {
      let constrs_loc = list_loc_or(constrs, loc, fn(constr) { constr.loc })
      node1(
        TypeDesc_Variant,
        constrs_loc,
        node_value(
          list_node(
            TypeDesc_Variant_ConstrList,
            constrs_loc,
            constrs,
            constr_decl_value,
          ),
        ),
      )
    }
    ExtendEnum(target~, constructors~) => {
      let constrs_loc = list_loc_or(constructors, loc, fn(constr) { constr.loc })
      node(TypeDesc_ExtendEnum, loc, [
        ("target", node_value(type_name_node(target))),
        (
          "constructors",
          node_value(
            list_node(
              TypeDesc_ExtendEnum_ConstrList,
              constrs_loc,
              constructors,
              constr_decl_value,
            ),
          ),
        ),
      ])
    }
    Record(fields~, constr_decl~) => {
      let children : Array[(String, Node)] = [
        (
          "value",
          node_value(
            list_node(TypeDesc_Record_FieldList, loc, fields, field_decl_value),
          ),
        ),
      ]
      if constr_decl is Some(decl) {
        children.push(("constr_decl", node_value(fun_decl_node(decl))))
      }
      node(TypeDesc_Record, loc, children)
    }
    TupleStruct(tys) => {
      let tys_loc = list_loc_or(tys, loc, fn(ty) { ty.loc() })
      node1(
        TypeDesc_TupleStruct,
        tys_loc,
        node_value(
          list_node(TypeDesc_TupleStruct_TypeList, tys_loc, tys, type_value),
        ),
      )
    }
    Alias(ty) => node1(TypeDesc_Alias, ty.loc(), type_value(ty))
  }
}

///|
fn deriving_directive_node(item : @syntax.DerivingDirective) -> Node {
  node(DerivingDirective, item.loc, [
    ("type_name", node_value(type_name_node(item.type_name))),
    (
      "args",
      node_value(
        list_node(
          DerivingDirective_ArgList,
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
    NoPayload => node0(ExceptionDecl_NoPayload, loc)
    EnumPayload(constrs) =>
      node1(
        ExceptionDecl_EnumPayload,
        loc,
        node_value(
          list_node(
            ExceptionDecl_EnumPayload_ConstrList,
            loc,
            constrs,
            constr_decl_value,
          ),
        ),
      )
  }
}

///|
fn constr_decl_node(item : @syntax.ConstrDecl) -> Node {
  node(ConstrDecl, item.loc, [
    ("name", node_value(constr_name_node(item.name))),
    (
      "args",
      option_value(item.args, fn(args) {
        node_value(
          list_node(ConstrDecl_ArgList, item.loc, args, constr_param_value),
        )
      }),
    ),
    (
      "tag",
      option_value(item.tag, fn(tag) {
        let (s, l) = tag
        node_value(node1(ConstrDecl_Tag, l, string_value(s)))
      }),
    ),
    (
      "attrs",
      node_value(
        list_node(ConstrDecl_AttrList, item.loc, item.attrs, attribute_value),
      ),
    ),
    ("doc", doc_string_value(item.doc)),
  ])
}

///|
fn constr_name_node(item : @syntax.ConstrName) -> Node {
  node(ConstrName, item.loc, [("name", string_value(item.name))])
}

///|
fn constr_param_node(item : @syntax.ConstrParam) -> Node {
  let loc = if item.label is Some(label) {
    label.loc.merge(item.ty.loc())
  } else {
    item.ty.loc()
  }
  node(ConstrParam, loc, [
    ("ty", type_value(item.ty)),
    ("mut", bool_value(item.mut_)),
    ("label", option_value(item.label, label_value)),
  ])
}

///|
fn field_decl_node(item : @syntax.FieldDecl) -> Node {
  node(FieldDecl, item.loc, [
    ("name", node_value(field_name_node(item.name))),
    ("ty", type_value(item.ty)),
    ("mut", bool_value(item.mut_)),
    ("vis", node_value(visibility_node(item.vis, item.loc))),
    (
      "attrs",
      node_value(
        list_node(FieldDecl_AttrList, item.loc, item.attrs, attribute_value),
      ),
    ),
    ("doc", doc_string_value(item.doc)),
  ])
}

///|
fn field_name_node(item : @syntax.FieldName) -> Node {
  node(FieldName, item.loc, [("label", string_value(item.label))])
}

///|
fn where_clause_node(item : @syntax.WhereClause) -> Node {
  node(WhereClause, item.loc, [
    (
      "fields",
      node_value(
        list_node(WhereClause_FieldList, item.loc, item.fields, field_def_value),
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
      node(Expr_Apply, loc, [
        ("func", expr_value(func)),
        (
          "args",
          node_value(
            list_node(Expr_Apply_ArgumentList, loc, args, argument_value),
          ),
        ),
        ("attr", node_value(apply_attr_node(loc))),
      ])
    Infix(op~, lhs~, rhs~, loc~) =>
      node(Expr_Infix, loc, [
        ("op", node_value(var_node(op))),
        ("lhs", expr_value(lhs)),
        ("rhs", expr_value(rhs)),
      ])
    Unary(op~, expr~, loc~) =>
      node(Expr_Unary, loc, [
        ("op", node_value(var_node(op))),
        ("expr", expr_value(expr)),
      ])
    Array(exprs~, is_iter~, loc~) =>
      node(Expr_Array, loc, [
        (
          "exprs",
          node_value(list_node(Expr_Array_ExprList, loc, exprs, expr_value)),
        ),
        ("is_iter", bool_value(is_iter)),
      ])
    ArraySpread(elems~, is_iter~, loc~) =>
      node(Expr_ArraySpread, loc, [
        (
          "elems",
          node_value(
            list_node(
              Expr_ArraySpread_ElemList,
              loc,
              elems,
              spreadable_elem_value,
            ),
          ),
        ),
        ("is_iter", bool_value(is_iter)),
      ])
    ListComprehension(kind~, guard_~, body~, is_iter~, loc~) =>
      node(Expr_ListComprehension, loc, [
        ("kind", node_value(list_comprehension_kind_node(kind, loc, is_iter~))),
        ("guard", option_value(guard_, expr_value)),
        ("body", expr_value(body)),
      ])
    ArrayGet(array~, index~, loc~) =>
      node(Expr_ArrayGet, loc, [
        ("array", expr_value(array)),
        ("index", expr_value(index)),
      ])
    ArrayGetSlice(array~, start_index~, end_index~, index_loc~, loc~) => {
      ignore(index_loc)
      node(Expr_ArrayGetSlice, loc, [
        ("array", expr_value(array)),
        ("start_index", option_value(start_index, expr_value)),
        ("end_index", option_value(end_index, expr_value)),
      ])
    }
    ArraySet(array~, index~, value~, loc~) =>
      node(Expr_ArraySet, loc, [
        ("array", expr_value(array)),
        ("index", expr_value(index)),
        ("value", expr_value(value)),
      ])
    ArrayAugmentedSet(op~, array~, index~, value~, loc~) =>
      node(Expr_ArrayAugmentedSet, loc, [
        ("op", node_value(var_node(op))),
        ("array", expr_value(array)),
        ("index", expr_value(index)),
        ("value", expr_value(value)),
      ])
    Constant(c~, loc~) =>
      node(Expr_Constant, loc, [("constant", constant_value(c, loc))])
    MultilineString(elems~, loc~) =>
      node(Expr_MultilineString, loc, [
        (
          "elems",
          node_value(
            list_node(Expr_MultilineString_ElemList, loc, elems, fn(elem) {
              node_value(multiline_string_elem_node(elem, loc))
            }),
          ),
        ),
      ])
    Interp(elems~, loc~) =>
      node(Expr_Interp, loc, [
        (
          "elems",
          node_value(
            list_node(Expr_Interp_ElemList, loc, elems, interp_elem_value),
          ),
        ),
      ])
    BytesInterp(elems~, loc~) =>
      node(Expr_BytesInterp, loc, [
        (
          "elems",
          node_value(
            list_node(Expr_BytesInterp_ElemList, loc, elems, interp_elem_value),
          ),
        ),
      ])
    Constraint(expr~, ty~, loc~) =>
      node(Expr_Constraint, loc, [
        ("expr", expr_value(expr)),
        ("ty", type_value(ty)),
      ])
    Constr(constr~, loc~) =>
      node(Expr_Constr, loc, [("constr", node_value(constructor_node(constr)))])
    While(loop_cond~, loop_body~, while_else~, label~, loc~) =>
      node(Expr_While, loc, [
        ("loop_cond", expr_value(loop_cond)),
        ("loop_body", expr_value(loop_body)),
        ("while_else", option_value(while_else, expr_value)),
        ("label", option_value(label, label_value)),
      ])
    Function(func~, loc~) =>
      node(Expr_Function, loc, [("func", node_value(func_node(func)))])
    Ident(id~, loc~) =>
      node(Expr_Ident, loc, [("id", node_value(var_node(id)))])
    If(cond~, ifso~, ifnot~, loc~) =>
      node(Expr_If, loc, [
        ("cond", expr_value(cond)),
        ("ifso", expr_value(ifso)),
        ("ifnot", option_value(ifnot, expr_value)),
      ])
    Guard(cond~, otherwise~, body~, loc~) =>
      node(Expr_Guard, loc, [
        ("cond", expr_value(cond)),
        ("otherwise", option_value(otherwise, expr_value)),
        ("body", expr_value(body)),
      ])
    Is(expr~, pat~, loc~) =>
      node(Expr_Is, loc, [
        ("expr", expr_value(expr)),
        ("pat", pattern_value(pat)),
      ])
    IsLexMatch(expr~, strategy~, pat~, pat_loc~, loc~) =>
      node(Expr_IsLexmatch, loc, [
        ("expr", expr_value(expr)),
        ("strategy", option_value(strategy, label_value)),
        (
          "pat",
          node_value(
            list_node(Expr_IsLexmatch_PatternList, pat_loc, pat, fn(p) {
              node_value(lex_top_pattern_node(p, pat_loc))
            }),
          ),
        ),
      ])
    RegexMatch(expr~, pat~, bindings~, loc~) =>
      node(Expr_RegexMatch, loc, [
        ("expr", expr_value(expr)),
        ("pat", node_value(regex_pattern_node(pat))),
        (
          "bindings",
          node_value(
            list_node(Expr_RegexMatch_BindingList, loc, bindings, fn(binding) {
              let (label, binder) = binding
              node_value(
                node(Expr_RegexMatch_Binding, label.loc, [
                  ("label", label_value(label)),
                  ("binder", option_value(binder, binder_value)),
                ]),
              )
            }),
          ),
        ),
      ])
    Defer(expr~, body~, loc~) =>
      node(Expr_Defer, loc, [
        ("expr", expr_value(expr)),
        ("body", expr_value(body)),
      ])
    LetFn(name~, func~, body~, loc~) =>
      node(Expr_LetFn, loc, [
        ("name", binder_value(name)),
        ("func", node_value(func_node(func))),
        ("body", expr_value(body)),
      ])
    LetAnd(bindings~, body~, loc~) =>
      node(Expr_LetAnd, loc, [
        (
          "bindings",
          node_value(
            list_node(Expr_LetAnd_BindingList, loc, bindings, fn(binding) {
              let (binder, ty, func) = binding
              node_value(
                node(LetAnd_Binding, loc, [
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
      node(Expr_Let, loc, [
        ("pattern", pattern_value(pattern)),
        ("expr", expr_value(expr)),
        ("body", expr_value(body)),
      ])
    Sequence(exprs~, last_expr~, loc~) =>
      node(Expr_Sequence, loc, [
        (
          "exprs",
          node_value(list_node(Expr_Sequence_ExprList, loc, exprs, expr_value)),
        ),
        ("last_expr", expr_value(last_expr)),
      ])
    Tuple(exprs~, loc~) =>
      node(Expr_Tuple, loc, [
        (
          "exprs",
          node_value(list_node(Expr_Tuple_ExprList, loc, exprs, expr_value)),
        ),
      ])
    Record(type_name~, fields~, trailing~, loc~) =>
      node(Expr_Record, loc, [
        ("type_name", option_value(type_name, type_name_value)),
        (
          "fields",
          node_value(
            list_node(Expr_Record_FieldList, loc, fields, field_def_value),
          ),
        ),
        ("trailing", node_value(trailing_mark_node(trailing, loc))),
      ])
    RecordUpdate(type_name~, record~, fields~, loc~) =>
      node(Expr_RecordUpdate, loc, [
        ("type_name", option_value(type_name, type_name_value)),
        ("record", expr_value(record)),
        (
          "fields",
          node_value(
            list_node(Expr_RecordUpdate_FieldList, loc, fields, field_def_value),
          ),
        ),
      ])
    Field(record~, accessor~, loc~) =>
      node(Expr_Field, loc, [
        ("record", expr_value(record)),
        ("accessor", node_value(accessor_node(accessor))),
      ])
    Method(type_name~, method_name~, loc~) =>
      node(Expr_Method, loc, [
        ("type_name", type_name_value(type_name)),
        ("method_name", label_value(method_name)),
      ])
    DotApply(self~, method_name~, args~, return_self~, loc~) =>
      node(Expr_DotApply, loc, [
        ("self", expr_value(self)),
        ("method_name", label_value(method_name)),
        (
          "args",
          node_value(
            list_node(Expr_DotApply_ArgList, loc, args, argument_value),
          ),
        ),
        ("return_self", bool_value(return_self)),
        ("attr", node_value(apply_attr_node(loc))),
      ])
    As(expr~, trait_~, loc~) =>
      node(Expr_As, loc, [
        ("expr", expr_value(expr)),
        ("trait", type_name_value(trait_)),
      ])
    Mutate(record~, accessor~, field~, augmented_by~, loc~) =>
      node(Expr_Mutate, loc, [
        ("record", expr_value(record)),
        ("accessor", node_value(accessor_node(accessor))),
        ("field", expr_value(field)),
        ("augmented_by", option_value(augmented_by, var_value)),
      ])
    Match(expr~, cases~, match_loc~, loc~) => {
      ignore(match_loc)
      node(Expr_Match, loc, [
        ("expr", expr_value(expr)),
        (
          "cases",
          node_value(list_node(Expr_Match_CaseList, loc, cases, case_value)),
        ),
      ])
    }
    LexMatch(strategy~, expr~, match_loc~, cases~, loc~) => {
      ignore(match_loc)
      node(Expr_Lexmatch, loc, [
        ("strategy", option_value(strategy, label_value)),
        ("expr", expr_value(expr)),
        (
          "cases",
          node_value(
            list_node(Expr_Lexmatch_CaseList, loc, cases, fn(case) {
              node_value(lex_case_node(case, loc))
            }),
          ),
        ),
      ])
    }
    LexScan(expr~, match_loc~, cases~, loc~) => {
      ignore(match_loc)
      node(Expr_Lexscan, loc, [
        ("expr", expr_value(expr)),
        (
          "cases",
          node_value(
            list_node(Expr_Lexscan_CaseList, loc, cases, fn(case) {
              node_value(lex_scan_case_node(case, loc))
            }),
          ),
        ),
      ])
    }
    LetMut(binder~, ty~, expr~, body~, loc~) =>
      node(Expr_LetMut, loc, [
        ("binder", binder_value(binder)),
        ("ty", option_value(ty, type_value)),
        ("expr", expr_value(expr)),
        ("body", expr_value(body)),
      ])
    Pipe(lhs~, rhs~, loc~) =>
      node(Expr_Pipe, loc, [("lhs", expr_value(lhs)), ("rhs", expr_value(rhs))])
    RevPipe(lhs~, rhs~, loc~) =>
      node(Expr_RevPipe, loc, [
        ("lhs", expr_value(lhs)),
        ("rhs", expr_value(rhs)),
      ])
    Assign(var_~, expr~, augmented_by~, loc~) =>
      node(Expr_Assign, loc, [
        ("var", var_value(var_)),
        ("expr", expr_value(expr)),
        ("augmented_by", option_value(augmented_by, var_value)),
      ])
    Hole(loc~, kind~) =>
      node(Expr_Hole, loc, [("kind", node_value(hole_node(kind, loc)))])
    Return(return_value~, loc~) =>
      node(Expr_Return, loc, [
        ("return_value", option_value(return_value, expr_value)),
      ])
    Raise(err_value~, loc~) =>
      node(Expr_Raise, loc, [("err_value", expr_value(err_value))])
    Quantifier(kind~, binder~, binder_ty~, body~, loc~) =>
      node(Expr_Quantifier, loc, [
        ("kind", predicate_quantifier_kind_value(kind)),
        ("binder", binder_value(binder)),
        ("binder_ty", type_value(binder_ty)),
        ("body", expr_value(body)),
      ])
    Implies(lhs~, rhs~, loc~) =>
      node(Expr_Implies, loc, [
        ("lhs", expr_value(lhs)),
        ("rhs", expr_value(rhs)),
      ])
    ProofAssert(expr~, loc~) =>
      node(Expr_ProofAssert, loc, [("expr", expr_value(expr))])
    ProofLet(binder~, expr~, loc~) =>
      node(Expr_ProofLet, loc, [
        ("binder", binder_value(binder)),
        ("expr", expr_value(expr)),
      ])
    Unit(loc~, faked~) => node(Expr_Unit, loc, [("faked", bool_value(faked))])
    Break(arg~, label~, loc~) =>
      node(Expr_Break, loc, [
        ("arg", option_value(arg, expr_value)),
        ("label", option_value(label, label_value)),
      ])
    Continue(args~, label~, loc~) =>
      node(Expr_Continue, loc, [
        (
          "args",
          node_value(list_node(Expr_Continue_ExprList, loc, args, expr_value)),
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
      node(Expr_For, loc, [
        (
          "binders",
          node_value(for_binding_list_node(Expr_For_BindingList, loc, binders)),
        ),
        ("condition", option_value(condition, expr_value)),
        (
          "continue_block",
          node_value(
            for_binding_list_node(Expr_For_ContBindingList, loc, continue_block),
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
      node(Expr_ForEach, loc, [
        (
          "binders",
          node_value(
            list_node(Expr_ForEach_BinderList, loc, binders, fn(b) {
              option_value(b, binder_value)
            }),
          ),
        ),
        ("expr", expr_value(expr)),
        (
          "init",
          node_value(foreach_binding_list_node(Expr_ForEach_Init, loc, init)),
        ),
        (
          "continue_block",
          node_value(
            foreach_binding_list_node(
              Expr_ForEach_ContinueBlock,
              loc,
              continue_block,
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
      node(Expr_Try, loc, [
        ("body", expr_value(body)),
        (
          "catch",
          node_value(list_node(Expr_Try_CaseList, loc, catch_, case_value)),
        ),
        ("catch_all", bool_value(false)),
        (
          "try_else",
          option_value(try_else, fn(cases) {
            node_value(
              list_node(Expr_Try_CaseList, else_loc, cases, case_value),
            )
          }),
        ),
        ("has_try", bool_value(has_try)),
      ])
    }
    TryOperator(body~, kind~, try_loc~, loc~) => {
      ignore(try_loc)
      node(Expr_TryOperator, loc, [
        ("body", expr_value(body)),
        ("kind", node_value(try_operator_kind_node(kind, loc))),
      ])
    }
    Map(elems~, loc~) =>
      node(Expr_Map, loc, [
        (
          "elems",
          node_value(
            list_node(Expr_Map_ElemList, loc, elems, map_expr_elem_value),
          ),
        ),
      ])
    Group(expr~, group~, loc~) =>
      node(Expr_Group, loc, [
        ("expr", expr_value(expr)),
        ("group", node_value(group_node(group, loc))),
      ])
    TemplateWriting(expr~, template~, is_conditional~, loc~) =>
      node(Expr_TemplateWriting, loc, [
        ("expr", expr_value(expr)),
        ("template", expr_value(template)),
        ("is_conditional", bool_value(is_conditional)),
      ])
    StaticAssert(asserts~, body~) => {
      let loc = body.loc()
      node(Expr_StaticAssert, loc, [
        (
          "asserts",
          node_value(
            list_node(
              Expr_StaticAssert_StaticAssertionList,
              loc,
              asserts,
              static_assertion_value,
            ),
          ),
        ),
        ("body", expr_value(body)),
      ])
    }
  }
}

///|
fn expr_value(expr : @syntax.Expr) -> Node {
  node_value(expr_node(expr))
}

///|
fn parameter_node(item : @syntax.Parameter) -> Node {
  match item {
    DiscardPositional(ty~, loc~) =>
      node(Parameter_DiscardPositional, loc, [
        ("ty", option_value(ty, type_value)),
      ])
    Positional(binder~, ty~) => {
      let loc = if ty is Some(ty) {
        binder.loc.merge(ty.loc())
      } else {
        binder.loc
      }
      node(Parameter_Positional, loc, [
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
      node(Parameter_Labelled, loc, [
        ("binder", binder_value(binder)),
        ("ty", option_value(ty, type_value)),
      ])
    }
    Optional(binder~, default~, ty~) => {
      let loc = binder.loc.merge(default.loc())
      node(Parameter_Optional, loc, [
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
      node(Parameter_QuestionOptional, loc, [
        ("binder", binder_value(binder)),
        ("ty", option_value(ty, type_value)),
      ])
    }
  }
}

///|
fn parameter_value(parameter : @syntax.Parameter) -> Node {
  node_value(parameter_node(parameter))
}

///|
fn test_name_value(item : @syntax.TestName) -> Node {
  option_value(item, fn(test_name) {
    let (s, loc) = test_name
    node_value(node1(TestName, loc, string_literal_value(s)))
  })
}

///|
fn attribute_node(item : @attribute.Attribute) -> Node {
  node(Attribute, item.loc, [("raw", string_value(item.raw))])
}

///|
fn attribute_value(attr : @attribute.Attribute) -> Node {
  node_value(attribute_node(attr))
}

///|
fn type_decl_node(item : @syntax.TypeDecl) -> Node {
  node(TypeDecl, item.loc, [
    ("tycon", string_value(item.tycon)),
    (
      "params",
      node_value(
        list_node(
          TypeDecl_ParamList,
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
        list_node(TypeDecl_AttrList, item.loc, item.attrs, attribute_value),
      ),
    ),
    ("doc", doc_string_value(item.doc)),
    ("type_vis", node_value(visibility_node(item.type_vis, item.loc))),
    ("is_declare", bool_value(item.is_declare)),
    (
      "deriving",
      node_value(
        list_node(
          TypeDecl_DerivingList,
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
  node(FunDecl, item.loc, [
    ("type_name", option_value(item.type_name, type_name_value)),
    ("name", binder_value(item.name)),
    ("has_error", null_value()),
    ("is_async", option_value(item.is_async, async_value)),
    (
      "decl_params",
      option_value(item.decl_params, fn(params) {
        node_value(
          list_node(
            FunDecl_ParameterList,
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
          FunDecl_QuantifierList,
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
          FunDecl_AttrList,
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
      node(DeclBody_DeclBody, loc, [
        (
          "local_types",
          node_value(empty_list_node(DeclBody_DeclBody_LocalTypeList, loc)),
        ),
        ("expr", expr_value(expr)),
      ])
    DeclStubs(stubs) =>
      node1(DeclBody_DeclStubs, loc, node_value(func_stubs_node(stubs, loc)))
    DeclNone => node0(DeclBody_DeclNone, loc)
  }
}

///|
fn label_node(item : @syntax.Label) -> Node {
  node(Label, item.loc, [("name", string_value(item.name))])
}

///|
fn label_value(label : @syntax.Label) -> Node {
  node_value(label_node(label))
}

///|
fn alias_target_node(item : @syntax.AliasTarget) -> Node {
  node(AliasTarget, item.loc(), [
    ("binder", binder_value(item.binder)),
    ("target", option_value(item.target, label_value)),
  ])
}

///|
fn binder_node(item : @syntax.Binder) -> Node {
  node(Binder, item.loc, [("name", string_value(item.name))])
}

///|
fn binder_value(binder : @syntax.Binder) -> Node {
  node_value(binder_node(binder))
}

///|
pub fn from_type(item : @syntax.Type) -> Node {
  type_node(item)
}

///|
fn type_node(item : @syntax.Type) -> Node {
  match item {
    Any(loc~) => node0(Type_Any, loc)
    Arrow(args~, res~, err~, is_async~, loc~) =>
      node(Type_Arrow, loc, [
        (
          "args",
          node_value(list_node(Type_Arrow_ArgList, loc, args, type_value)),
        ),
        ("res", type_value(res)),
        ("err", node_value(error_type_node(err, loc))),
        ("is_async", option_value(is_async, async_value)),
      ])
    Tuple(tys~, loc~) =>
      node(Type_Tuple, loc, [
        (
          "tys",
          node_value(list_node(Type_Tuple_TypeList, loc, tys, type_value)),
        ),
      ])
    Name(constr_id~, tys~, loc~) =>
      node(Type_Name, loc, [
        ("constr_id", node_value(constr_id_node(constr_id))),
        ("tys", node_value(list_node(Type_Name_TypeList, loc, tys, type_value))),
      ])
    Option(ty~, loc~, question_loc~) => {
      ignore(question_loc)
      node(Type_Option, loc, [("ty", type_value(ty))])
    }
    Object(constr_id) =>
      node1(Type_Object, constr_id.loc, node_value(constr_id_node(constr_id)))
  }
}

///|
fn type_value(ty : @syntax.Type) -> Node {
  node_value(type_node(ty))
}

///|
fn visibility_node(item : @syntax.Visibility, loc : @basic.Location) -> Node {
  match item {
    Default => node0(Visibility_Default, loc)
    Priv(loc~) => node0(Visibility_Priv, loc)
    Pub(attr~, loc~) =>
      node(Visibility_Pub, loc, [("attr", option_value(attr, string_value))])
  }
}

///|
fn trait_decl_node(item : @syntax.TraitDecl) -> Node {
  node(TraitDecl, item.loc, [
    ("name", binder_value(item.name)),
    (
      "supers",
      node_value(
        list_node(
          TraitDecl_SuperList,
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
          TraitDecl_MethodList,
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
        list_node(TraitDecl_AttrList, item.loc, item.attrs, attribute_value),
      ),
    ),
    ("doc", doc_string_value(item.doc)),
  ])
}

///|
fn type_name_node(item : @syntax.TypeName) -> Node {
  node(TypeName, item.loc, [
    ("name", node_value(long_ident_node(item.name, item.loc))),
    ("is_object", bool_value(item.is_object)),
  ])
}

///|
fn type_name_value(type_name : @syntax.TypeName) -> Node {
  node_value(type_name_node(type_name))
}

///|
fn type_var_binder_node(item : @syntax.TypeVarBinder) -> Node {
  let constraints_loc = list_loc_or(item.constraints, item.name_loc, fn(c) {
    c.loc
  })
  let loc = item.name_loc.merge(constraints_loc)
  node(TypeVarBinder, loc, [
    ("name", string_value(item.name)),
    (
      "constraints",
      node_value(
        list_node(
          TypeVarBinder_TypeVarConstraintList,
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
      node(ErrorType_ErrorType, ty.loc(), [("ty", type_value(ty))])
    DefaultErrorType(loc~) => node0(ErrorType_DefaultErrorType, loc)
    NoErrorType => node0(ErrorType_NoErrorType, loc)
    Noraise(loc~) => node0(ErrorType_Noraise, loc)
    MaybeError(ty~) =>
      node(ErrorType_MaybeError, ty.loc(), [("ty", type_value(ty))])
  }
}

///|
fn using_name_value(item : (@syntax.AliasTarget, @syntax.UsingKind)) -> Node {
  let (target, kind) = item
  let loc = target.loc()
  let kind_str = match kind {
    Value => "value"
    Type => "type"
    Trait => "trait"
  }
  node_value(
    node(UsingName, loc, [
      ("name", node_value(alias_target_node(target))),
      ("kind", string_value(kind_str)),
    ]),
  )
}

///|
fn argument_node(item : @syntax.Argument) -> Node {
  node(Argument, item.value.loc(), [
    ("value", expr_value(item.value)),
    ("kind", node_value(argument_kind_node(item.kind, item.value.loc()))),
  ])
}

///|
fn argument_value(argument : @syntax.Argument) -> Node {
  node_value(argument_node(argument))
}

///|
fn argument_kind_node(
  item : @syntax.ArgumentKind,
  loc : @basic.Location,
) -> Node {
  match item {
    Positional => node0(ArgumentKind_Positional, loc)
    Labelled(label) =>
      node1(ArgumentKind_Labelled, label.loc, label_value(label))
    LabelledPun(label) =>
      node1(ArgumentKind_LabelledPun, label.loc, label_value(label))
    LabelledOption(label~, question_loc~) => {
      ignore(question_loc)
      node(ArgumentKind_LabelledOption, label.loc, [
        ("label", label_value(label)),
      ])
    }
    LabelledOptionPun(label~, question_loc~) => {
      ignore(question_loc)
      node(ArgumentKind_LabelledOptionPun, label.loc, [
        ("label", label_value(label)),
      ])
    }
  }
}

///|
fn apply_attr_node(loc : @basic.Location) -> Node {
  node0(ApplyAttr_NoAttr, loc)
}

///|
fn var_node(item : @syntax.Var) -> Node {
  node(Var, item.loc, [
    ("name", node_value(long_ident_node(item.name, item.loc))),
  ])
}

///|
fn var_value(var_ : @syntax.Var) -> Node {
  node_value(var_node(var_))
}

///|
fn constant_value(item : @syntax.Constant, loc : @basic.Location) -> Node {
  node_value(constant_node(item, loc))
}

///|
fn constant_node(item : @syntax.Constant, loc : @basic.Location) -> Node {
  match item {
    Bool(b) => node1(Constant_Bool, loc, bool_value(b))
    Byte(b) => node1(Constant_Byte, loc, byte_literal_value(b))
    Bytes(b) => node1(Constant_Bytes, loc, bytes_literal_value(b))
    Char(c) => node1(Constant_Char, loc, char_literal_value(c))
    Int(s) => node1(Constant_Int, loc, string_value(s))
    Int64(s) => node1(Constant_Int64, loc, string_value(s))
    UInt(s) => node1(Constant_UInt, loc, string_value(s))
    UInt64(s) => node1(Constant_UInt64, loc, string_value(s))
    Float(s) => node1(Constant_Float, loc, string_value(s))
    Double(s) => node1(Constant_Double, loc, string_value(s))
    String(s) => node1(Constant_String, loc, string_literal_value(s))
    Regex(s) => node1(Constant_Regex, loc, string_literal_value(s))
    BigInt(s) => node1(Constant_BigInt, loc, string_value(s))
  }
}

///|
fn spreadable_elem_node(item : @syntax.SpreadableElem) -> Node {
  match item {
    Regular(expr) => node1(SpreadableElem_Regular, expr.loc(), expr_value(expr))
    Spread(expr~, loc~) =>
      node(SpreadableElem_Spread, loc, [("expr", expr_value(expr))])
  }
}

///|
fn spreadable_elem_value(elem : @syntax.SpreadableElem) -> Node {
  node_value(spreadable_elem_node(elem))
}

///|
fn multiline_string_elem_node(
  item : @syntax.MultilineStringElem,
  loc : @basic.Location,
) -> Node {
  match item {
    String(s) => node1(MultilineString_String, loc, string_value(s))
    Interp(elems) =>
      node1(
        MultilineString_Interp,
        loc,
        node_value(
          list_node(
            MultilineString_Interp_ElemList,
            loc,
            elems,
            interp_elem_value,
          ),
        ),
      )
  }
}

///|
fn interp_elem_node(item : @syntax.InterpElem) -> Node {
  match item {
    Literal(repr~, loc~) =>
      node(InterpElem_Literal, loc, [("repr", string_literal_value(repr))])
    Expr(expr~, loc~) =>
      node(InterpElem_Expr, loc, [("expr", expr_value(expr))])
    Source({ source, loc }) =>
      node(InterpElem_Source, loc, [("source", string_value(source))])
  }
}

///|
fn interp_elem_value(elem : @syntax.InterpElem) -> Node {
  node_value(interp_elem_node(elem))
}

///|
fn constructor_node(item : @syntax.Constructor) -> Node {
  node(Constructor, item.loc, [
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
        ConstructorExtraInfo_TypeName,
        type_name.loc,
        type_name_value(type_name),
      )
    TypeNameWithConstrPackage(type_name~, pkg~) =>
      node(ConstructorExtraInfo_TypeNameWithConstrPackage, loc, [
        ("type_name", type_name_value(type_name)),
        ("pkg", string_value(pkg)),
      ])
    Package(s) => node1(ConstructorExtraInfo_Package, loc, string_value(s))
    NoExtraInfo => node0(ConstructorExtraInfo_NoExtraInfo, loc)
  }
}

///|
fn func_node(item : @syntax.Func) -> Node {
  node(Func_Lambda, item.loc, [
    (
      "parameters",
      node_value(
        list_node(
          Func_Lambda_ParameterList,
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
    ("has_error", null_value()),
    ("is_async", option_value(item.is_async, async_value)),
  ])
}

///|
fn fn_kind_node(item : @syntax.FnKind, loc : @basic.Location) -> Node {
  match item {
    Lambda => node0(FnKind_Lambda, loc)
    Arrow => node0(FnKind_Arrow, loc)
  }
}

///|
fn field_def_node(item : @syntax.FieldDef) -> Node {
  node(FieldDef, item.loc, [
    ("label", label_value(item.label)),
    ("expr", expr_value(item.expr)),
    ("is_pun", bool_value(item.is_pun)),
  ])
}

///|
fn field_def_value(field : @syntax.FieldDef) -> Node {
  node_value(field_def_node(field))
}

///|
fn trailing_mark_node(
  item : @syntax.TrailingMark,
  loc : @basic.Location,
) -> Node {
  match item {
    Comma => node0(Trailing_Comma, loc)
    Semi => node0(Trailing_Semi, loc)
    None => node0(Trailing_None, loc)
  }
}

///|
fn accessor_node(item : @syntax.Accessor) -> Node {
  match item {
    Label(label) => node1(Accessor_Label, label.loc, label_value(label))
    Index(tuple_index~, loc~) =>
      node(Accessor_Index, loc, [
        ("tuple_index", number_value(tuple_index.to_double())),
      ])
    Newtype(loc~) => node0(Accessor_Newtype, loc)
  }
}

///|
fn case_node(item : @syntax.Case) -> Node {
  let pattern_loc = item.pattern.loc()
  let body_loc = item.body.loc()
  let loc = pattern_loc.merge(body_loc)
  node(Case, loc, [
    ("pattern", pattern_value(item.pattern)),
    ("guard", option_value(item.guard_, expr_value)),
    ("body", expr_value(item.body)),
  ])
}

///|
fn case_value(case : @syntax.Case) -> Node {
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
      node(Pattern_Alias, loc, [
        ("pat", pattern_value(pat)),
        ("alias", binder_value(alias_)),
      ])
    Any(loc~) => node0(Pattern_Any, loc)
    Array(pats~, loc~) =>
      node(Pattern_Array, loc, [
        ("pats", node_value(array_patterns_node(pats, loc))),
      ])
    Constant(c~, loc~) =>
      node(Pattern_Constant, loc, [("constant", constant_value(c, loc))])
    Constraint(pat~, ty~, loc~) =>
      node(Pattern_Constraint, loc, [
        ("pat", pattern_value(pat)),
        ("ty", type_value(ty)),
      ])
    Constr(constr~, args~, is_open~, loc~) =>
      node(Pattern_Constr, loc, [
        ("constr", node_value(constructor_node(constr))),
        (
          "args",
          option_value(args, fn(args) {
            node_value(
              list_node(Pattern_Constr_ArgList, loc, args, constr_pat_arg_value),
            )
          }),
        ),
        ("is_open", bool_value(is_open)),
      ])
    Or(pat1~, pat2~, loc~) =>
      node(Pattern_Or, loc, [
        ("pat1", pattern_value(pat1)),
        ("pat2", pattern_value(pat2)),
      ])
    Tuple(pats~, loc~) =>
      node(Pattern_Tuple, loc, [
        (
          "pats",
          node_value(
            list_node(Pattern_Tuple_PatternList, loc, pats, pattern_value),
          ),
        ),
      ])
    Var(binder) => node1(Pattern_Var, binder.loc, binder_value(binder))
    Record(fields~, is_closed~, loc~) =>
      node(Pattern_Record, loc, [
        (
          "fields",
          node_value(
            list_node(Pattern_Record_FieldList, loc, fields, field_pat_value),
          ),
        ),
        ("is_closed", bool_value(is_closed)),
      ])
    Map(elems~, is_closed~, loc~) =>
      node(Pattern_Map, loc, [
        (
          "elems",
          node_value(
            list_node(Pattern_Map_ElemList, loc, elems, map_pat_elem_value),
          ),
        ),
        ("is_closed", bool_value(is_closed)),
      ])
    Range(lhs~, rhs~, kind~, loc~) =>
      node(Pattern_Range, loc, [
        ("lhs", pattern_value(lhs)),
        ("rhs", pattern_value(rhs)),
        ("kind", node_value(range_kind_node(kind, loc))),
      ])
    SpecialConstr(binder~, args~, loc~) =>
      node(Pattern_SpecialConstr, loc, [
        ("binder", binder_value(binder)),
        (
          "args",
          node_value(
            list_node(
              Pattern_SpecialConstr_ArgList,
              loc,
              args,
              constr_pat_arg_value,
            ),
          ),
        ),
      ])
  }
}

///|
fn pattern_value(pattern : @syntax.Pattern) -> Node {
  node_value(pattern_node(pattern))
}

///|
fn range_kind_node(item : @syntax.RangeKind, loc : @basic.Location) -> Node {
  match item {
    Inclusive | InclusiveMissingEqual => node0(RangeKind_Inclusive, loc)
    Exclusive => node0(RangeKind_Exclusive, loc)
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
        ArrayPatterns_Closed,
        loc,
        node_value(
          list_node(
            ArrayPatterns_Closed_PatternList,
            loc,
            pats,
            array_pattern_value,
          ),
        ),
      )
    Open(pats1, pats2, binder) =>
      node(ArrayPatterns_Open, loc, [
        (
          "0",
          node_value(
            list_node(
              ArrayPatterns_Open_LPatternList,
              loc,
              pats1,
              array_pattern_value,
            ),
          ),
        ),
        (
          "1",
          node_value(
            list_node(
              ArrayPatterns_Open_RPatternList,
              loc,
              pats2,
              array_pattern_value,
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
      node1(ArrayPattern_Pattern, pattern.loc(), pattern_value(pattern))
    StringSpread(str~, loc~) =>
      node(ArrayPattern_StringSpread, loc, [("str", string_literal_value(str))])
    BytesSpread(bytes~, loc~) =>
      node(ArrayPattern_BytesSpread, loc, [
        ("bytes", bytes_literal_value(bytes)),
      ])
    ConstSpread(binder~, pkg~, loc~) =>
      node(ArrayPattern_ConstSpread, loc, [
        ("binder", binder_value(binder)),
        ("pkg", option_value(pkg, string_value)),
      ])
  }
}

///|
fn array_pattern_value(pattern : @syntax.ArrayPattern) -> Node {
  node_value(array_pattern_node(pattern))
}

///|
fn dot_dot_binder_node(
  item : @syntax.DotDotBinder,
  loc : @basic.Location,
) -> Node {
  match item {
    Underscore => node0(DotDotBinder_Underscore, loc)
    NoBinder => node0(DotDotBinder_NoBinder, loc)
    BinderAs(binder) =>
      node1(DotDotBinder_BinderAs, binder.loc, binder_value(binder))
    Binder(binder) =>
      node1(DotDotBinder_Binder, binder.loc, binder_value(binder))
  }
}

///|
fn constr_pat_arg_node(item : @syntax.ConstrPatArg) -> Node {
  node(ConstrPatArg, item.pat.loc(), [
    ("pat", pattern_value(item.pat)),
    ("kind", node_value(argument_kind_node(item.kind, item.pat.loc()))),
  ])
}

///|
fn constr_pat_arg_value(arg : @syntax.ConstrPatArg) -> Node {
  node_value(constr_pat_arg_node(arg))
}

///|
fn field_pat_node(item : @syntax.FieldPat) -> Node {
  node(FieldPat, item.loc, [
    ("label", label_value(item.label)),
    ("pattern", pattern_value(item.pattern)),
    ("is_pun", bool_value(item.is_pun)),
  ])
}

///|
fn field_pat_value(field : @syntax.FieldPat) -> Node {
  node_value(field_pat_node(field))
}

///|
fn map_pat_elem_node(item : @syntax.MapPatElem) -> Node {
  node(MapPatElem, item.loc, [
    ("key", constant_value(item.key, item.key_loc)),
    ("pat", pattern_value(item.pat)),
    ("match_absent", bool_value(item.match_absent)),
  ])
}

///|
fn map_pat_elem_value(elem : @syntax.MapPatElem) -> Node {
  node_value(map_pat_elem_node(elem))
}

///|
fn map_expr_elem_node(item : @syntax.MapExprElem) -> Node {
  node(MapExprElem, item.loc, [
    ("key", constant_value(item.key, item.key_loc)),
    ("expr", expr_value(item.expr)),
  ])
}

///|
fn map_expr_elem_value(elem : @syntax.MapExprElem) -> Node {
  node_value(map_expr_elem_node(elem))
}

///|
fn static_assertion_node(item : @syntax.StaticAssertion) -> Node {
  node(StaticAssertion, item.loc, [
    ("ty", type_value(item.ty)),
    ("trait", node_value(long_ident_node(item.trait_, item.loc))),
    ("msg", string_value(item.msg)),
  ])
}

///|
fn static_assertion_value(assertion : @syntax.StaticAssertion) -> Node {
  node_value(static_assertion_node(assertion))
}

///|
fn lex_case_node(item : @syntax.LexCase, loc : @basic.Location) -> Node {
  node(LexCase, loc, [
    (
      "pat",
      node_value(
        list_node(LexCase_PatternList, item.pat_loc, item.pat, fn(ltp) {
          node_value(lex_top_pattern_node(ltp, item.pat_loc))
        }),
      ),
    ),
    ("guard", option_value(item.guard_, expr_value)),
    ("body", expr_value(item.body)),
  ])
}

///|
fn lex_scan_case_node(
  item : @syntax.LexScanCase,
  loc : @basic.Location,
) -> Node {
  node(LexScanCase, loc, [
    ("pat", node_value(lex_scan_case_pattern_node(item.pat))),
    ("guard", option_value(item.guard_, expr_value)),
    ("body", expr_value(item.body)),
  ])
}

///|
fn lex_scan_case_pattern_node(item : @syntax.LexScanCasePattern) -> Node {
  match item {
    Pattern(pat) => {
      let pat_node = regex_pattern_node(pat)
      node1(LexScanCasePattern_Pattern, pat_node.loc, node_value(pat_node))
    }
    Binder(binder) =>
      node1(LexScanCasePattern_Binder, binder.loc, binder_value(binder))
    Wildcard(loc~) => node0(LexScanCasePattern_Wildcard, loc)
  }
}

///|
fn lex_top_pattern_node(
  item : @syntax.LexTopPattern,
  loc : @basic.Location,
) -> Node {
  match item {
    Pattern(pat) =>
      node1(LexTopPattern_Pattern, loc, node_value(lex_pattern_node(pat)))
    Binder(binder) => node1(LexTopPattern_Binder, loc, binder_value(binder))
    Wildcard(loc~) => node0(LexTopPattern_Wildcard, loc)
  }
}

///|
fn lex_pattern_node(item : @syntax.LexPattern) -> Node {
  match item {
    Regex(lit~, offset~, loc~) =>
      node(LexPattern_Regex, loc, [
        ("lit", string_value(lit)),
        ("offset", number_value(offset.to_double())),
      ])
    RegexInterp(elems~, loc~) =>
      node(LexPattern_RegexInterp, loc, [
        (
          "elems",
          node_value(
            list_node(
              LexPattern_RegexInterp_InterpElemList,
              loc,
              elems,
              interp_elem_value,
            ),
          ),
        ),
      ])
    ConstantRef(lid~, loc~) =>
      node(LexPattern_ConstantRef, loc, [
        ("lid", node_value(long_ident_node(lid, loc))),
      ])
    Alias(pat~, binder~, loc~) =>
      node(LexPattern_Alias, loc, [
        ("pat", node_value(lex_pattern_node(pat))),
        ("binder", binder_value(binder)),
      ])
    Sequence(pats~, loc~) =>
      node(LexPattern_Sequence, loc, [
        (
          "pats",
          node_value(
            list_node(
              LexPattern_Sequence_PatternList,
              loc,
              pats,
              lex_pattern_value,
            ),
          ),
        ),
      ])
  }
}

///|
fn lex_pattern_value(pattern : @syntax.LexPattern) -> Node {
  node_value(lex_pattern_node(pattern))
}

///|
fn regex_pattern_node(item : @syntax.RegexPattern) -> Node {
  match item {
    Literal(lit~, loc~) =>
      node(RegexPattern_Literal, loc, [("lit", string_value(lit))])
    Reference(lid~, loc~) =>
      node(RegexPattern_Reference, loc, [
        ("lid", node_value(long_ident_node(lid, loc))),
      ])
    Sequence(pat1~, pat2~, loc~) =>
      node(RegexPattern_Sequence, loc, [
        ("pat1", node_value(regex_pattern_node(pat1))),
        ("pat2", node_value(regex_pattern_node(pat2))),
      ])
    Alternation(pat1~, pat2~, loc~) =>
      node(RegexPattern_Alternation, loc, [
        ("pat1", node_value(regex_pattern_node(pat1))),
        ("pat2", node_value(regex_pattern_node(pat2))),
      ])
    Alias(pat~, binder~, loc~) =>
      node(RegexPattern_Alias, loc, [
        ("pat", node_value(regex_pattern_node(pat))),
        ("binder", binder_value(binder)),
      ])
  }
}

///|
fn predicate_quantifier_kind_value(
  item : @syntax.PredicateQuantifierKind,
) -> Node {
  match item {
    Forall => string_value("forall")
    Exists => string_value("exists")
  }
}

///|
fn list_comprehension_kind_node(
  item : @syntax.ListComprehensionKind,
  loc : @basic.Location,
  is_iter~ : Bool,
) -> Node {
  match item {
    Foreach(binders~, expr~, init~, continue_block~) =>
      node(Expr_ListComprehension_Kind_Foreach, loc, [
        (
          "binders",
          node_value(
            list_node(Expr_ForEach_BinderList, loc, binders, fn(b) {
              option_value(b, binder_value)
            }),
          ),
        ),
        ("expr", expr_value(expr)),
        (
          "init",
          node_value(foreach_binding_list_node(Expr_ForEach_Init, loc, init)),
        ),
        (
          "continue_block",
          node_value(
            foreach_binding_list_node(
              Expr_ForEach_ContinueBlock,
              loc,
              continue_block,
            ),
          ),
        ),
        ("is_iter", bool_value(is_iter)),
      ])
    For(binders~, condition~, continue_block~, for_loc~) => {
      ignore(for_loc)
      node(Expr_ListComprehension_Kind_For, loc, [
        (
          "binders",
          node_value(for_binding_list_node(Expr_For_BindingList, loc, binders)),
        ),
        ("condition", option_value(condition, expr_value)),
        (
          "continue_block",
          node_value(
            for_binding_list_node(Expr_For_ContBindingList, loc, continue_block),
          ),
        ),
        ("is_iter", bool_value(is_iter)),
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
    Question => node0(TryOperatorKind_Question, loc)
    Exclamation => node0(TryOperatorKind_Exclamation, loc)
  }
}

///|
fn group_node(item : @syntax.Group, loc : @basic.Location) -> Node {
  match item {
    Brace => node0(Group_Brace, loc)
    Paren => node0(Group_Paren, loc)
  }
}

///|
fn hole_node(item : @syntax.Hole, loc : @basic.Location) -> Node {
  match item {
    Synthesized => node0(Hole_Synthesized, loc)
    Incomplete => node0(Hole_Incomplete, loc)
    Todo => node0(Hole_Todo, loc)
  }
}

///|
fn async_value(is_async : @basic.Location) -> Node {
  node_value(node0(Async, is_async))
}

///|
fn for_binding_list_node(
  kind : NodeKind,
  loc : @basic.Location,
  bindings : @list.List[(@syntax.Binder, @syntax.Expr)],
) -> Node {
  list_node(kind, loc, bindings, fn(binding) {
    let (binder, expr) = binding
    let binding_kind = if kind == Expr_For_ContBindingList {
      For_ContBinding
    } else {
      For_Binding
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
  kind : NodeKind,
  loc : @basic.Location,
  bindings : @list.List[(@syntax.Binder, @syntax.Expr)],
) -> Node {
  list_node(kind, loc, bindings, fn(binding) {
    let (binder, expr) = binding
    let (binding_kind, binder_field) = if kind == Expr_ForEach_Init {
      (ForEach_Init, "init")
    } else {
      (ForEach_ContinueBlock, "binder")
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
  list_node(ImplList, @syntax.no_location, impls, impl_value)
}

///|
fn impl_node(item : @syntax.Impl) -> Node {
  match item {
    TopExpr(expr~, is_main~, is_async~, loc~) =>
      node(Impl_TopExpr, loc, [
        ("expr", expr_value(expr)),
        ("is_main", bool_value(is_main)),
        (
          "local_types",
          node_value(empty_list_node(Impl_TopExpr_LocalTypeList, loc)),
        ),
        ("is_async", option_value(is_async, async_value)),
      ])
    TopTest(expr~, name~, params~, is_async~, loc~, attrs~, doc~) =>
      node(Impl_TopTest, loc, [
        ("expr", expr_value(expr)),
        ("name", test_name_value(name)),
        (
          "params",
          option_value(params, fn(params) {
            node_value(
              list_node(Impl_TopTest_ParamList, loc, params, parameter_value),
            )
          }),
        ),
        (
          "local_types",
          node_value(empty_list_node(Impl_TopTest_LocalTypeList, loc)),
        ),
        ("is_async", option_value(is_async, async_value)),
        (
          "attrs",
          node_value(
            list_node(Impl_TopTest_AttrList, loc, attrs, attribute_value),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
    TopTypeDef(type_decl) =>
      node1(
        Impl_TopTypeDef,
        type_decl.loc,
        node_value(type_decl_node(type_decl)),
      )
    TopFuncDef(fun_decl~, decl_body~, where_clause~, loc~) =>
      node(Impl_TopFuncDef, loc, [
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
      node(Impl_TopLetDef, loc, [
        ("binder", binder_value(binder)),
        ("ty", option_value(ty, type_value)),
        ("expr", expr_value(expr)),
        ("vis", node_value(visibility_node(vis, loc))),
        ("is_constant", bool_value(is_constant)),
        ("is_declare", bool_value(is_declare)),
        (
          "attrs",
          node_value(
            list_node(Impl_TopLetDef_AttrList, loc, attrs, attribute_value),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
    TopTrait(trait_decl) =>
      node1(
        Impl_TopTrait,
        trait_decl.loc,
        node_value(trait_decl_node(trait_decl)),
      )
    TopImpl(
      self_ty~,
      trait_~,
      method_name~,
      quantifiers~,
      method_quantifiers~,
      params~,
      ret_ty~,
      err_ty~,
      body~,
      vis~,
      loc~,
      attrs~,
      doc~
    ) =>
      node(Impl_TopImpl, loc, [
        ("self_ty", option_value(self_ty, type_value)),
        ("trait", type_name_value(trait_)),
        ("method_name", binder_value(method_name)),
        ("has_error", null_value()),
        (
          "quantifiers",
          node_value(
            list_node(
              Impl_TopImpl_QuantifierList,
              loc,
              quantifiers,
              type_var_binder_value,
            ),
          ),
        ),
        (
          "method_quantifiers",
          node_value(
            list_node(
              Impl_TopImpl_MethodQuantifierList,
              loc,
              method_quantifiers,
              type_var_binder_value,
            ),
          ),
        ),
        (
          "params",
          node_value(
            list_node(Impl_TopImpl_ParamList, loc, params, parameter_value),
          ),
        ),
        ("ret_ty", option_value(ret_ty, type_value)),
        ("err_ty", node_value(error_type_node(err_ty, loc))),
        ("body", node_value(decl_body_node(body, loc))),
        ("vis", node_value(visibility_node(vis, loc))),
        (
          "attrs",
          node_value(
            list_node(Impl_TopImpl_AttrList, loc, attrs, attribute_value),
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
      node(Impl_TopView, loc, [
        (
          "quantifiers",
          node_value(
            list_node(
              Impl_TopView_QuantifierList,
              loc,
              quantifiers,
              type_var_binder_value,
            ),
          ),
        ),
        ("source_ty", type_value(source_ty)),
        (
          "view_constrs",
          node_value(
            list_node(
              Impl_TopView_ConstrList,
              params_loc,
              view_constrs,
              constr_decl_value,
            ),
          ),
        ),
        ("body", expr_value(body)),
        ("ty_name", string_value(view_type_name)),
        (
          "parameters",
          node_value(
            list_node(
              Impl_TopView_ParameterList,
              loc,
              parameters,
              parameter_value,
            ),
          ),
        ),
        ("func_name", binder_value(view_func_name)),
        ("vis", node_value(visibility_node(vis, loc))),
        (
          "attrs",
          node_value(
            list_node(Impl_TopView_AttrList, loc, attrs, attribute_value),
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
      node(Impl_TopImplRelation, loc, [
        ("self_ty", type_value(self_ty)),
        ("trait", type_name_value(trait_)),
        (
          "quantifiers",
          node_value(
            list_node(
              Impl_TopImplRelation_QuantifierList,
              loc,
              quantifiers,
              type_var_binder_value,
            ),
          ),
        ),
        ("vis", node_value(visibility_node(vis, loc))),
        ("is_declare", bool_value(is_declare)),
        (
          "attrs",
          node_value(
            list_node(
              Impl_TopImplRelation_AttrList,
              loc,
              attrs,
              attribute_value,
            ),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
    TopUsing(pkg~, names~, vis~, attrs~, loc~, doc~) =>
      node(Impl_TopUsing, loc, [
        ("pkg", label_value(pkg)),
        (
          "names",
          node_value(
            list_node(Impl_TopUsing_NameList, loc, names, using_name_value),
          ),
        ),
        ("vis", node_value(visibility_node(vis, loc))),
        (
          "attrs",
          node_value(
            list_node(Impl_TopUsing_AttrList, loc, attrs, attribute_value),
          ),
        ),
        ("doc", doc_string_value(doc)),
      ])
  }
}

///|
fn impl_value(item : @syntax.Impl) -> Node {
  node_value(impl_node(item))
}

///|
fn type_decl_binder_value(item : @syntax.TypeDeclBinder) -> Node {
  node_value(type_decl_binder_node(item))
}

///|
fn type_var_constraint_value(item : @syntax.TypeVarConstraint) -> Node {
  node_value(type_var_constraint_node(item))
}

///|
fn type_var_binder_value(item : @syntax.TypeVarBinder) -> Node {
  node_value(type_var_binder_node(item))
}

///|
fn trait_method_decl_value(item : @syntax.TraitMethodDecl) -> Node {
  node_value(trait_method_decl_node(item))
}

///|
fn deriving_directive_value(item : @syntax.DerivingDirective) -> Node {
  node_value(deriving_directive_node(item))
}

///|
fn constr_decl_value(item : @syntax.ConstrDecl) -> Node {
  node_value(constr_decl_node(item))
}

///|
fn constr_param_value(item : @syntax.ConstrParam) -> Node {
  node_value(constr_param_node(item))
}

///|
fn field_decl_value(item : @syntax.FieldDecl) -> Node {
  node_value(field_decl_node(item))
}

///|
fn where_clause_value(item : @syntax.WhereClause) -> Node {
  node_value(where_clause_node(item))
}
