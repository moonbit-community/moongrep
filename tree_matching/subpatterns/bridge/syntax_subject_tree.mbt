///|
type Subject = @subpatterns.SubjectTree[@basic.Location]

///|
fn node(
  loc : @basic.Location,
  label : String,
  children : ArrayView[Subject],
) -> Subject {
  @subpatterns.SubjectTree::node(loc, label, children)
}

///|
fn leaf(loc : @basic.Location, label : String) -> Subject {
  node(loc, label, [])
}

///|
fn field(loc : @basic.Location, name : String, child : Subject) -> Subject {
  node(loc, "field:\{name}", [child])
}

///|
fn string_leaf(loc : @basic.Location, value : String) -> Subject {
  leaf(loc, "string:\{value}")
}

///|
fn bool_leaf(loc : @basic.Location, value : Bool) -> Subject {
  leaf(loc, if value { "bool:true" } else { "bool:false" })
}

///|
fn int_leaf(loc : @basic.Location, value : Int) -> Subject {
  leaf(loc, "int:\{value}")
}

///|
fn none_node(loc : @basic.Location) -> Subject {
  leaf(loc, "none")
}

///|
fn async_node(loc : @basic.Location) -> Subject {
  node(loc, "Async", [])
}

///|
fn[A] option_node(
  loc : @basic.Location,
  value : A?,
  convert : (A) -> Subject,
) -> Subject {
  match value {
    Some(value) => convert(value)
    None => none_node(loc)
  }
}

///|
fn[A] list_node(
  kind : String,
  loc : @basic.Location,
  values : @list.List[A],
  convert : (A) -> Subject,
) -> Subject {
  let children = []
  values.each(fn(value) { children.push(convert(value)) })
  node(loc, kind, children)
}

///|
fn empty_list_node(kind : String, loc : @basic.Location) -> Subject {
  node(loc, kind, [])
}

///|
fn long_ident_to_subject_tree(
  loc : @basic.Location,
  id : @syntax.LongIdent,
) -> Subject {
  match id {
    Ident(name~) =>
      node(loc, "LongIdent::Ident", [
        field(loc, "value", string_leaf(loc, name)),
      ])
    Dot(pkg~, id~) =>
      node(loc, "LongIdent::Dot", [
        field(loc, "pkg", string_leaf(loc, pkg)),
        field(loc, "id", string_leaf(loc, id)),
      ])
  }
}

///|
fn var_to_subject_tree(var_ : @syntax.Var) -> Subject {
  node(var_.loc, "Var", [
    field(var_.loc, "name", long_ident_to_subject_tree(var_.loc, var_.name)),
  ])
}

///|
fn constant_value_node(
  loc : @basic.Location,
  kind : String,
  value : Subject,
) -> Subject {
  node(loc, kind, [field(loc, "value", value)])
}

///|
fn constant_to_subject_tree(
  loc : @basic.Location,
  constant : @syntax.Constant,
) -> Subject {
  match constant {
    Bool(value) =>
      constant_value_node(loc, "Constant::Bool", bool_leaf(loc, value))
    Byte(value) =>
      constant_value_node(loc, "Constant::Byte", string_leaf(loc, value))
    Bytes(value) =>
      constant_value_node(loc, "Constant::Bytes", string_leaf(loc, value))
    Char(value) =>
      constant_value_node(loc, "Constant::Char", string_leaf(loc, value))
    Int(value) =>
      constant_value_node(loc, "Constant::Int", string_leaf(loc, value))
    Int64(value) =>
      constant_value_node(loc, "Constant::Int64", string_leaf(loc, value))
    UInt(value) =>
      constant_value_node(loc, "Constant::UInt", string_leaf(loc, value))
    UInt64(value) =>
      constant_value_node(loc, "Constant::UInt64", string_leaf(loc, value))
    Float(value) =>
      constant_value_node(loc, "Constant::Float", string_leaf(loc, value))
    Double(value) =>
      constant_value_node(loc, "Constant::Double", string_leaf(loc, value))
    String(value) =>
      constant_value_node(loc, "Constant::String", string_leaf(loc, value))
    Regex(value) =>
      constant_value_node(loc, "Constant::Regex", string_leaf(loc, value))
    BigInt(value) =>
      constant_value_node(loc, "Constant::BigInt", string_leaf(loc, value))
  }
}

///|
fn label_to_subject_tree(label : @syntax.Label) -> Subject {
  node(label.loc, "Label", [
    field(label.loc, "name", string_leaf(label.loc, label.name)),
  ])
}

///|
fn binder_to_subject_tree(binder : @syntax.Binder) -> Subject {
  node(binder.loc, "Binder", [
    field(binder.loc, "name", string_leaf(binder.loc, binder.name)),
  ])
}

///|
fn constr_id_to_subject_tree(constr_id : @syntax.ConstrId) -> Subject {
  node(constr_id.loc, "ConstrId", [
    field(
      constr_id.loc,
      "id",
      long_ident_to_subject_tree(constr_id.loc, constr_id.id),
    ),
  ])
}

///|
fn type_name_to_subject_tree(type_name : @syntax.TypeName) -> Subject {
  node(type_name.loc, "TypeName", [
    field(
      type_name.loc,
      "name",
      long_ident_to_subject_tree(type_name.loc, type_name.name),
    ),
    field(
      type_name.loc,
      "is_object",
      bool_leaf(type_name.loc, type_name.is_object),
    ),
  ])
}

///|
fn constr_name_to_subject_tree(name : @syntax.ConstrName) -> Subject {
  node(name.loc, "ConstrName", [
    field(name.loc, "name", string_leaf(name.loc, name.name)),
  ])
}

///|
fn field_name_to_subject_tree(name : @syntax.FieldName) -> Subject {
  node(name.loc, "FieldName", [
    field(name.loc, "label", string_leaf(name.loc, name.label)),
  ])
}

///|
fn async_option_to_subject_tree(
  loc : @basic.Location,
  is_async : @basic.Location?,
) -> Subject {
  option_node(loc, is_async, async_node)
}

///|
fn visibility_to_subject_tree(
  visibility : @syntax.Visibility,
  loc : @basic.Location,
) -> Subject {
  match visibility {
    Default => node(loc, "Visibility::Default", [])
    Priv(loc~) => node(loc, "Visibility::Priv", [])
    Pub(attr~, loc~) =>
      node(loc, "Visibility::Pub", [
        field(
          loc,
          "attr",
          option_node(loc, attr, fn(value) { string_leaf(loc, value) }),
        ),
      ])
  }
}

///|
fn apply_attr_to_subject_tree(loc : @basic.Location) -> Subject {
  node(loc, "ApplyAttr::NoAttr", [])
}

///|
fn fn_kind_to_subject_tree(
  kind : @syntax.FnKind,
  loc : @basic.Location,
) -> Subject {
  match kind {
    Lambda => node(loc, "FnKind::Lambda", [])
    Arrow => node(loc, "FnKind::Arrow", [])
  }
}

///|
fn trailing_mark_to_subject_tree(
  trailing : @syntax.TrailingMark,
  loc : @basic.Location,
) -> Subject {
  match trailing {
    Comma => node(loc, "Trailing::Comma", [])
    Semi => node(loc, "Trailing::Semi", [])
    None => node(loc, "Trailing::None", [])
  }
}

///|
fn group_to_subject_tree(
  group : @syntax.Group,
  loc : @basic.Location,
) -> Subject {
  match group {
    Brace => node(loc, "Group::Brace", [])
    Paren => node(loc, "Group::Paren", [])
  }
}

///|
fn hole_to_subject_tree(hole : @syntax.Hole, loc : @basic.Location) -> Subject {
  match hole {
    Synthesized => node(loc, "Hole::Synthesized", [])
    Incomplete => node(loc, "Hole::Incomplete", [])
    Todo => node(loc, "Hole::Todo", [])
  }
}

///|
fn try_operator_kind_to_subject_tree(
  kind : @syntax.TryOperatorKind,
  loc : @basic.Location,
) -> Subject {
  match kind {
    Question => node(loc, "TryOperatorKind::Question", [])
    Exclamation => node(loc, "TryOperatorKind::Exclamation", [])
  }
}

///|
fn range_kind_to_subject_tree(
  kind : @syntax.RangeKind,
  loc : @basic.Location,
) -> Subject {
  match kind {
    Inclusive | InclusiveMissingEqual => node(loc, "RangeKind::Inclusive", [])
    Exclusive => node(loc, "RangeKind::Exclusive", [])
  }
}

///|
fn predicate_quantifier_kind_to_subject_tree(
  kind : @syntax.PredicateQuantifierKind,
  loc : @basic.Location,
) -> Subject {
  match kind {
    Forall => string_leaf(loc, "forall")
    Exists => string_leaf(loc, "exists")
  }
}

///|
fn error_type_to_subject_tree(
  error_type : @syntax.ErrorType,
  loc : @basic.Location,
) -> Subject {
  match error_type {
    ErrorType(ty~) =>
      node(ty.loc(), "ErrorType::ErrorType", [
        field(ty.loc(), "ty", type_to_subject_tree(ty)),
      ])
    DefaultErrorType(loc~) => node(loc, "ErrorType::DefaultErrorType", [])
    NoErrorType => node(loc, "ErrorType::NoErrorType", [])
    Noraise(loc~) => node(loc, "ErrorType::Noraise", [])
    MaybeError(ty~) =>
      node(ty.loc(), "ErrorType::MaybeError", [
        field(ty.loc(), "ty", type_to_subject_tree(ty)),
      ])
  }
}

///|
fn type_to_subject_tree(ty : @syntax.Type) -> Subject {
  match ty {
    Any(loc~) => node(loc, "Type::Any", [])
    Arrow(args~, res~, err~, is_async~, loc~) =>
      node(loc, "Type::Arrow", [
        field(
          loc,
          "args",
          list_node("Type::Arrow::ArgList", loc, args, type_to_subject_tree),
        ),
        field(loc, "res", type_to_subject_tree(res)),
        field(loc, "err", error_type_to_subject_tree(err, loc)),
        field(loc, "is_async", async_option_to_subject_tree(loc, is_async)),
      ])
    Tuple(tys~, loc~) =>
      node(loc, "Type::Tuple", [
        field(
          loc,
          "tys",
          list_node("Type::Tuple::TypeList", loc, tys, type_to_subject_tree),
        ),
      ])
    Name(constr_id~, tys~, loc~) =>
      node(loc, "Type::Name", [
        field(loc, "constr_id", constr_id_to_subject_tree(constr_id)),
        field(
          loc,
          "tys",
          list_node("Type::Name::TypeList", loc, tys, type_to_subject_tree),
        ),
      ])
    Option(ty~, loc~, question_loc~) => {
      ignore(question_loc)
      node(loc, "Type::Option", [field(loc, "ty", type_to_subject_tree(ty))])
    }
    Object(constr_id) =>
      node(constr_id.loc, "Type::Object", [
        field(constr_id.loc, "value", constr_id_to_subject_tree(constr_id)),
      ])
  }
}

///|
fn type_var_constraint_to_subject_tree(
  constraint : @syntax.TypeVarConstraint,
) -> Subject {
  node(constraint.loc, "TypeVarConstraint", [
    field(
      constraint.loc,
      "trait",
      long_ident_to_subject_tree(constraint.loc, constraint.trait_),
    ),
  ])
}

///|
fn type_var_constraint_list_loc(
  default : @basic.Location,
  constraints : @list.List[@syntax.TypeVarConstraint],
) -> @basic.Location {
  match constraints {
    @list.Empty => default
    @list.More(constraint, tail=@list.Empty) => constraint.loc
    @list.More(first, tail~) => first.loc.merge(tail.last().unwrap().loc)
  }
}

///|
fn type_var_binder_to_subject_tree(binder : @syntax.TypeVarBinder) -> Subject {
  let constraints_loc = type_var_constraint_list_loc(
    binder.name_loc,
    binder.constraints,
  )
  let loc = binder.name_loc.merge(constraints_loc)
  node(loc, "TypeVarBinder", [
    field(loc, "name", string_leaf(loc, binder.name)),
    field(
      loc,
      "constraints",
      list_node(
        "TypeVarBinder::TypeVarConstraintList",
        constraints_loc,
        binder.constraints,
        type_var_constraint_to_subject_tree,
      ),
    ),
  ])
}

///|
fn type_decl_binder_to_subject_tree(binder : @syntax.TypeDeclBinder) -> Subject {
  node(binder.loc, "TypeDeclBinder", [
    field(
      binder.loc,
      "name",
      option_node(binder.loc, binder.name, fn(value) {
        string_leaf(binder.loc, value)
      }),
    ),
  ])
}

///|
fn argument_kind_to_subject_tree(
  kind : @syntax.ArgumentKind,
  loc : @basic.Location,
) -> Subject {
  match kind {
    Positional => node(loc, "ArgumentKind::Positional", [])
    Labelled(label) =>
      node(label.loc, "ArgumentKind::Labelled", [
        field(label.loc, "value", label_to_subject_tree(label)),
      ])
    LabelledPun(label) =>
      node(label.loc, "ArgumentKind::LabelledPun", [
        field(label.loc, "value", label_to_subject_tree(label)),
      ])
    LabelledOption(label~, question_loc~) => {
      ignore(question_loc)
      node(label.loc, "ArgumentKind::LabelledOption", [
        field(label.loc, "label", label_to_subject_tree(label)),
      ])
    }
    LabelledOptionPun(label~, question_loc~) => {
      ignore(question_loc)
      node(label.loc, "ArgumentKind::LabelledOptionPun", [
        field(label.loc, "label", label_to_subject_tree(label)),
      ])
    }
  }
}

///|
fn argument_to_subject_tree(argument : @syntax.Argument) -> Subject {
  let loc = argument.value.loc()
  node(loc, "Argument", [
    field(loc, "value", expr_to_subject_tree(argument.value)),
    field(loc, "kind", argument_kind_to_subject_tree(argument.kind, loc)),
  ])
}

///|
fn parameter_to_subject_tree(parameter : @syntax.Parameter) -> Subject {
  let loc = parameter.loc()
  match parameter {
    DiscardPositional(ty~, loc~) =>
      node(loc, "Parameter::DiscardPositional", [
        field(loc, "ty", option_node(loc, ty, type_to_subject_tree)),
      ])
    Positional(binder~, ty~) =>
      node(loc, "Parameter::Positional", [
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(loc, "ty", option_node(loc, ty, type_to_subject_tree)),
      ])
    Labelled(binder~, ty~) =>
      node(loc, "Parameter::Labelled", [
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(loc, "ty", option_node(loc, ty, type_to_subject_tree)),
      ])
    Optional(binder~, default~, ty~) =>
      node(loc, "Parameter::Optional", [
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(loc, "default", expr_to_subject_tree(default)),
        field(loc, "ty", option_node(loc, ty, type_to_subject_tree)),
      ])
    QuestionOptional(binder~, ty~) =>
      node(loc, "Parameter::QuestionOptional", [
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(loc, "ty", option_node(loc, ty, type_to_subject_tree)),
      ])
  }
}

///|
fn case_to_subject_tree(case_ : @syntax.Case) -> Subject {
  let loc = case_.pattern.loc().merge(case_.body.loc())
  node(loc, "Case", [
    field(loc, "pattern", pattern_to_subject_tree(case_.pattern)),
    field(loc, "guard", option_node(loc, case_.guard_, expr_to_subject_tree)),
    field(loc, "body", expr_to_subject_tree(case_.body)),
  ])
}

///|
fn constructor_extra_info_to_subject_tree(
  extra : @syntax.ConstructorExtraInfo,
  loc : @basic.Location,
) -> Subject {
  match extra {
    TypeName(type_name) =>
      node(type_name.loc, "ConstructorExtraInfo::TypeName", [
        field(type_name.loc, "value", type_name_to_subject_tree(type_name)),
      ])
    TypeNameWithConstrPackage(type_name~, pkg~) =>
      node(loc, "ConstructorExtraInfo::TypeNameWithConstrPackage", [
        field(loc, "type_name", type_name_to_subject_tree(type_name)),
        field(loc, "pkg", string_leaf(loc, pkg)),
      ])
    Package(pkg) =>
      node(loc, "ConstructorExtraInfo::Package", [
        field(loc, "value", string_leaf(loc, pkg)),
      ])
    NoExtraInfo => node(loc, "ConstructorExtraInfo::NoExtraInfo", [])
  }
}

///|
fn constructor_to_subject_tree(constr : @syntax.Constructor) -> Subject {
  node(constr.loc, "Constructor", [
    field(constr.loc, "name", constr_name_to_subject_tree(constr.name)),
    field(
      constr.loc,
      "extra_info",
      constructor_extra_info_to_subject_tree(constr.extra_info, constr.loc),
    ),
  ])
}

///|
fn accessor_to_subject_tree(accessor : @syntax.Accessor) -> Subject {
  match accessor {
    Label(label) =>
      node(label.loc, "Accessor::Label", [
        field(label.loc, "value", label_to_subject_tree(label)),
      ])
    Index(tuple_index~, loc~) =>
      node(loc, "Accessor::Index", [
        field(loc, "tuple_index", int_leaf(loc, tuple_index)),
      ])
    Newtype(loc~) => node(loc, "Accessor::Newtype", [])
  }
}

///|
fn spreadable_elem_to_subject_tree(elem : @syntax.SpreadableElem) -> Subject {
  match elem {
    Regular(expr) =>
      node(expr.loc(), "SpreadableElem::Regular", [
        field(expr.loc(), "value", expr_to_subject_tree(expr)),
      ])
    Spread(expr~, loc~) =>
      node(loc, "SpreadableElem::Spread", [
        field(loc, "expr", expr_to_subject_tree(expr)),
      ])
  }
}

///|
fn multiline_string_elem_to_subject_tree(
  elem : @syntax.MultilineStringElem,
  loc : @basic.Location,
) -> Subject {
  match elem {
    String(value) =>
      node(loc, "MultilineString::String", [
        field(loc, "value", string_leaf(loc, value)),
      ])
    Interp(elems) =>
      node(loc, "MultilineString::Interp", [
        field(
          loc,
          "value",
          list_node(
            "MultilineString::Interp::ElemList", loc, elems, interp_elem_to_subject_tree,
          ),
        ),
      ])
  }
}

///|
fn interp_elem_to_subject_tree(elem : @syntax.InterpElem) -> Subject {
  match elem {
    Literal(repr~, loc~) =>
      node(loc, "InterpElem::Literal", [
        field(loc, "repr", string_leaf(loc, repr)),
      ])
    Expr(expr~, loc~) =>
      node(loc, "InterpElem::Expr", [
        field(loc, "expr", expr_to_subject_tree(expr)),
      ])
    Source(source) =>
      node(source.loc, "InterpElem::Source", [
        field(source.loc, "source", string_leaf(source.loc, source.source)),
      ])
  }
}

///|
fn field_def_to_subject_tree(field_def : @syntax.FieldDef) -> Subject {
  node(field_def.loc, "FieldDef", [
    field(field_def.loc, "label", label_to_subject_tree(field_def.label)),
    field(field_def.loc, "expr", expr_to_subject_tree(field_def.expr)),
    field(field_def.loc, "is_pun", bool_leaf(field_def.loc, field_def.is_pun)),
  ])
}

///|
fn where_clause_to_subject_tree(where_clause : @syntax.WhereClause) -> Subject {
  node(where_clause.loc, "WhereClause", [
    field(
      where_clause.loc,
      "fields",
      list_node(
        "WhereClause::FieldList",
        where_clause.loc,
        where_clause.fields,
        field_def_to_subject_tree,
      ),
    ),
  ])
}

///|
fn map_expr_elem_to_subject_tree(elem : @syntax.MapExprElem) -> Subject {
  node(elem.loc, "MapExprElem", [
    field(elem.loc, "key", constant_to_subject_tree(elem.key_loc, elem.key)),
    field(elem.loc, "expr", expr_to_subject_tree(elem.expr)),
  ])
}

///|
fn regex_pattern_to_subject_tree(pattern : @syntax.RegexPattern) -> Subject {
  match pattern {
    Literal(lit~, loc~) =>
      node(loc, "RegexPattern::Literal", [
        field(loc, "lit", string_leaf(loc, lit)),
      ])
    Reference(lid~, loc~) =>
      node(loc, "RegexPattern::Reference", [
        field(loc, "lid", long_ident_to_subject_tree(loc, lid)),
      ])
    Sequence(pat1~, pat2~, loc~) =>
      node(loc, "RegexPattern::Sequence", [
        field(loc, "pat1", regex_pattern_to_subject_tree(pat1)),
        field(loc, "pat2", regex_pattern_to_subject_tree(pat2)),
      ])
    Alternation(pat1~, pat2~, loc~) =>
      node(loc, "RegexPattern::Alternation", [
        field(loc, "pat1", regex_pattern_to_subject_tree(pat1)),
        field(loc, "pat2", regex_pattern_to_subject_tree(pat2)),
      ])
    Alias(pat~, binder~, loc~) =>
      node(loc, "RegexPattern::Alias", [
        field(loc, "pat", regex_pattern_to_subject_tree(pat)),
        field(loc, "binder", binder_to_subject_tree(binder)),
      ])
  }
}

///|
fn lex_pattern_to_subject_tree(pattern : @syntax.LexPattern) -> Subject {
  match pattern {
    Regex(lit~, offset~, loc~) =>
      node(loc, "LexPattern::Regex", [
        field(loc, "lit", string_leaf(loc, lit)),
        field(loc, "offset", int_leaf(loc, offset)),
      ])
    RegexInterp(elems~, loc~) =>
      node(loc, "LexPattern::RegexInterp", [
        field(
          loc,
          "elems",
          list_node(
            "LexPattern::RegexInterp::InterpElemList", loc, elems, interp_elem_to_subject_tree,
          ),
        ),
      ])
    ConstantRef(lid~, loc~) =>
      node(loc, "LexPattern::ConstantRef", [
        field(loc, "lid", long_ident_to_subject_tree(loc, lid)),
      ])
    Alias(pat~, binder~, loc~) =>
      node(loc, "LexPattern::Alias", [
        field(loc, "pat", lex_pattern_to_subject_tree(pat)),
        field(loc, "binder", binder_to_subject_tree(binder)),
      ])
    Sequence(pats~, loc~) =>
      node(loc, "LexPattern::Sequence", [
        field(
          loc,
          "pats",
          list_node(
            "LexPattern::Sequence::PatternList", loc, pats, lex_pattern_to_subject_tree,
          ),
        ),
      ])
  }
}

///|
fn lex_top_pattern_to_subject_tree(
  pattern : @syntax.LexTopPattern,
  loc : @basic.Location,
) -> Subject {
  match pattern {
    Pattern(pat) =>
      node(loc, "LexTopPattern::Pattern", [
        field(loc, "value", lex_pattern_to_subject_tree(pat)),
      ])
    Binder(binder) =>
      node(loc, "LexTopPattern::Binder", [
        field(loc, "value", binder_to_subject_tree(binder)),
      ])
    Wildcard(loc~) => node(loc, "LexTopPattern::Wildcard", [])
  }
}

///|
fn lex_case_to_subject_tree(
  case_ : @syntax.LexCase,
  loc : @basic.Location,
) -> Subject {
  node(loc, "LexCase", [
    field(
      loc,
      "pat",
      list_node("LexCase::PatternList", case_.pat_loc, case_.pat, fn(pattern) {
        lex_top_pattern_to_subject_tree(pattern, case_.pat_loc)
      }),
    ),
    field(loc, "guard", option_node(loc, case_.guard_, expr_to_subject_tree)),
    field(loc, "body", expr_to_subject_tree(case_.body)),
  ])
}

///|
fn for_binding_to_subject_tree(
  loc : @basic.Location,
  binder : @syntax.Binder,
  expr : @syntax.Expr,
) -> Subject {
  node(loc, "For::Binding", [
    field(loc, "binder", binder_to_subject_tree(binder)),
    field(loc, "expr", expr_to_subject_tree(expr)),
  ])
}

///|
fn for_cont_binding_to_subject_tree(
  loc : @basic.Location,
  binder : @syntax.Binder,
  expr : @syntax.Expr,
) -> Subject {
  node(loc, "For::ContBinding", [
    field(loc, "binder", binder_to_subject_tree(binder)),
    field(loc, "expr", expr_to_subject_tree(expr)),
  ])
}

///|
fn foreach_init_to_subject_tree(
  loc : @basic.Location,
  binder : @syntax.Binder,
  expr : @syntax.Expr,
) -> Subject {
  node(loc, "ForEach::Init", [
    field(loc, "init", binder_to_subject_tree(binder)),
    field(loc, "expr", expr_to_subject_tree(expr)),
  ])
}

///|
fn foreach_continue_to_subject_tree(
  loc : @basic.Location,
  binder : @syntax.Binder,
  expr : @syntax.Expr,
) -> Subject {
  node(loc, "ForEach::ContinueBlock", [
    field(loc, "binder", binder_to_subject_tree(binder)),
    field(loc, "expr", expr_to_subject_tree(expr)),
  ])
}

///|
fn list_comprehension_kind_to_subject_tree(
  kind : @syntax.ListComprehensionKind,
  loc : @basic.Location,
) -> Subject {
  match kind {
    Foreach(binders~, expr~, init~, continue_block~) =>
      node(loc, "Expr::ListComprehension::Kind::Foreach", [
        field(
          loc,
          "binders",
          list_node("Expr::ForEach::BinderList", loc, binders, fn(binder) {
            option_node(loc, binder, binder_to_subject_tree)
          }),
        ),
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(
          loc,
          "init",
          list_node("Expr::ForEach::Init", loc, init, fn(binding) {
            let (binder, expr) = binding
            foreach_init_to_subject_tree(loc, binder, expr)
          }),
        ),
        field(
          loc,
          "continue_block",
          list_node("Expr::ForEach::ContinueBlock", loc, continue_block, fn(
            binding,
          ) {
            let (binder, expr) = binding
            foreach_continue_to_subject_tree(loc, binder, expr)
          }),
        ),
      ])
    For(binders~, condition~, continue_block~, for_loc~) => {
      ignore(for_loc)
      node(loc, "Expr::ListComprehension::Kind::For", [
        field(
          loc,
          "binders",
          list_node("Expr::For::BindingList", loc, binders, fn(binding) {
            let (binder, expr) = binding
            for_binding_to_subject_tree(loc, binder, expr)
          }),
        ),
        field(
          loc,
          "condition",
          option_node(loc, condition, expr_to_subject_tree),
        ),
        field(
          loc,
          "continue_block",
          list_node("Expr::For::ContBindingList", loc, continue_block, fn(
            binding,
          ) {
            let (binder, expr) = binding
            for_cont_binding_to_subject_tree(loc, binder, expr)
          }),
        ),
      ])
    }
  }
}

///|
fn static_assertion_to_subject_tree(
  assertion : @syntax.StaticAssertion,
) -> Subject {
  node(assertion.loc, "StaticAssertion", [
    field(assertion.loc, "ty", type_to_subject_tree(assertion.ty)),
    field(
      assertion.loc,
      "trait",
      long_ident_to_subject_tree(assertion.loc, assertion.trait_),
    ),
    field(assertion.loc, "msg", string_leaf(assertion.loc, assertion.msg)),
  ])
}

///|
fn array_pattern_to_subject_tree(pattern : @syntax.ArrayPattern) -> Subject {
  match pattern {
    Pattern(pattern) =>
      node(pattern.loc(), "ArrayPattern::Pattern", [
        field(pattern.loc(), "value", pattern_to_subject_tree(pattern)),
      ])
    StringSpread(str~, loc~) =>
      node(loc, "ArrayPattern::StringSpread", [
        field(loc, "str", string_leaf(loc, str)),
      ])
    BytesSpread(bytes~, loc~) =>
      node(loc, "ArrayPattern::BytesSpread", [
        field(loc, "bytes", string_leaf(loc, bytes)),
      ])
    ConstSpread(binder~, pkg~, loc~) =>
      node(loc, "ArrayPattern::ConstSpread", [
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(
          loc,
          "pkg",
          option_node(loc, pkg, fn(value) { string_leaf(loc, value) }),
        ),
      ])
  }
}

///|
fn dot_dot_binder_to_subject_tree(
  binder : @syntax.DotDotBinder,
  loc : @basic.Location,
) -> Subject {
  match binder {
    Underscore => node(loc, "DotDotBinder::Underscore", [])
    NoBinder => node(loc, "DotDotBinder::NoBinder", [])
    BinderAs(binder) =>
      node(binder.loc, "DotDotBinder::BinderAs", [
        field(binder.loc, "value", binder_to_subject_tree(binder)),
      ])
    Binder(binder) =>
      node(binder.loc, "DotDotBinder::Binder", [
        field(binder.loc, "value", binder_to_subject_tree(binder)),
      ])
  }
}

///|
fn array_patterns_to_subject_tree(
  patterns : @syntax.ArrayPatterns,
  loc : @basic.Location,
) -> Subject {
  match patterns {
    Closed(patterns) =>
      node(loc, "ArrayPatterns::Closed", [
        field(
          loc,
          "value",
          list_node(
            "ArrayPatterns::Closed::PatternList", loc, patterns, array_pattern_to_subject_tree,
          ),
        ),
      ])
    Open(left, right, binder) =>
      node(loc, "ArrayPatterns::Open", [
        field(
          loc,
          "0",
          list_node(
            "ArrayPatterns::Open::LPatternList", loc, left, array_pattern_to_subject_tree,
          ),
        ),
        field(
          loc,
          "1",
          list_node(
            "ArrayPatterns::Open::RPatternList", loc, right, array_pattern_to_subject_tree,
          ),
        ),
        field(loc, "2", dot_dot_binder_to_subject_tree(binder, loc)),
      ])
  }
}

///|
fn constr_pat_arg_to_subject_tree(arg : @syntax.ConstrPatArg) -> Subject {
  let loc = arg.pat.loc()
  node(loc, "ConstrPatArg", [
    field(loc, "pat", pattern_to_subject_tree(arg.pat)),
    field(loc, "kind", argument_kind_to_subject_tree(arg.kind, loc)),
  ])
}

///|
fn field_pat_to_subject_tree(field_pat : @syntax.FieldPat) -> Subject {
  node(field_pat.loc, "FieldPat", [
    field(field_pat.loc, "label", label_to_subject_tree(field_pat.label)),
    field(field_pat.loc, "pattern", pattern_to_subject_tree(field_pat.pattern)),
    field(field_pat.loc, "is_pun", bool_leaf(field_pat.loc, field_pat.is_pun)),
  ])
}

///|
fn map_pat_elem_to_subject_tree(elem : @syntax.MapPatElem) -> Subject {
  node(elem.loc, "MapPatElem", [
    field(elem.loc, "key", constant_to_subject_tree(elem.key_loc, elem.key)),
    field(elem.loc, "pat", pattern_to_subject_tree(elem.pat)),
    field(elem.loc, "match_absent", bool_leaf(elem.loc, elem.match_absent)),
  ])
}

///|
fn pattern_to_subject_tree(pattern : @syntax.Pattern) -> Subject {
  match pattern {
    Alias(pat~, alias_~, loc~) =>
      node(loc, "Pattern::Alias", [
        field(loc, "pat", pattern_to_subject_tree(pat)),
        field(loc, "alias", binder_to_subject_tree(alias_)),
      ])
    Any(loc~) => node(loc, "Pattern::Any", [])
    Array(pats~, loc~) =>
      node(loc, "Pattern::Array", [
        field(loc, "pats", array_patterns_to_subject_tree(pats, loc)),
      ])
    Constant(c~, loc~) =>
      node(loc, "Pattern::Constant", [
        field(loc, "constant", constant_to_subject_tree(loc, c)),
      ])
    Constraint(pat~, ty~, loc~) =>
      node(loc, "Pattern::Constraint", [
        field(loc, "pat", pattern_to_subject_tree(pat)),
        field(loc, "ty", type_to_subject_tree(ty)),
      ])
    Constr(constr~, args~, is_open~, loc~) =>
      node(loc, "Pattern::Constr", [
        field(loc, "constr", constructor_to_subject_tree(constr)),
        field(
          loc,
          "args",
          option_node(loc, args, fn(args) {
            list_node(
              "Pattern::Constr::ArgList", loc, args, constr_pat_arg_to_subject_tree,
            )
          }),
        ),
        field(loc, "is_open", bool_leaf(loc, is_open)),
      ])
    Or(pat1~, pat2~, loc~) =>
      node(loc, "Pattern::Or", [
        field(loc, "pat1", pattern_to_subject_tree(pat1)),
        field(loc, "pat2", pattern_to_subject_tree(pat2)),
      ])
    Tuple(pats~, loc~) =>
      node(loc, "Pattern::Tuple", [
        field(
          loc,
          "pats",
          list_node(
            "Pattern::Tuple::PatternList", loc, pats, pattern_to_subject_tree,
          ),
        ),
      ])
    Var(binder) =>
      node(binder.loc, "Pattern::Var", [
        field(binder.loc, "value", binder_to_subject_tree(binder)),
      ])
    Record(fields~, is_closed~, loc~) =>
      node(loc, "Pattern::Record", [
        field(
          loc,
          "fields",
          list_node(
            "Pattern::Record::FieldList", loc, fields, field_pat_to_subject_tree,
          ),
        ),
        field(loc, "is_closed", bool_leaf(loc, is_closed)),
      ])
    Map(elems~, is_closed~, loc~) =>
      node(loc, "Pattern::Map", [
        field(
          loc,
          "elems",
          list_node(
            "Pattern::Map::ElemList", loc, elems, map_pat_elem_to_subject_tree,
          ),
        ),
        field(loc, "is_closed", bool_leaf(loc, is_closed)),
      ])
    Range(lhs~, rhs~, kind~, loc~) =>
      node(loc, "Pattern::Range", [
        field(loc, "lhs", pattern_to_subject_tree(lhs)),
        field(loc, "rhs", pattern_to_subject_tree(rhs)),
        field(loc, "kind", range_kind_to_subject_tree(kind, loc)),
      ])
    SpecialConstr(binder~, args~, loc~) =>
      node(loc, "Pattern::SpecialConstr", [
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(
          loc,
          "args",
          list_node(
            "Pattern::SpecialConstr::ArgList", loc, args, constr_pat_arg_to_subject_tree,
          ),
        ),
      ])
  }
}

///|
fn constr_decl_list_loc(
  default : @basic.Location,
  constrs : @list.List[@syntax.ConstrDecl],
) -> @basic.Location {
  match constrs {
    @list.Empty => default
    @list.More(constr, tail=@list.Empty) => constr.loc
    @list.More(first, tail~) => first.loc.merge(tail.last().unwrap().loc)
  }
}

///|
fn type_list_loc(
  default : @basic.Location,
  types : @list.List[@syntax.Type],
) -> @basic.Location {
  match types {
    @list.Empty => default
    @list.More(ty, tail=@list.Empty) => ty.loc()
    @list.More(first, tail~) => first.loc().merge(tail.last().unwrap().loc())
  }
}

///|
fn exception_decl_to_subject_tree(
  decl : @syntax.ExceptionDecl,
  loc : @basic.Location,
) -> Subject {
  match decl {
    NoPayload => node(loc, "ExceptionDecl::NoPayload", [])
    EnumPayload(constrs) =>
      node(loc, "ExceptionDecl::EnumPayload", [
        field(
          loc,
          "value",
          list_node(
            "ExceptionDecl::EnumPayload::ConstrList", loc, constrs, constr_decl_to_subject_tree,
          ),
        ),
      ])
  }
}

///|
fn doc_string_to_subject_tree(doc : @syntax.DocString) -> Subject {
  let parts = []
  doc.content.each(fn(line) { parts.push(line) })
  string_leaf(doc.loc, parts.join("\n"))
}

///|
fn attribute_to_subject_tree(attribute : @attribute.Attribute) -> Subject {
  node(attribute.loc, "Attribute", [
    field(attribute.loc, "raw", string_leaf(attribute.loc, attribute.raw)),
  ])
}

///|
fn constr_param_to_subject_tree(param : @syntax.ConstrParam) -> Subject {
  let loc = match param.label {
    Some(label) => label.loc.merge(param.ty.loc())
    None => param.ty.loc()
  }
  node(loc, "ConstrParam", [
    field(loc, "ty", type_to_subject_tree(param.ty)),
    field(loc, "mut", bool_leaf(loc, param.mut_)),
    field(loc, "label", option_node(loc, param.label, label_to_subject_tree)),
  ])
}

///|
fn constr_decl_to_subject_tree(decl : @syntax.ConstrDecl) -> Subject {
  node(decl.loc, "ConstrDecl", [
    field(decl.loc, "name", constr_name_to_subject_tree(decl.name)),
    field(
      decl.loc,
      "args",
      option_node(decl.loc, decl.args, fn(args) {
        list_node(
          "ConstrDecl::ArgList",
          decl.loc,
          args,
          constr_param_to_subject_tree,
        )
      }),
    ),
    field(
      decl.loc,
      "tag",
      option_node(decl.loc, decl.tag, fn(tag) {
        let (value, loc) = tag
        node(loc, "ConstrDecl::Tag", [
          field(loc, "value", string_leaf(loc, value)),
        ])
      }),
    ),
    field(
      decl.loc,
      "attrs",
      list_node(
        "ConstrDecl::AttrList",
        decl.loc,
        decl.attrs,
        attribute_to_subject_tree,
      ),
    ),
    field(decl.loc, "doc", doc_string_to_subject_tree(decl.doc)),
  ])
}

///|
fn field_decl_to_subject_tree(decl : @syntax.FieldDecl) -> Subject {
  node(decl.loc, "FieldDecl", [
    field(decl.loc, "name", field_name_to_subject_tree(decl.name)),
    field(decl.loc, "ty", type_to_subject_tree(decl.ty)),
    field(decl.loc, "mut", bool_leaf(decl.loc, decl.mut_)),
    field(decl.loc, "vis", visibility_to_subject_tree(decl.vis, decl.loc)),
    field(
      decl.loc,
      "attrs",
      list_node(
        "FieldDecl::AttrList",
        decl.loc,
        decl.attrs,
        attribute_to_subject_tree,
      ),
    ),
    field(decl.loc, "doc", doc_string_to_subject_tree(decl.doc)),
  ])
}

///|
fn type_desc_to_subject_tree(
  desc : @syntax.TypeDesc,
  loc : @basic.Location,
) -> Subject {
  match desc {
    Abstract => node(loc, "TypeDesc::Abstract", [])
    ExtensibleEnum(constrs) => {
      let constrs_loc = constr_decl_list_loc(loc, constrs)
      node(constrs_loc, "TypeDesc::ExtensibleEnum", [
        field(
          constrs_loc,
          "value",
          list_node(
            "TypeDesc::ExtensibleEnum::ConstrList", constrs_loc, constrs, constr_decl_to_subject_tree,
          ),
        ),
      ])
    }
    Error(exception_decl) =>
      node(loc, "TypeDesc::Error", [
        field(loc, "value", exception_decl_to_subject_tree(exception_decl, loc)),
      ])
    Variant(constrs) => {
      let constrs_loc = constr_decl_list_loc(loc, constrs)
      node(constrs_loc, "TypeDesc::Variant", [
        field(
          constrs_loc,
          "value",
          list_node(
            "TypeDesc::Variant::ConstrList", constrs_loc, constrs, constr_decl_to_subject_tree,
          ),
        ),
      ])
    }
    ExtendEnum(target~, constructors~) => {
      let constrs_loc = constr_decl_list_loc(loc, constructors)
      node(loc, "TypeDesc::ExtendEnum", [
        field(loc, "target", type_name_to_subject_tree(target)),
        field(
          loc,
          "constructors",
          list_node(
            "TypeDesc::ExtendEnum::ConstrList", constrs_loc, constructors, constr_decl_to_subject_tree,
          ),
        ),
      ])
    }
    Record(fields~, constr_decl~) =>
      match constr_decl {
        None =>
          node(loc, "TypeDesc::Record", [
            field(
              loc,
              "value",
              list_node(
                "TypeDesc::Record::FieldList", loc, fields, field_decl_to_subject_tree,
              ),
            ),
          ])
        Some(constr_decl) =>
          node(loc, "TypeDesc::Record", [
            field(
              loc,
              "value",
              list_node(
                "TypeDesc::Record::FieldList", loc, fields, field_decl_to_subject_tree,
              ),
            ),
            field(loc, "constr_decl", fun_decl_to_subject_tree(constr_decl)),
          ])
      }
    TupleStruct(types) => {
      let types_loc = type_list_loc(loc, types)
      node(types_loc, "TypeDesc::TupleStruct", [
        field(
          types_loc,
          "value",
          list_node(
            "TypeDesc::TupleStruct::TypeList", types_loc, types, type_to_subject_tree,
          ),
        ),
      ])
    }
    Alias(ty) =>
      node(ty.loc(), "TypeDesc::Alias", [
        field(ty.loc(), "value", type_to_subject_tree(ty)),
      ])
  }
}

///|
fn deriving_directive_to_subject_tree(
  directive : @syntax.DerivingDirective,
) -> Subject {
  node(directive.loc, "DerivingDirective", [
    field(
      directive.loc,
      "type_name",
      type_name_to_subject_tree(directive.type_name),
    ),
    field(
      directive.loc,
      "args",
      list_node(
        "DerivingDirective::ArgList",
        directive.loc,
        directive.args,
        argument_to_subject_tree,
      ),
    ),
  ])
}

///|
fn type_decl_to_subject_tree(decl : @syntax.TypeDecl) -> Subject {
  node(decl.loc, "TypeDecl", [
    field(decl.loc, "tycon", string_leaf(decl.loc, decl.tycon)),
    field(
      decl.loc,
      "params",
      list_node(
        "TypeDecl::ParamList",
        decl.loc,
        decl.params,
        type_decl_binder_to_subject_tree,
      ),
    ),
    field(
      decl.loc,
      "components",
      type_desc_to_subject_tree(decl.components, decl.loc),
    ),
    field(
      decl.loc,
      "attrs",
      list_node(
        "TypeDecl::AttrList",
        decl.loc,
        decl.attrs,
        attribute_to_subject_tree,
      ),
    ),
    field(decl.loc, "doc", doc_string_to_subject_tree(decl.doc)),
    field(
      decl.loc,
      "type_vis",
      visibility_to_subject_tree(decl.type_vis, decl.loc),
    ),
    field(decl.loc, "is_declare", bool_leaf(decl.loc, decl.is_declare)),
    field(
      decl.loc,
      "deriving",
      list_node(
        "TypeDecl::DerivingList",
        decl.loc,
        decl.deriving,
        deriving_directive_to_subject_tree,
      ),
    ),
  ])
}

///|
fn func_stubs_to_subject_tree(
  stubs : @syntax.FuncStubs,
  loc : @basic.Location,
) -> Subject {
  match stubs {
    Import(module_name~, func_name~, language~) =>
      node(loc, "FuncStubs::Import", [
        field(loc, "module_name", string_leaf(loc, module_name)),
        field(loc, "func_name", string_leaf(loc, func_name)),
        field(
          loc,
          "language",
          option_node(loc, language, fn(value) { string_leaf(loc, value) }),
        ),
      ])
    Embedded(language~, code~) =>
      node(loc, "FuncStubs::Embedded", [
        field(
          loc,
          "language",
          option_node(loc, language, fn(value) { string_leaf(loc, value) }),
        ),
        field(loc, "code", embedded_code_to_subject_tree(code, loc)),
      ])
  }
}

///|
fn embedded_code_to_subject_tree(
  code : @syntax.EmbeddedCode,
  loc : @basic.Location,
) -> Subject {
  match code {
    CodeString(value) =>
      node(loc, "EmbeddedCode::CodeString", [
        field(loc, "value", string_leaf(loc, value)),
      ])
    CodeMultilineString(strings) =>
      node(loc, "EmbeddedCode::CodeMultilineString", [
        field(
          loc,
          "value",
          list_node(
            "EmbeddedCode::CodeMultilineString::LiteralList",
            loc,
            strings,
            fn(value) { string_leaf(loc, value) },
          ),
        ),
      ])
  }
}

///|
fn decl_body_to_subject_tree(
  body : @syntax.DeclBody,
  loc : @basic.Location,
) -> Subject {
  match body {
    DeclBody(expr~) =>
      node(loc, "DeclBody::DeclBody", [
        field(
          loc,
          "local_types",
          empty_list_node("DeclBody::DeclBody::LocalTypeList", loc),
        ),
        field(loc, "expr", expr_to_subject_tree(expr)),
      ])
    DeclStubs(stubs) =>
      node(loc, "DeclBody::DeclStubs", [
        field(loc, "value", func_stubs_to_subject_tree(stubs, loc)),
      ])
    DeclNone => node(loc, "DeclBody::DeclNone", [])
  }
}

///|
fn fun_decl_to_subject_tree(decl : @syntax.FunDecl) -> Subject {
  node(decl.loc, "FunDecl", [
    field(
      decl.loc,
      "type_name",
      option_node(decl.loc, decl.type_name, type_name_to_subject_tree),
    ),
    field(decl.loc, "name", binder_to_subject_tree(decl.name)),
    field(decl.loc, "has_error", none_node(decl.loc)),
    field(
      decl.loc,
      "is_async",
      async_option_to_subject_tree(decl.loc, decl.is_async),
    ),
    field(
      decl.loc,
      "decl_params",
      option_node(decl.loc, decl.decl_params, fn(params) {
        list_node(
          "FunDecl::ParameterList",
          decl.params_loc,
          params,
          parameter_to_subject_tree,
        )
      }),
    ),
    field(
      decl.loc,
      "quantifiers",
      list_node(
        "FunDecl::QuantifierList",
        decl.params_loc,
        decl.quantifiers,
        type_var_binder_to_subject_tree,
      ),
    ),
    field(
      decl.loc,
      "return_type",
      option_node(decl.loc, decl.return_type, type_to_subject_tree),
    ),
    field(
      decl.loc,
      "error_type",
      error_type_to_subject_tree(decl.error_type, decl.loc),
    ),
    field(
      decl.loc,
      "vis",
      visibility_to_subject_tree(decl.vis, decl.params_loc),
    ),
    field(
      decl.loc,
      "attrs",
      list_node(
        "FunDecl::AttrList",
        decl.params_loc,
        decl.attrs,
        attribute_to_subject_tree,
      ),
    ),
    field(decl.loc, "doc", doc_string_to_subject_tree(decl.doc)),
  ])
}

///|
fn func_to_subject_tree(func : @syntax.Func) -> Subject {
  node(func.loc, "Func::Lambda", [
    field(
      func.loc,
      "parameters",
      list_node(
        "Func::Lambda::ParameterList",
        func.params_loc,
        func.parameters,
        parameter_to_subject_tree,
      ),
    ),
    field(func.loc, "body", expr_to_subject_tree(func.body)),
    field(
      func.loc,
      "return_type",
      option_node(func.loc, func.return_type, type_to_subject_tree),
    ),
    field(
      func.loc,
      "error_type",
      error_type_to_subject_tree(func.error_type, func.loc),
    ),
    field(func.loc, "kind", fn_kind_to_subject_tree(func.kind, func.loc)),
    field(func.loc, "has_error", none_node(func.loc)),
    field(
      func.loc,
      "is_async",
      async_option_to_subject_tree(func.loc, func.is_async),
    ),
  ])
}

///|
fn trait_method_decl_to_subject_tree(
  method_decl : @syntax.TraitMethodDecl,
) -> Subject {
  node(method_decl.loc, "TraitMethodDecl", [
    field(method_decl.loc, "name", binder_to_subject_tree(method_decl.name)),
    field(method_decl.loc, "has_error", none_node(method_decl.loc)),
    field(
      method_decl.loc,
      "is_async",
      async_option_to_subject_tree(method_decl.loc, method_decl.is_async),
    ),
    field(
      method_decl.loc,
      "quantifiers",
      list_node(
        "TraitMethodDecl::QuantifierList",
        method_decl.loc,
        method_decl.quantifiers,
        type_var_binder_to_subject_tree,
      ),
    ),
    field(
      method_decl.loc,
      "params",
      list_node(
        "TraitMethodDecl::ParamList",
        method_decl.loc,
        method_decl.params,
        parameter_to_subject_tree,
      ),
    ),
    field(
      method_decl.loc,
      "return_type",
      option_node(
        method_decl.loc,
        method_decl.return_type,
        type_to_subject_tree,
      ),
    ),
    field(
      method_decl.loc,
      "error_type",
      error_type_to_subject_tree(method_decl.error_type, method_decl.loc),
    ),
    field(
      method_decl.loc,
      "has_default",
      option_node(method_decl.loc, method_decl.has_default, fn(loc) {
        node(loc, "TraitMethodDecl::HasDefault", [])
      }),
    ),
    field(
      method_decl.loc,
      "attrs",
      list_node(
        "TraitMethodDecl::AttrList",
        method_decl.loc,
        method_decl.attrs,
        attribute_to_subject_tree,
      ),
    ),
  ])
}

///|
fn trait_decl_to_subject_tree(trait_decl : @syntax.TraitDecl) -> Subject {
  node(trait_decl.loc, "TraitDecl", [
    field(trait_decl.loc, "name", binder_to_subject_tree(trait_decl.name)),
    field(
      trait_decl.loc,
      "supers",
      list_node(
        "TraitDecl::SuperList",
        trait_decl.loc,
        trait_decl.supers,
        type_var_constraint_to_subject_tree,
      ),
    ),
    field(
      trait_decl.loc,
      "methods",
      list_node(
        "TraitDecl::MethodList",
        trait_decl.loc,
        trait_decl.methods,
        trait_method_decl_to_subject_tree,
      ),
    ),
    field(
      trait_decl.loc,
      "vis",
      visibility_to_subject_tree(trait_decl.vis, trait_decl.loc),
    ),
    field(
      trait_decl.loc,
      "is_declare",
      bool_leaf(trait_decl.loc, trait_decl.is_declare),
    ),
    field(
      trait_decl.loc,
      "attrs",
      list_node(
        "TraitDecl::AttrList",
        trait_decl.loc,
        trait_decl.attrs,
        attribute_to_subject_tree,
      ),
    ),
    field(trait_decl.loc, "doc", doc_string_to_subject_tree(trait_decl.doc)),
  ])
}

///|
fn test_name_to_subject_tree(
  name : (String, @basic.Location)?,
  loc : @basic.Location,
) -> Subject {
  option_node(loc, name, fn(test_name) {
    let (value, loc) = test_name
    node(loc, "TestName", [field(loc, "value", string_leaf(loc, value))])
  })
}

///|
fn alias_target_to_subject_tree(target : @syntax.AliasTarget) -> Subject {
  let loc = target.loc()
  node(loc, "AliasTarget", [
    field(loc, "binder", binder_to_subject_tree(target.binder)),
    field(loc, "target", option_node(loc, target.target, label_to_subject_tree)),
  ])
}

///|
fn using_kind_to_subject_tree(
  kind : @syntax.UsingKind,
  loc : @basic.Location,
) -> Subject {
  match kind {
    Value => string_leaf(loc, "value")
    Type => string_leaf(loc, "type")
    Trait => string_leaf(loc, "trait")
  }
}

///|
fn using_name_to_subject_tree(
  item : (@syntax.AliasTarget, @syntax.UsingKind),
) -> Subject {
  let (target, kind) = item
  let loc = target.loc()
  node(loc, "UsingName", [
    field(loc, "name", alias_target_to_subject_tree(target)),
    field(loc, "kind", using_kind_to_subject_tree(kind, loc)),
  ])
}

///|
pub fn expr_to_subject_tree(expr : @syntax.Expr) -> Subject {
  match expr {
    Apply(func~, args~, loc~) =>
      node(loc, "Expr::Apply", [
        field(loc, "func", expr_to_subject_tree(func)),
        field(
          loc,
          "args",
          list_node(
            "Expr::Apply::ArgumentList", loc, args, argument_to_subject_tree,
          ),
        ),
        field(loc, "attr", apply_attr_to_subject_tree(loc)),
      ])
    Infix(op~, lhs~, rhs~, loc~) =>
      node(loc, "Expr::Infix", [
        field(loc, "op", var_to_subject_tree(op)),
        field(loc, "lhs", expr_to_subject_tree(lhs)),
        field(loc, "rhs", expr_to_subject_tree(rhs)),
      ])
    Unary(op~, expr~, loc~) =>
      node(loc, "Expr::Unary", [
        field(loc, "op", var_to_subject_tree(op)),
        field(loc, "expr", expr_to_subject_tree(expr)),
      ])
    Array(exprs~, loc~) =>
      node(loc, "Expr::Array", [
        field(
          loc,
          "exprs",
          list_node("Expr::Array::ExprList", loc, exprs, expr_to_subject_tree),
        ),
      ])
    ArraySpread(elems~, loc~) =>
      node(loc, "Expr::ArraySpread", [
        field(
          loc,
          "elems",
          list_node(
            "Expr::ArraySpread::ElemList", loc, elems, spreadable_elem_to_subject_tree,
          ),
        ),
      ])
    ListComprehension(kind~, guard_~, body~, loc~) =>
      node(loc, "Expr::ListComprehension", [
        field(loc, "kind", list_comprehension_kind_to_subject_tree(kind, loc)),
        field(loc, "guard", option_node(loc, guard_, expr_to_subject_tree)),
        field(loc, "body", expr_to_subject_tree(body)),
      ])
    ArrayGet(array~, index~, loc~) =>
      node(loc, "Expr::ArrayGet", [
        field(loc, "array", expr_to_subject_tree(array)),
        field(loc, "index", expr_to_subject_tree(index)),
      ])
    ArrayGetSlice(array~, start_index~, end_index~, index_loc~, loc~) => {
      ignore(index_loc)
      node(loc, "Expr::ArrayGetSlice", [
        field(loc, "array", expr_to_subject_tree(array)),
        field(
          loc,
          "start_index",
          option_node(loc, start_index, expr_to_subject_tree),
        ),
        field(
          loc,
          "end_index",
          option_node(loc, end_index, expr_to_subject_tree),
        ),
      ])
    }
    ArraySet(array~, index~, value~, loc~) =>
      node(loc, "Expr::ArraySet", [
        field(loc, "array", expr_to_subject_tree(array)),
        field(loc, "index", expr_to_subject_tree(index)),
        field(loc, "value", expr_to_subject_tree(value)),
      ])
    ArrayAugmentedSet(op~, array~, index~, value~, loc~) =>
      node(loc, "Expr::ArrayAugmentedSet", [
        field(loc, "op", var_to_subject_tree(op)),
        field(loc, "array", expr_to_subject_tree(array)),
        field(loc, "index", expr_to_subject_tree(index)),
        field(loc, "value", expr_to_subject_tree(value)),
      ])
    Constant(c~, loc~) =>
      node(loc, "Expr::Constant", [
        field(loc, "constant", constant_to_subject_tree(loc, c)),
      ])
    MultilineString(elems~, loc~) =>
      node(loc, "Expr::MultilineString", [
        field(
          loc,
          "elems",
          list_node("Expr::MultilineString::ElemList", loc, elems, fn(elem) {
            multiline_string_elem_to_subject_tree(elem, loc)
          }),
        ),
      ])
    Interp(elems~, loc~) =>
      node(loc, "Expr::Interp", [
        field(
          loc,
          "elems",
          list_node(
            "Expr::Interp::ElemList", loc, elems, interp_elem_to_subject_tree,
          ),
        ),
      ])
    Constraint(expr~, ty~, loc~) =>
      node(loc, "Expr::Constraint", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "ty", type_to_subject_tree(ty)),
      ])
    Constr(constr~, loc~) =>
      node(loc, "Expr::Constr", [
        field(loc, "constr", constructor_to_subject_tree(constr)),
      ])
    While(loop_cond~, loop_body~, while_else~, label~, loc~) =>
      node(loc, "Expr::While", [
        field(loc, "loop_cond", expr_to_subject_tree(loop_cond)),
        field(loc, "loop_body", expr_to_subject_tree(loop_body)),
        field(
          loc,
          "while_else",
          option_node(loc, while_else, expr_to_subject_tree),
        ),
        field(loc, "label", option_node(loc, label, label_to_subject_tree)),
      ])
    Function(func~, loc~) =>
      node(loc, "Expr::Function", [
        field(loc, "func", func_to_subject_tree(func)),
      ])
    Ident(id~, loc~) =>
      node(loc, "Expr::Ident", [field(loc, "id", var_to_subject_tree(id))])
    If(cond~, ifso~, ifnot~, loc~) =>
      node(loc, "Expr::If", [
        field(loc, "cond", expr_to_subject_tree(cond)),
        field(loc, "ifso", expr_to_subject_tree(ifso)),
        field(loc, "ifnot", option_node(loc, ifnot, expr_to_subject_tree)),
      ])
    Guard(cond~, otherwise~, body~, loc~) =>
      node(loc, "Expr::Guard", [
        field(loc, "cond", expr_to_subject_tree(cond)),
        field(
          loc,
          "otherwise",
          option_node(loc, otherwise, expr_to_subject_tree),
        ),
        field(loc, "body", expr_to_subject_tree(body)),
      ])
    Is(expr~, pat~, loc~) =>
      node(loc, "Expr::Is", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "pat", pattern_to_subject_tree(pat)),
      ])
    IsLexMatch(expr~, strategy~, pat~, pat_loc~, loc~) =>
      node(loc, "Expr::IsLexmatch", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(
          loc,
          "strategy",
          option_node(loc, strategy, label_to_subject_tree),
        ),
        field(
          loc,
          "pat",
          list_node("Expr::IsLexmatch::PatternList", pat_loc, pat, fn(pattern) {
            lex_top_pattern_to_subject_tree(pattern, pat_loc)
          }),
        ),
      ])
    RegexMatch(expr~, pat~, bindings~, loc~) =>
      node(loc, "Expr::RegexMatch", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "pat", regex_pattern_to_subject_tree(pat)),
        field(
          loc,
          "bindings",
          list_node("Expr::RegexMatch::BindingList", loc, bindings, fn(
            binding,
          ) {
            let (label, binder) = binding
            node(label.loc, "Expr::RegexMatch::Binding", [
              field(label.loc, "label", label_to_subject_tree(label)),
              field(
                label.loc,
                "binder",
                option_node(label.loc, binder, binder_to_subject_tree),
              ),
            ])
          }),
        ),
      ])
    Defer(expr~, body~, loc~) =>
      node(loc, "Expr::Defer", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "body", expr_to_subject_tree(body)),
      ])
    LetFn(name~, func~, body~, loc~) =>
      node(loc, "Expr::LetFn", [
        field(loc, "name", binder_to_subject_tree(name)),
        field(loc, "func", func_to_subject_tree(func)),
        field(loc, "body", expr_to_subject_tree(body)),
      ])
    LetAnd(bindings~, body~, loc~) =>
      node(loc, "Expr::LetAnd", [
        field(
          loc,
          "bindings",
          list_node("Expr::LetAnd::BindingList", loc, bindings, fn(binding) {
            let (binder, ty, func) = binding
            node(loc, "LetAnd::Binding", [
              field(loc, "binder", binder_to_subject_tree(binder)),
              field(loc, "type", option_node(loc, ty, type_to_subject_tree)),
              field(loc, "func", func_to_subject_tree(func)),
            ])
          }),
        ),
        field(loc, "body", expr_to_subject_tree(body)),
      ])
    Let(pattern~, expr~, body~, loc~) =>
      node(loc, "Expr::Let", [
        field(loc, "pattern", pattern_to_subject_tree(pattern)),
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "body", expr_to_subject_tree(body)),
      ])
    Sequence(exprs~, last_expr~, loc~) =>
      node(loc, "Expr::Sequence", [
        field(
          loc,
          "exprs",
          list_node(
            "Expr::Sequence::ExprList", loc, exprs, expr_to_subject_tree,
          ),
        ),
        field(loc, "last_expr", expr_to_subject_tree(last_expr)),
      ])
    Tuple(exprs~, loc~) =>
      node(loc, "Expr::Tuple", [
        field(
          loc,
          "exprs",
          list_node("Expr::Tuple::ExprList", loc, exprs, expr_to_subject_tree),
        ),
      ])
    Record(type_name~, fields~, trailing~, loc~) =>
      node(loc, "Expr::Record", [
        field(
          loc,
          "type_name",
          option_node(loc, type_name, type_name_to_subject_tree),
        ),
        field(
          loc,
          "fields",
          list_node(
            "Expr::Record::FieldList", loc, fields, field_def_to_subject_tree,
          ),
        ),
        field(loc, "trailing", trailing_mark_to_subject_tree(trailing, loc)),
      ])
    RecordUpdate(type_name~, record~, fields~, loc~) =>
      node(loc, "Expr::RecordUpdate", [
        field(
          loc,
          "type_name",
          option_node(loc, type_name, type_name_to_subject_tree),
        ),
        field(loc, "record", expr_to_subject_tree(record)),
        field(
          loc,
          "fields",
          list_node(
            "Expr::RecordUpdate::FieldList", loc, fields, field_def_to_subject_tree,
          ),
        ),
      ])
    Field(record~, accessor~, loc~) =>
      node(loc, "Expr::Field", [
        field(loc, "record", expr_to_subject_tree(record)),
        field(loc, "accessor", accessor_to_subject_tree(accessor)),
      ])
    Method(type_name~, method_name~, loc~) =>
      node(loc, "Expr::Method", [
        field(loc, "type_name", type_name_to_subject_tree(type_name)),
        field(loc, "method_name", label_to_subject_tree(method_name)),
      ])
    DotApply(self~, method_name~, args~, return_self~, loc~) =>
      node(loc, "Expr::DotApply", [
        field(loc, "self", expr_to_subject_tree(self)),
        field(loc, "method_name", label_to_subject_tree(method_name)),
        field(
          loc,
          "args",
          list_node(
            "Expr::DotApply::ArgList", loc, args, argument_to_subject_tree,
          ),
        ),
        field(loc, "return_self", bool_leaf(loc, return_self)),
        field(loc, "attr", apply_attr_to_subject_tree(loc)),
      ])
    As(expr~, trait_~, loc~) =>
      node(loc, "Expr::As", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "trait", type_name_to_subject_tree(trait_)),
      ])
    Mutate(record~, accessor~, field=field_expr, augmented_by~, loc~) =>
      node(loc, "Expr::Mutate", [
        field(loc, "record", expr_to_subject_tree(record)),
        field(loc, "accessor", accessor_to_subject_tree(accessor)),
        field(loc, "field", expr_to_subject_tree(field_expr)),
        field(
          loc,
          "augmented_by",
          option_node(loc, augmented_by, var_to_subject_tree),
        ),
      ])
    Match(expr~, cases~, match_loc~, loc~) => {
      ignore(match_loc)
      node(loc, "Expr::Match", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(
          loc,
          "cases",
          list_node("Expr::Match::CaseList", loc, cases, case_to_subject_tree),
        ),
      ])
    }
    LexMatch(strategy~, expr~, match_loc~, cases~, loc~) => {
      ignore(match_loc)
      node(loc, "Expr::Lexmatch", [
        field(
          loc,
          "strategy",
          option_node(loc, strategy, label_to_subject_tree),
        ),
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(
          loc,
          "cases",
          list_node("Expr::Lexmatch::CaseList", loc, cases, fn(case_) {
            lex_case_to_subject_tree(case_, loc)
          }),
        ),
      ])
    }
    LetMut(binder~, ty~, expr~, body~, loc~) =>
      node(loc, "Expr::LetMut", [
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(loc, "ty", option_node(loc, ty, type_to_subject_tree)),
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "body", expr_to_subject_tree(body)),
      ])
    Pipe(lhs~, rhs~, loc~) =>
      node(loc, "Expr::Pipe", [
        field(loc, "lhs", expr_to_subject_tree(lhs)),
        field(loc, "rhs", expr_to_subject_tree(rhs)),
      ])
    RevPipe(lhs~, rhs~, loc~) =>
      node(loc, "Expr::RevPipe", [
        field(loc, "lhs", expr_to_subject_tree(lhs)),
        field(loc, "rhs", expr_to_subject_tree(rhs)),
      ])
    Assign(var_~, expr~, augmented_by~, loc~) =>
      node(loc, "Expr::Assign", [
        field(loc, "var", var_to_subject_tree(var_)),
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(
          loc,
          "augmented_by",
          option_node(loc, augmented_by, var_to_subject_tree),
        ),
      ])
    Hole(loc~, kind~) =>
      node(loc, "Expr::Hole", [
        field(loc, "kind", hole_to_subject_tree(kind, loc)),
      ])
    Return(return_value~, loc~) =>
      node(loc, "Expr::Return", [
        field(
          loc,
          "return_value",
          option_node(loc, return_value, expr_to_subject_tree),
        ),
      ])
    Raise(err_value~, loc~) =>
      node(loc, "Expr::Raise", [
        field(loc, "err_value", expr_to_subject_tree(err_value)),
      ])
    Quantifier(kind~, binder~, binder_ty~, body~, loc~) =>
      node(loc, "Expr::Quantifier", [
        field(loc, "kind", predicate_quantifier_kind_to_subject_tree(kind, loc)),
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(loc, "binder_ty", type_to_subject_tree(binder_ty)),
        field(loc, "body", expr_to_subject_tree(body)),
      ])
    Implies(lhs~, rhs~, loc~) =>
      node(loc, "Expr::Implies", [
        field(loc, "lhs", expr_to_subject_tree(lhs)),
        field(loc, "rhs", expr_to_subject_tree(rhs)),
      ])
    ProofAssert(expr~, loc~) =>
      node(loc, "Expr::ProofAssert", [
        field(loc, "expr", expr_to_subject_tree(expr)),
      ])
    ProofLet(binder~, expr~, loc~) =>
      node(loc, "Expr::ProofLet", [
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(loc, "expr", expr_to_subject_tree(expr)),
      ])
    Unit(loc~, faked~) =>
      node(loc, "Expr::Unit", [field(loc, "faked", bool_leaf(loc, faked))])
    Break(arg~, label~, loc~) =>
      node(loc, "Expr::Break", [
        field(loc, "arg", option_node(loc, arg, expr_to_subject_tree)),
        field(loc, "label", option_node(loc, label, label_to_subject_tree)),
      ])
    Continue(args~, label~, loc~) =>
      node(loc, "Expr::Continue", [
        field(
          loc,
          "args",
          list_node("Expr::Continue::ExprList", loc, args, expr_to_subject_tree),
        ),
        field(loc, "label", option_node(loc, label, label_to_subject_tree)),
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
      node(loc, "Expr::For", [
        field(
          loc,
          "binders",
          list_node("Expr::For::BindingList", loc, binders, fn(binding) {
            let (binder, expr) = binding
            for_binding_to_subject_tree(loc, binder, expr)
          }),
        ),
        field(
          loc,
          "condition",
          option_node(loc, condition, expr_to_subject_tree),
        ),
        field(
          loc,
          "continue_block",
          list_node("Expr::For::ContBindingList", loc, continue_block, fn(
            binding,
          ) {
            let (binder, expr) = binding
            for_cont_binding_to_subject_tree(loc, binder, expr)
          }),
        ),
        field(loc, "body", expr_to_subject_tree(body)),
        field(loc, "for_else", option_node(loc, for_else, expr_to_subject_tree)),
        field(
          loc,
          "where_clause",
          option_node(loc, where_clause, where_clause_to_subject_tree),
        ),
        field(loc, "label", option_node(loc, label, label_to_subject_tree)),
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
      node(loc, "Expr::ForEach", [
        field(
          loc,
          "binders",
          list_node("Expr::ForEach::BinderList", loc, binders, fn(binder) {
            option_node(loc, binder, binder_to_subject_tree)
          }),
        ),
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(
          loc,
          "init",
          list_node("Expr::ForEach::Init", loc, init, fn(binding) {
            let (binder, expr) = binding
            foreach_init_to_subject_tree(loc, binder, expr)
          }),
        ),
        field(
          loc,
          "continue_block",
          list_node("Expr::ForEach::ContinueBlock", loc, continue_block, fn(
            binding,
          ) {
            let (binder, expr) = binding
            foreach_continue_to_subject_tree(loc, binder, expr)
          }),
        ),
        field(loc, "body", expr_to_subject_tree(body)),
        field(
          loc,
          "else_block",
          option_node(loc, else_block, expr_to_subject_tree),
        ),
        field(
          loc,
          "where_clause",
          option_node(loc, where_clause, where_clause_to_subject_tree),
        ),
        field(loc, "label", option_node(loc, label, label_to_subject_tree)),
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
      node(loc, "Expr::Try", [
        field(loc, "body", expr_to_subject_tree(body)),
        field(
          loc,
          "catch",
          list_node("Expr::Try::CaseList", loc, catch_, case_to_subject_tree),
        ),
        field(loc, "catch_all", bool_leaf(loc, false)),
        field(
          loc,
          "try_else",
          option_node(loc, try_else, fn(cases) {
            list_node(
              "Expr::Try::CaseList", else_loc, cases, case_to_subject_tree,
            )
          }),
        ),
        field(loc, "has_try", bool_leaf(loc, has_try)),
      ])
    }
    TryOperator(body~, kind~, try_loc~, loc~) => {
      ignore(try_loc)
      node(loc, "Expr::TryOperator", [
        field(loc, "body", expr_to_subject_tree(body)),
        field(loc, "kind", try_operator_kind_to_subject_tree(kind, loc)),
      ])
    }
    Map(elems~, loc~) =>
      node(loc, "Expr::Map", [
        field(
          loc,
          "elems",
          list_node(
            "Expr::Map::ElemList", loc, elems, map_expr_elem_to_subject_tree,
          ),
        ),
      ])
    Group(expr~, group~, loc~) =>
      node(loc, "Expr::Group", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "group", group_to_subject_tree(group, loc)),
      ])
    TemplateWriting(expr~, template~, loc~) =>
      node(loc, "Expr::TemplateWriting", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "template", expr_to_subject_tree(template)),
      ])
    StaticAssert(asserts~, body~) => {
      let loc = body.loc()
      node(loc, "Expr::StaticAssert", [
        field(
          loc,
          "asserts",
          list_node(
            "Expr::StaticAssert::StaticAssertionList", loc, asserts, static_assertion_to_subject_tree,
          ),
        ),
        field(loc, "body", expr_to_subject_tree(body)),
      ])
    }
  }
}

///|
pub fn impl_to_subject_tree(impl_ : @syntax.Impl) -> Subject {
  match impl_ {
    TopExpr(expr~, is_main~, is_async~, loc~) =>
      node(loc, "Impl::TopExpr", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "is_main", bool_leaf(loc, is_main)),
        field(
          loc,
          "local_types",
          empty_list_node("Impl::TopExpr::LocalTypeList", loc),
        ),
        field(loc, "is_async", option_node(loc, is_async, async_node)),
      ])
    TopTest(expr~, name~, params~, is_async~, loc~, attrs~, doc~) =>
      node(loc, "Impl::TopTest", [
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "name", test_name_to_subject_tree(name, loc)),
        field(
          loc,
          "params",
          option_node(loc, params, fn(params) {
            list_node(
              "Impl::TopTest::ParamList", loc, params, parameter_to_subject_tree,
            )
          }),
        ),
        field(
          loc,
          "local_types",
          empty_list_node("Impl::TopTest::LocalTypeList", loc),
        ),
        field(loc, "is_async", async_option_to_subject_tree(loc, is_async)),
        field(
          loc,
          "attrs",
          list_node(
            "Impl::TopTest::AttrList", loc, attrs, attribute_to_subject_tree,
          ),
        ),
        field(loc, "doc", doc_string_to_subject_tree(doc)),
      ])
    TopTypeDef(type_decl) =>
      node(type_decl.loc, "Impl::TopTypeDef", [
        field(type_decl.loc, "value", type_decl_to_subject_tree(type_decl)),
      ])
    TopFuncDef(fun_decl~, decl_body~, where_clause~, loc~) =>
      node(loc, "Impl::TopFuncDef", [
        field(loc, "fun_decl", fun_decl_to_subject_tree(fun_decl)),
        field(
          loc,
          "where_clause",
          option_node(loc, where_clause, where_clause_to_subject_tree),
        ),
        field(loc, "decl_body", decl_body_to_subject_tree(decl_body, loc)),
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
      node(loc, "Impl::TopLetDef", [
        field(loc, "binder", binder_to_subject_tree(binder)),
        field(loc, "ty", option_node(loc, ty, type_to_subject_tree)),
        field(loc, "expr", expr_to_subject_tree(expr)),
        field(loc, "vis", visibility_to_subject_tree(vis, loc)),
        field(loc, "is_constant", bool_leaf(loc, is_constant)),
        field(loc, "is_declare", bool_leaf(loc, is_declare)),
        field(
          loc,
          "attrs",
          list_node(
            "Impl::TopLetDef::AttrList", loc, attrs, attribute_to_subject_tree,
          ),
        ),
        field(loc, "doc", doc_string_to_subject_tree(doc)),
      ])
    TopTrait(trait_decl) =>
      node(trait_decl.loc, "Impl::TopTrait", [
        field(trait_decl.loc, "value", trait_decl_to_subject_tree(trait_decl)),
      ])
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
      node(loc, "Impl::TopImpl", [
        field(loc, "self_ty", option_node(loc, self_ty, type_to_subject_tree)),
        field(loc, "trait", type_name_to_subject_tree(trait_)),
        field(loc, "method_name", binder_to_subject_tree(method_name)),
        field(loc, "has_error", none_node(loc)),
        field(
          loc,
          "quantifiers",
          list_node(
            "Impl::TopImpl::QuantifierList", loc, quantifiers, type_var_binder_to_subject_tree,
          ),
        ),
        field(
          loc,
          "params",
          list_node(
            "Impl::TopImpl::ParamList", loc, params, parameter_to_subject_tree,
          ),
        ),
        field(loc, "ret_ty", option_node(loc, ret_ty, type_to_subject_tree)),
        field(loc, "err_ty", error_type_to_subject_tree(err_ty, loc)),
        field(loc, "body", decl_body_to_subject_tree(body, loc)),
        field(loc, "vis", visibility_to_subject_tree(vis, loc)),
        field(
          loc,
          "attrs",
          list_node(
            "Impl::TopImpl::AttrList", loc, attrs, attribute_to_subject_tree,
          ),
        ),
        field(loc, "doc", doc_string_to_subject_tree(doc)),
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
      node(loc, "Impl::TopView", [
        field(
          loc,
          "quantifiers",
          list_node(
            "Impl::TopView::QuantifierList", loc, quantifiers, type_var_binder_to_subject_tree,
          ),
        ),
        field(loc, "source_ty", type_to_subject_tree(source_ty)),
        field(
          loc,
          "view_constrs",
          list_node(
            "Impl::TopView::ConstrList", params_loc, view_constrs, constr_decl_to_subject_tree,
          ),
        ),
        field(loc, "body", expr_to_subject_tree(body)),
        field(loc, "ty_name", string_leaf(loc, view_type_name)),
        field(
          loc,
          "parameters",
          list_node(
            "Impl::TopView::ParameterList", loc, parameters, parameter_to_subject_tree,
          ),
        ),
        field(loc, "func_name", binder_to_subject_tree(view_func_name)),
        field(loc, "vis", visibility_to_subject_tree(vis, loc)),
        field(
          loc,
          "attrs",
          list_node(
            "Impl::TopView::AttrList", loc, attrs, attribute_to_subject_tree,
          ),
        ),
        field(loc, "doc", doc_string_to_subject_tree(doc)),
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
      node(loc, "Impl::TopImplRelation", [
        field(loc, "self_ty", type_to_subject_tree(self_ty)),
        field(loc, "trait", type_name_to_subject_tree(trait_)),
        field(
          loc,
          "quantifiers",
          list_node(
            "Impl::TopImplRelation::QuantifierList", loc, quantifiers, type_var_binder_to_subject_tree,
          ),
        ),
        field(loc, "vis", visibility_to_subject_tree(vis, loc)),
        field(loc, "is_declare", bool_leaf(loc, is_declare)),
        field(
          loc,
          "attrs",
          list_node(
            "Impl::TopImplRelation::AttrList", loc, attrs, attribute_to_subject_tree,
          ),
        ),
        field(loc, "doc", doc_string_to_subject_tree(doc)),
      ])
    TopUsing(pkg~, names~, vis~, attrs~, loc~, doc~) =>
      node(loc, "Impl::TopUsing", [
        field(loc, "pkg", label_to_subject_tree(pkg)),
        field(
          loc,
          "names",
          list_node(
            "Impl::TopUsing::NameList", loc, names, using_name_to_subject_tree,
          ),
        ),
        field(loc, "vis", visibility_to_subject_tree(vis, loc)),
        field(
          loc,
          "attrs",
          list_node(
            "Impl::TopUsing::AttrList", loc, attrs, attribute_to_subject_tree,
          ),
        ),
        field(loc, "doc", doc_string_to_subject_tree(doc)),
      ])
  }
}
