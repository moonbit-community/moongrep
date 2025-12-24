///|
enum ConvertMode {
  Pattern
  Target
}

///|
let current_convert_mode : Ref[ConvertMode] = Ref::new(Target)

///|
fn LabelledTree::from_binder(binder : @syntax.Binder) -> LabelledTree {
  if binder.name == "___" && current_convert_mode.val is Pattern {
    return LabelledTree::wildcard(binder.loc)
  } else {
    LabelledTree::node(binder.loc, "Binder(\{binder.name})", [])
  }
}

///|
fn LabelledTree::from_pattern(pattern : @syntax.Pattern) -> LabelledTree {
  match pattern {
    Alias(pat~, alias_~, loc~) => {
      let childs = [
        LabelledTree::from_pattern(pat),
        LabelledTree::from_binder(alias_),
      ]
      LabelledTree::node(loc, "Pattern::Alias", childs)
    }
    Any(loc~) => LabelledTree::node(loc, "Pattern::Any", [])
    Array(pats~, loc~) => {
      let childs = []
      match pats {
        Closed(array_pats) =>
          array_pats.each(array_pat => match array_pat {
            Pattern(pat) => childs.push(LabelledTree::from_pattern(pat))
            StringSpread(str~, loc~) =>
              childs.push(LabelledTree::node(loc, "StringSpread(\{str})", []))
            BytesSpread(bytes~, loc~) =>
              childs.push(LabelledTree::node(loc, "BytesSpread(\{bytes})", []))
            ConstSpread(binder~, pkg~, loc~) => {
              let pkg_label = match pkg {
                Some(p) => "Package(\{p})"
                None => "NoPackage"
              }
              let spread_childs = [
                LabelledTree::from_binder(binder),
                LabelledTree::node(loc, pkg_label, []),
              ]
              childs.push(LabelledTree::node(loc, "ConstSpread", spread_childs))
            }
          })
        Open(before_pats, after_pats, dotdot_binder) => {
          before_pats.each(array_pat => match array_pat {
            Pattern(pat) => childs.push(LabelledTree::from_pattern(pat))
            StringSpread(str~, loc~) =>
              childs.push(LabelledTree::node(loc, "StringSpread(\{str})", []))
            BytesSpread(bytes~, loc~) =>
              childs.push(LabelledTree::node(loc, "BytesSpread(\{bytes})", []))
            ConstSpread(binder~, pkg~, loc~) => {
              let pkg_label = match pkg {
                Some(p) => "Package(\{p})"
                None => "NoPackage"
              }
              let spread_childs = [
                LabelledTree::from_binder(binder),
                LabelledTree::node(loc, pkg_label, []),
              ]
              childs.push(LabelledTree::node(loc, "ConstSpread", spread_childs))
            }
          })
          match dotdot_binder {
            Underscore =>
              childs.push(LabelledTree::node(loc, "DotDot::Underscore", []))
            NoBinder =>
              childs.push(LabelledTree::node(loc, "DotDot::NoBinder", []))
            BinderAs(binder) =>
              childs.push(
                LabelledTree::node(
                  binder.loc,
                  "DotDot::BinderAs(\{binder.name})",
                  [],
                ),
              )
            Binder(binder) =>
              childs.push(
                LabelledTree::node(
                  binder.loc,
                  "DotDot::Binder(\{binder.name})",
                  [],
                ),
              )
          }
          after_pats.each(array_pat => match array_pat {
            Pattern(pat) => childs.push(LabelledTree::from_pattern(pat))
            StringSpread(str~, loc~) =>
              childs.push(LabelledTree::node(loc, "StringSpread(\{str})", []))
            BytesSpread(bytes~, loc~) =>
              childs.push(LabelledTree::node(loc, "BytesSpread(\{bytes})", []))
            ConstSpread(binder~, pkg~, loc~) => {
              let pkg_label = match pkg {
                Some(p) => "Package(\{p})"
                None => "NoPackage"
              }
              let spread_childs = [
                LabelledTree::from_binder(binder),
                LabelledTree::node(loc, pkg_label, []),
              ]
              childs.push(LabelledTree::node(loc, "ConstSpread", spread_childs))
            }
          })
        }
      }
      LabelledTree::node(loc, "Pattern::Array", childs)
    }
    Constant(c~, loc~) => {
      let label = match c {
        String(s) => "Constant::String(\{s})"
        Double(d) => "Constant::Double(\{d})"
        Int(i) => "Constant::Int(\{i})"
        Float(f) => "Constant::Float(\{f})"
        UInt64(u) => "Constant::UInt64(\{u})"
        UInt(u) => "Constant::UInt(\{u})"
        Int64(i) => "Constant::Int64(\{i})"
        Char(c) => "Constant::Char(\{c})"
        Bool(b) => "Constant::Bool(\{b})"
        Bytes(b) => "Constant::Bytes(\{b})"
        Byte(b) => "Constant::Byte(\{b})"
        BigInt(i) => "Constant::BigInt(\{i})"
      }
      LabelledTree::node(loc, label, [])
    }
    Constraint(pat~, ty~, loc~) => {
      let childs = [
        LabelledTree::from_pattern(pat),
        LabelledTree::from_type(ty),
      ]
      LabelledTree::node(loc, "Pattern::Constraint", childs)
    }
    Constr(constr~, args~, is_open~, loc~) => {
      let childs = [LabelledTree::from_constructor(constr)]
      match args {
        Some(arg_list) =>
          arg_list.each(arg => {
            let arg_childs = [LabelledTree::from_pattern(arg.pat)]
            let kind_label = match arg.kind {
              Positional => "ArgumentKind::Positional"
              Labelled(label) => "ArgumentKind::Labelled(\{label.name})"
              LabelledPun(label) => "ArgumentKind::LabelledPun(\{label.name})"
              LabelledOption(label~, question_loc~) =>
                "ArgumentKind::LabelledOption(\{label.name})"
              LabelledOptionPun(label~, question_loc~) =>
                "ArgumentKind::LabelledOptionPun(\{label.name})"
            }
            arg_childs.push(LabelledTree::node(loc, kind_label, []))
            childs.push(LabelledTree::node(loc, "ConstrPatArg", arg_childs))
          })
        None => ()
      }
      childs.push(LabelledTree::node(loc, "IsOpen(\{is_open})", []))
      LabelledTree::node(loc, "Pattern::Constr", childs)
    }
    Or(pat1~, pat2~, loc~) => {
      let childs = [
        LabelledTree::from_pattern(pat1),
        LabelledTree::from_pattern(pat2),
      ]
      LabelledTree::node(loc, "Pattern::Or", childs)
    }
    Tuple(pats~, loc~) => {
      let childs = []
      pats.each(pat => childs.push(LabelledTree::from_pattern(pat)))
      LabelledTree::node(loc, "Pattern::Tuple", childs)
    }
    Var(binder) =>
      LabelledTree::node(binder.loc, "Pattern::Var(\{binder.name})", [])
    Record(fields~, is_closed~, loc~) => {
      let childs = []
      fields.each(field => {
        let field_childs = [LabelledTree::from_pattern(field.pattern)]
        field_childs.push(
          LabelledTree::node(field.label.loc, "Label(\{field.label.name})", []),
        )
        field_childs.push(
          LabelledTree::node(field.loc, "IsPun(\{field.is_pun})", []),
        )
        childs.push(LabelledTree::node(field.loc, "FieldPat", field_childs))
      })
      childs.push(LabelledTree::node(loc, "IsClosed(\{is_closed})", []))
      LabelledTree::node(loc, "Pattern::Record", childs)
    }
    Map(elems~, is_closed~, loc~) => {
      let childs = []
      elems.each(elem => {
        let elem_childs = [LabelledTree::from_pattern(elem.pat)]
        let key_label = match elem.key {
          String(s) => "Constant::String(\{s})"
          Double(d) => "Constant::Double(\{d})"
          Int(i) => "Constant::Int(\{i})"
          Float(f) => "Constant::Float(\{f})"
          UInt64(u) => "Constant::UInt64(\{u})"
          UInt(u) => "Constant::UInt(\{u})"
          Int64(i) => "Constant::Int64(\{i})"
          Char(c) => "Constant::Char(\{c})"
          Bool(b) => "Constant::Bool(\{b})"
          Bytes(b) => "Constant::Bytes(\{b})"
          Byte(b) => "Constant::Byte(\{b})"
          BigInt(i) => "Constant::BigInt(\{i})"
        }
        elem_childs.push(LabelledTree::node(elem.key_loc, key_label, []))
        elem_childs.push(
          LabelledTree::node(elem.loc, "MatchAbsent(\{elem.match_absent})", []),
        )
        childs.push(LabelledTree::node(elem.loc, "MapPatElem", elem_childs))
      })
      childs.push(LabelledTree::node(loc, "IsClosed(\{is_closed})", []))
      LabelledTree::node(loc, "Pattern::Map", childs)
    }
    Range(lhs~, rhs~, kind~, loc~) => {
      let childs = [
        LabelledTree::from_pattern(lhs),
        LabelledTree::from_pattern(rhs),
      ]
      let kind_label = match kind {
        Inclusive => "RangeKind::Inclusive"
        Exclusive => "RangeKind::Exclusive"
        InclusiveMissingEqual => "RangeKind::InclusiveMissingEqual"
      }
      childs.push(LabelledTree::node(loc, kind_label, []))
      LabelledTree::node(loc, "Pattern::Range", childs)
    }
    SpecialConstr(binder~, args~, loc~) => {
      let childs = [LabelledTree::from_binder(binder)]
      args.each(arg => {
        let arg_childs = [LabelledTree::from_pattern(arg.pat)]
        let kind_label = match arg.kind {
          Positional => "ArgumentKind::Positional"
          Labelled(label) => "ArgumentKind::Labelled(\{label.name})"
          LabelledPun(label) => "ArgumentKind::LabelledPun(\{label.name})"
          LabelledOption(label~, question_loc~) =>
            "ArgumentKind::LabelledOption(\{label.name})"
          LabelledOptionPun(label~, question_loc~) =>
            "ArgumentKind::LabelledOptionPun(\{label.name})"
        }
        arg_childs.push(LabelledTree::node(loc, kind_label, []))
        childs.push(LabelledTree::node(loc, "ConstrPatArg", arg_childs))
      })
      LabelledTree::node(loc, "Pattern::SpecialConstr", childs)
    }
  }
}

///|
fn LabelledTree::from_type(ty : @syntax.Type) -> LabelledTree {
  match ty {
    Any(loc~) => LabelledTree::node(loc, "Type::Any", [])
    Arrow(args~, res~, err~, is_async~, loc~) => {
      let childs = []
      args.each(arg => childs.push(LabelledTree::from_type(arg)))
      childs.push(LabelledTree::from_type(res))
      let err_tree = match err {
        ErrorType(ty~) => LabelledTree::from_type(ty)
        DefaultErrorType(loc~) =>
          LabelledTree::node(loc, "ErrorType::DefaultErrorType", [])
        NoErrorType => LabelledTree::node(loc, "ErrorType::NoErrorType", [])
        Noraise(loc~) => LabelledTree::node(loc, "ErrorType::Noraise", [])
        MaybeError(ty~) => LabelledTree::from_type(ty)
      }
      childs.push(err_tree)
      childs.push(LabelledTree::node(loc, "IsAsync(\{is_async})", []))
      LabelledTree::node(loc, "Type::Arrow", childs)
    }
    Tuple(tys~, loc~) => {
      let childs = []
      tys.each(ty => childs.push(LabelledTree::from_type(ty)))
      LabelledTree::node(loc, "Type::Tuple", childs)
    }
    Name(constr_id~, tys~, loc~) => {
      let childs = []
      let id_name = match constr_id.id {
        Ident(name~) => name
        Dot(pkg~, id~) => "\{pkg}.\{id}"
      }
      childs.push(LabelledTree::node(constr_id.loc, "ConstrId(\{id_name})", []))
      tys.each(ty => childs.push(LabelledTree::from_type(ty)))
      LabelledTree::node(loc, "Type::Name", childs)
    }
    Option(ty~, loc~, question_loc~) => {
      let childs = [LabelledTree::from_type(ty)]
      LabelledTree::node(loc, "Type::Option", childs)
    }
    Object(constr_id) => {
      let id_name = match constr_id.id {
        Ident(name~) => name
        Dot(pkg~, id~) => "\{pkg}.\{id}"
      }
      LabelledTree::node(constr_id.loc, "Type::Object(\{id_name})", [])
    }
  }
}

///|
fn LabelledTree::from_lex_top_pattern(
  pat : @syntax.LexTopPattern,
) -> LabelledTree {
  match pat {
    Pattern(lex_pattern) => {
      fn from_lex_pattern(pattern : @syntax.LexPattern) -> LabelledTree {
        match pattern {
          Regex(lit~, loc~) =>
            LabelledTree::node(loc, "LexPattern::Regex(\{lit})", [])
          RegexInterp(elems~, loc~) => {
            let childs = []
            elems.each(elem => childs.push(LabelledTree::from_interp_elem(elem)))
            LabelledTree::node(loc, "LexPattern::RegexInterp", childs)
          }
          Alias(pat~, binder~, loc~) => {
            let childs = [
              from_lex_pattern(pat),
              LabelledTree::from_binder(binder),
            ]
            LabelledTree::node(loc, "LexPattern::Alias", childs)
          }
          Sequence(pats~, loc~) => {
            let childs = []
            pats.each(pat => childs.push(from_lex_pattern(pat)))
            LabelledTree::node(loc, "LexPattern::Sequence", childs)
          }
        }
      }

      from_lex_pattern(lex_pattern)
    }
    Binder(binder) =>
      LabelledTree::node(binder.loc, "LexTopPattern::Binder(\{binder.name})", [])
    Wildcard(loc~) => LabelledTree::node(loc, "LexTopPattern::Wildcard", [])
  }
}

///|
fn LabelledTree::from_accessor(accessor : @syntax.Accessor) -> LabelledTree {
  match accessor {
    Label(label) =>
      LabelledTree::node(label.loc, "Accessor::Label(\{label.name})", [])
    Index(tuple_index~, loc~) =>
      LabelledTree::node(loc, "Accessor::Index(\{tuple_index})", [])
    Newtype(loc~) => LabelledTree::node(loc, "Accessor::Newtype", [])
  }
}

///|
fn LabelledTree::from_type_name(type_name : @syntax.TypeName) -> LabelledTree {
  let name_str = match type_name.name {
    Ident(name~) => name
    Dot(pkg~, id~) => "\{pkg}.\{id}"
  }
  let label = if type_name.is_object {
    "TypeName::Object(\{name_str})"
  } else {
    "TypeName(\{name_str})"
  }
  LabelledTree::node(type_name.loc, label, [])
}

///|
fn LabelledTree::from_argument(arg : @syntax.Argument) -> LabelledTree {
  let childs = [LabelledTree::from_expr(arg.value)]
  let kind_label = match arg.kind {
    Positional => "ArgumentKind::Positional"
    Labelled(label) => "ArgumentKind::Labelled(\{label.name})"
    LabelledPun(label) => "ArgumentKind::LabelledPun(\{label.name})"
    LabelledOption(label~, question_loc~) => {
      ignore(question_loc)
      "ArgumentKind::LabelledOption(\{label.name})"
    }
    LabelledOptionPun(label~, question_loc~) => {
      ignore(question_loc)
      "ArgumentKind::LabelledOptionPun(\{label.name})"
    }
  }
  childs.push(LabelledTree::node(arg.value.loc(), kind_label, []))
  // TODO: use real argument location
  LabelledTree::node(arg.value.loc(), "Argument", childs)
}

///|
fn LabelledTree::from_field_def(field : @syntax.FieldDef) -> LabelledTree {
  let childs = [
    LabelledTree::node(field.label.loc, "Label(\{field.label.name})", []),
    LabelledTree::from_expr(field.expr),
    LabelledTree::node(field.loc, "IsPun(\{field.is_pun})", []),
  ]
  LabelledTree::node(field.loc, "FieldDef", childs)
}

///|
fn LabelledTree::from_func(func : @syntax.Func) -> LabelledTree {
  fn from_parameter(param : @syntax.Parameter) -> LabelledTree {
    match param {
      DiscardPositional(ty~, loc~) => {
        let childs = []
        match ty {
          Some(t) => childs.push(LabelledTree::from_type(t))
          None => ()
        }
        LabelledTree::node(loc, "Parameter::DiscardPositional", childs)
      }
      Positional(binder~, ty~) => {
        let childs = [LabelledTree::from_binder(binder)]
        match ty {
          Some(t) => childs.push(LabelledTree::from_type(t))
          None => ()
        }
        LabelledTree::node(binder.loc, "Parameter::Positional", childs)
      }
      Labelled(binder~, ty~) => {
        let childs = [LabelledTree::from_binder(binder)]
        match ty {
          Some(t) => childs.push(LabelledTree::from_type(t))
          None => ()
        }
        LabelledTree::node(binder.loc, "Parameter::Labelled", childs)
      }
      Optional(binder~, default~, ty~) => {
        let childs = [
          LabelledTree::from_binder(binder),
          LabelledTree::from_expr(default),
        ]
        match ty {
          Some(t) => childs.push(LabelledTree::from_type(t))
          None => ()
        }
        LabelledTree::node(binder.loc, "Parameter::Optional", childs)
      }
      QuestionOptional(binder~, ty~) => {
        let childs = [LabelledTree::from_binder(binder)]
        match ty {
          Some(t) => childs.push(LabelledTree::from_type(t))
          None => ()
        }
        LabelledTree::node(binder.loc, "Parameter::QuestionOptional", childs)
      }
    }
  }

  fn from_error_type(err : @syntax.ErrorType, loc : Location) -> LabelledTree {
    match err {
      ErrorType(ty~) => LabelledTree::from_type(ty)
      DefaultErrorType(loc~) =>
        LabelledTree::node(loc, "ErrorType::DefaultErrorType", [])
      NoErrorType => LabelledTree::node(loc, "ErrorType::NoErrorType", [])
      Noraise(loc~) => LabelledTree::node(loc, "ErrorType::Noraise", [])
      MaybeError(ty~) => LabelledTree::from_type(ty)
    }
  }

  match func {
    Lambda(
      parameters~,
      params_loc~,
      body~,
      return_type~,
      error_type~,
      kind~,
      has_error~,
      is_async~,
      loc~
    ) => {
      let childs = []
      parameters.each(param => childs.push(from_parameter(param)))
      childs.push(LabelledTree::from_expr(body))
      match return_type {
        Some(ret_ty) => childs.push(LabelledTree::from_type(ret_ty))
        None => ()
      }
      childs.push(from_error_type(error_type, loc))
      let kind_label = match kind {
        Lambda => "FnKind::Lambda"
        Matrix => "FnKind::Matrix"
        Arrow => "FnKind::Arrow"
      }
      childs.push(LabelledTree::node(loc, kind_label, []))
      match has_error {
        Some(error_loc) =>
          childs.push(LabelledTree::node(error_loc, "HasError", []))
        None => ()
      }
      childs.push(LabelledTree::node(loc, "IsAsync(\{is_async})", []))
      LabelledTree::node(loc, "Func::Lambda", childs)
    }
    Match(cases~, has_error~, is_async~, fn_loc~, loc~) => {
      let childs = []
      cases.each(case => {
        let case_childs = []
        case.patterns.each(pat => case_childs.push(
          LabelledTree::from_pattern(pat),
        ))
        match case.guard_ {
          Some(guard_expr) =>
            case_childs.push(LabelledTree::from_expr(guard_expr))
          None => ()
        }
        case_childs.push(LabelledTree::from_expr(case.body))
        childs.push(
          LabelledTree::node(case.body.loc(), "MultiArgCase", case_childs),
        )
      })
      match has_error {
        Some(error_loc) =>
          childs.push(LabelledTree::node(error_loc, "HasError", []))
        None => ()
      }
      childs.push(LabelledTree::node(loc, "IsAsync(\{is_async})", []))
      LabelledTree::node(loc, "Func::Match", childs)
    }
  }
}

///|
fn LabelledTree::from_constructor(constr : @syntax.Constructor) -> LabelledTree {
  let childs = [
    LabelledTree::node(constr.name.loc, "ConstrName(\{constr.name.name})", []),
  ]
  let extra_info_tree = match constr.extra_info {
    TypeName(type_name) => LabelledTree::from_type_name(type_name)
    Package(pkg) => LabelledTree::node(constr.loc, "Package(\{pkg})", [])
    NoExtraInfo => LabelledTree::node(constr.loc, "NoExtraInfo", [])
  }
  childs.push(extra_info_tree)
  LabelledTree::node(constr.loc, "Constructor", childs)
}

///|
fn LabelledTree::from_interp_elem(elem : @syntax.InterpElem) -> LabelledTree {
  match elem {
    Literal(repr~, loc~) =>
      LabelledTree::node(loc, "InterpElem::Literal(\{repr})", [])
    Expr(expr~, loc~) => {
      let childs = [LabelledTree::from_expr(expr)]
      LabelledTree::node(loc, "InterpElem::Expr", childs)
    }
    Source(interp_source) =>
      LabelledTree::node(
        // InterpSource doesn't have location, use dummy location
        {
          start: { fname: "", lnum: 0, bol: 0, cnum: 0 },
          end: { fname: "", lnum: 0, bol: 0, cnum: 0 },
        },
        "InterpElem::Source",
        [],
      )
  }
}

///|
fn LabelledTree::from_multiline_string_elem(
  elem : @syntax.MultilineStringElem,
) -> LabelledTree {
  match elem {
    String(s) =>
      LabelledTree::node(
        // MultilineStringElem doesn't have a location, so we use a dummy location
        {
          start: { fname: "", lnum: 0, bol: 0, cnum: 0 },
          end: { fname: "", lnum: 0, bol: 0, cnum: 0 },
        },
        "MultilineStringElem::String(\{s})",
        [],
      )
    Interp(elems) => {
      let childs = []
      elems.each(elem => childs.push(LabelledTree::from_interp_elem(elem)))
      LabelledTree::node(
        // MultilineStringElem doesn't have a location, so we use a dummy location
        {
          start: { fname: "", lnum: 0, bol: 0, cnum: 0 },
          end: { fname: "", lnum: 0, bol: 0, cnum: 0 },
        },
        "MultilineStringElem::Interp",
        childs,
      )
    }
  }
}

///|
fn LabelledTree::from_spreadable_elem(
  elem : @syntax.SpreadableElem,
) -> LabelledTree {
  match elem {
    Regular(expr) => LabelledTree::from_expr(expr)
    Spread(expr~, loc~) => {
      let childs = [LabelledTree::from_expr(expr)]
      LabelledTree::node(loc, "SpreadableElem::Spread", childs)
    }
  }
}

///|
fn LabelledTree::from_static_assertion(
  assertion : @syntax.StaticAssertion,
) -> LabelledTree {
  let childs = [LabelledTree::from_type(assertion.ty)]
  let trait_name = match assertion.trait_ {
    Ident(name~) => name
    Dot(pkg~, id~) => "\{pkg}.\{id}"
  }
  childs.push(LabelledTree::node(assertion.loc, "Trait(\{trait_name})", []))
  childs.push(
    LabelledTree::node(assertion.loc, "Message(\{assertion.msg})", []),
  )
  LabelledTree::node(assertion.loc, "StaticAssertion", childs)
}

///|
fn LabelledTree::from_expr(expr : Expr) -> LabelledTree {
  match expr {
    Group(expr~, loc~, group~) => {
      // no group loc, so use different label
      let label = match group {
        Paren => "Expr::Group:Paren"
        Brace => "Expr::Group:Brace"
      }
      let childs = [LabelledTree::from_expr(expr)]
      LabelledTree::node(loc, label, childs)
    }
    Map(elems~, loc~) => {
      let childs = []
      elems.each(elem => {
        let { key, key_loc, expr, loc } = elem
        let key = match key {
          String(s) => "Constant::String(\{s})"
          Double(d) => "Constant::Double(\{d})"
          Int(i) => "Constant::Int(\{i})"
          Float(f) => "Constant::Float(\{f})"
          UInt64(u) => "Constant::UInt64(\{u})"
          UInt(u) => "Constant::UInt(\{u})"
          Int64(i) => "Constant::Int64(\{i})"
          Char(c) => "Constant::Char(\{c})"
          Bool(b) => "Constant::Bool(\{b})"
          Bytes(b) => "Constant::Bytes(\{b})"
          Byte(b) => "Constant::Byte(\{b})"
          BigInt(i) => "Constant::BigInt(\{i})"
        }
        let key = LabelledTree::node(key_loc, key, [])
        let expr = LabelledTree::from_expr(expr)
        let elem = LabelledTree::node(loc, "MapExprElem", [key, expr])
        childs.push(elem)
      })
      LabelledTree::node(loc, "Expr::Map", childs)
    }
    TryOperator(body~, kind~, try_loc~, loc~) => {
      let kind_label = match kind {
        Question => "TryOperatorKind::Question"
        Exclamation => "TryOperatorKind::Exclamation"
      }
      let childs = [
        LabelledTree::from_expr(body),
        LabelledTree::node(try_loc, kind_label, []),
      ]
      LabelledTree::node(loc, "Expr::TryOperator", childs)
    }
    Try(
      body~,
      catch_~,
      catch_all~,
      try_else~,
      has_try~,
      try_loc~,
      catch_loc~,
      else_loc~,
      loc~
    ) => {
      let childs = []
      childs.push(LabelledTree::from_expr(body))
      catch_.each(case => {
        let guard_childs = []
        guard_childs.push(LabelledTree::from_pattern(case.pattern))
        match case.guard_ {
          Some(guard_expr) =>
            guard_childs.push(LabelledTree::from_expr(guard_expr))
          None => ()
        }
        guard_childs.push(LabelledTree::from_expr(case.body))
        childs.push(
          LabelledTree::node(case.pattern.loc(), "Case", guard_childs),
        )
      })
      match try_else {
        Some(try_else_cases) =>
          try_else_cases.each(case => {
            let guard_childs = []
            guard_childs.push(LabelledTree::from_pattern(case.pattern))
            match case.guard_ {
              Some(guard_expr) =>
                guard_childs.push(LabelledTree::from_expr(guard_expr))
              None => ()
            }
            guard_childs.push(LabelledTree::from_expr(case.body))
            childs.push(
              LabelledTree::node(
                case.pattern.loc(),
                "TryElseCase",
                guard_childs,
              ),
            )
          })
        None => ()
      }
      LabelledTree::node(loc, "Expr::Try", childs)
    }
    ForEach(binders~, expr~, body~, else_block~, label~, loc~) => {
      let childs = []
      binders.each(binder => match binder {
        Some(b) => childs.push(LabelledTree::from_binder(b))
        None => childs.push(LabelledTree::node(loc, "NoBinder", []))
      })
      childs.push(LabelledTree::from_expr(expr))
      childs.push(LabelledTree::from_expr(body))
      match else_block {
        Some(else_expr) => childs.push(LabelledTree::from_expr(else_expr))
        None => ()
      }
      match label {
        Some(l) =>
          childs.push(LabelledTree::node(l.loc, "Label(\{l.name})", []))
        None => ()
      }
      LabelledTree::node(loc, "Expr::ForEach", childs)
    }
    For(binders~, condition~, continue_block~, body~, for_else~, label~, loc~) => {
      let childs = []
      binders.each(fn(pair) {
        let (binder, init_expr) = pair
        let init_childs = [
          LabelledTree::from_binder(binder),
          LabelledTree::from_expr(init_expr),
        ]
        childs.push(LabelledTree::node(binder.loc, "ForBinder", init_childs))
      })
      match condition {
        Some(cond) => childs.push(LabelledTree::from_expr(cond))
        None => ()
      }
      continue_block.each(fn(pair) {
        let (binder, cont_expr) = pair
        let cont_childs = [
          LabelledTree::from_binder(binder),
          LabelledTree::from_expr(cont_expr),
        ]
        childs.push(
          LabelledTree::node(binder.loc, "ContinueBinder", cont_childs),
        )
      })
      childs.push(LabelledTree::from_expr(body))
      match for_else {
        Some(else_expr) => childs.push(LabelledTree::from_expr(else_expr))
        None => ()
      }
      match label {
        Some(l) =>
          childs.push(LabelledTree::node(l.loc, "Label(\{l.name})", []))
        None => ()
      }
      LabelledTree::node(loc, "Expr::For", childs)
    }
    Loop(arg~, body~, label~, loop_loc~, loc~) => {
      let childs = [LabelledTree::from_expr(arg)]
      body.each(case => {
        let case_childs = []
        case_childs.push(LabelledTree::from_pattern(case.pattern))
        match case.guard_ {
          Some(guard_expr) =>
            case_childs.push(LabelledTree::from_expr(guard_expr))
          None => ()
        }
        case_childs.push(LabelledTree::from_expr(case.body))
        childs.push(LabelledTree::node(case.pattern.loc(), "Case", case_childs))
      })
      match label {
        Some(l) =>
          childs.push(LabelledTree::node(l.loc, "Label(\{l.name})", []))
        None => ()
      }
      LabelledTree::node(loc, "Expr::Loop", childs)
    }
    Continue(args~, label~, loc~) => {
      let childs = []
      args.each(arg => childs.push(LabelledTree::from_expr(arg)))
      match label {
        Some(l) =>
          childs.push(LabelledTree::node(l.loc, "Label(\{l.name})", []))
        None => ()
      }
      LabelledTree::node(loc, "Expr::Continue", childs)
    }
    Break(arg~, label~, loc~) => {
      let childs = []
      match arg {
        Some(a) => childs.push(LabelledTree::from_expr(a))
        None => ()
      }
      match label {
        Some(l) =>
          childs.push(LabelledTree::node(l.loc, "Label(\{l.name})", []))
        None => ()
      }
      LabelledTree::node(loc, "Expr::Break", childs)
    }
    Unit(loc~, faked~) => {
      let label = if faked { "Expr::Unit(faked)" } else { "Expr::Unit" }
      LabelledTree::node(loc, label, [])
    }
    Raise(err_value~, loc~) => {
      let childs = [LabelledTree::from_expr(err_value)]
      LabelledTree::node(loc, "Expr::Raise", childs)
    }
    Return(return_value~, loc~) => {
      let childs = []
      match return_value {
        Some(ret_val) => childs.push(LabelledTree::from_expr(ret_val))
        None => ()
      }
      LabelledTree::node(loc, "Expr::Return", childs)
    }
    Hole(loc~, kind~) => {
      let kind_label = match kind {
        Synthesized => "Hole::Synthesized"
        Incomplete => "Hole::Incomplete"
        Todo => "Hole::Todo"
      }
      LabelledTree::node(loc, "Expr::Hole(\{kind_label})", [])
    }
    Assign(var_~, expr~, augmented_by~, loc~) => {
      let childs = []
      let var_name = match var_.name {
        Ident(name~) => name
        Dot(pkg~, id~) => "\{pkg}.\{id}"
      }
      childs.push(LabelledTree::node(var_.loc, "Var(\{var_name})", []))
      childs.push(LabelledTree::from_expr(expr))
      match augmented_by {
        Some(op) => {
          let op_name = match op.name {
            Ident(name~) => name
            Dot(pkg~, id~) => "\{pkg}.\{id}"
          }
          childs.push(LabelledTree::node(op.loc, "AugmentedBy(\{op_name})", []))
        }
        None => ()
      }
      LabelledTree::node(loc, "Expr::Assign", childs)
    }
    Pipe(lhs~, rhs~, loc~) => {
      let childs = [LabelledTree::from_expr(lhs), LabelledTree::from_expr(rhs)]
      LabelledTree::node(loc, "Expr::Pipe", childs)
    }
    LetMut(binder~, ty~, expr~, body~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_binder(binder))
      match ty {
        Some(type_) => childs.push(LabelledTree::from_type(type_))
        None => ()
      }
      childs.push(LabelledTree::from_expr(expr))
      childs.push(LabelledTree::from_expr(body))
      LabelledTree::node(loc, "Expr::LetMut", childs)
    }
    LexMatch(strategy~, expr~, match_loc~, cases~, loc~) => {
      let childs = []
      match strategy {
        Some(strat) =>
          childs.push(
            LabelledTree::node(strat.loc, "Strategy(\{strat.name})", []),
          )
        None => ()
      }
      childs.push(LabelledTree::from_expr(expr))
      cases.each(case => {
        let case_childs = []
        case.pat.each(pat => case_childs.push(
          LabelledTree::from_lex_top_pattern(pat),
        ))
        case_childs.push(LabelledTree::from_expr(case.body))
        childs.push(LabelledTree::node(case.pat_loc, "LexCase", case_childs))
      })
      LabelledTree::node(loc, "Expr::LexMatch", childs)
    }
    Match(expr~, cases~, match_loc~, loc~) => {
      let childs = [LabelledTree::from_expr(expr)]
      cases.each(case => {
        let case_childs = []
        case_childs.push(LabelledTree::from_pattern(case.pattern))
        match case.guard_ {
          Some(guard_expr) =>
            case_childs.push(LabelledTree::from_expr(guard_expr))
          None => ()
        }
        case_childs.push(LabelledTree::from_expr(case.body))
        childs.push(LabelledTree::node(case.pattern.loc(), "Case", case_childs))
      })
      LabelledTree::node(loc, "Expr::Match", childs)
    }
    Mutate(record~, accessor~, field~, augmented_by~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_expr(record))
      childs.push(LabelledTree::from_accessor(accessor))
      childs.push(LabelledTree::from_expr(field))
      match augmented_by {
        Some(op) => {
          let op_name = match op.name {
            Ident(name~) => name
            Dot(pkg~, id~) => "\{pkg}.\{id}"
          }
          childs.push(LabelledTree::node(op.loc, "AugmentedBy(\{op_name})", []))
        }
        None => ()
      }
      LabelledTree::node(loc, "Expr::Mutate", childs)
    }
    As(expr~, trait_~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_expr(expr))
      childs.push(LabelledTree::from_type_name(trait_))
      LabelledTree::node(loc, "Expr::As", childs)
    }
    DotApply(self~, method_name~, args~, return_self~, attr~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_expr(self))
      childs.push(
        LabelledTree::node(method_name.loc, "MethodName(\{method_name.name})", []),
      )
      args.each(arg => childs.push(LabelledTree::from_argument(arg)))
      let attr_label = match attr {
        NoAttr => "NoAttr"
        Exclamation => "Exclamation"
        Question => "Question"
      }
      childs.push(LabelledTree::node(loc, "ApplyAttr(\{attr_label})", []))
      childs.push(LabelledTree::node(loc, "ReturnSelf(\{return_self})", []))
      LabelledTree::node(loc, "Expr::DotApply", childs)
    }
    Method(type_name~, method_name~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_type_name(type_name))
      childs.push(
        LabelledTree::node(method_name.loc, "MethodName(\{method_name.name})", []),
      )
      LabelledTree::node(loc, "Expr::Method", childs)
    }
    Field(record~, accessor~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_expr(record))
      childs.push(LabelledTree::from_accessor(accessor))
      LabelledTree::node(loc, "Expr::Field", childs)
    }
    RecordUpdate(type_name~, record~, fields~, loc~) => {
      let childs = []
      match type_name {
        Some(tn) => childs.push(LabelledTree::from_type_name(tn))
        None => ()
      }
      childs.push(LabelledTree::from_expr(record))
      fields.each(field => childs.push(LabelledTree::from_field_def(field)))
      LabelledTree::node(loc, "Expr::RecordUpdate", childs)
    }
    Record(type_name~, fields~, trailing~, loc~) => {
      let childs = []
      match type_name {
        Some(tn) => childs.push(LabelledTree::from_type_name(tn))
        None => ()
      }
      fields.each(field => childs.push(LabelledTree::from_field_def(field)))
      let trailing_label = match trailing {
        Comma => "TrailingMark::Comma"
        Semi => "TrailingMark::Semi"
        None => "TrailingMark::None"
      }
      childs.push(LabelledTree::node(loc, trailing_label, []))
      LabelledTree::node(loc, "Expr::Record", childs)
    }
    Tuple(exprs~, loc~) => {
      let childs = []
      exprs.each(expr => childs.push(LabelledTree::from_expr(expr)))
      LabelledTree::node(loc, "Expr::Tuple", childs)
    }
    Sequence(exprs~, last_expr~, loc~) => {
      let childs = []
      exprs.each(expr => childs.push(LabelledTree::from_expr(expr)))
      childs.push(LabelledTree::from_expr(last_expr))
      LabelledTree::node(loc, "Expr::Sequence", childs)
    }
    Let(pattern~, expr~, body~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_pattern(pattern))
      childs.push(LabelledTree::from_expr(expr))
      childs.push(LabelledTree::from_expr(body))
      LabelledTree::node(loc, "Expr::Let", childs)
    }
    LetAnd(bindings~, body~, loc~) => {
      let childs = []
      bindings.each(fn(binding) {
        let (binder, ty, func) = binding
        let binding_childs = []
        binding_childs.push(LabelledTree::from_binder(binder))
        match ty {
          Some(type_) => binding_childs.push(LabelledTree::from_type(type_))
          None => ()
        }
        binding_childs.push(LabelledTree::from_func(func))
        childs.push(
          LabelledTree::node(binder.loc, "LetAndBinding", binding_childs),
        )
      })
      childs.push(LabelledTree::from_expr(body))
      LabelledTree::node(loc, "Expr::LetAnd", childs)
    }
    LetRec(bindings~, body~, loc~) => {
      let childs = []
      bindings.each(fn(binding) {
        let (binder, func) = binding
        let binding_childs = [
          LabelledTree::from_binder(binder),
          LabelledTree::from_func(func),
        ]
        childs.push(
          LabelledTree::node(binder.loc, "LetRecBinding", binding_childs),
        )
      })
      childs.push(LabelledTree::from_expr(body))
      LabelledTree::node(loc, "Expr::LetRec", childs)
    }
    LetFn(name~, func~, body~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_binder(name))
      childs.push(LabelledTree::from_func(func))
      childs.push(LabelledTree::from_expr(body))
      LabelledTree::node(loc, "Expr::LetFn", childs)
    }
    Defer(expr~, body~, loc~) => {
      let childs = [
        LabelledTree::from_expr(expr),
        LabelledTree::from_expr(body),
      ]
      LabelledTree::node(loc, "Expr::Defer", childs)
    }
    IsLexMatch(expr~, strategy~, pat~, pat_loc~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_expr(expr))
      match strategy {
        Some(strat) =>
          childs.push(
            LabelledTree::node(strat.loc, "Strategy(\{strat.name})", []),
          )
        None => ()
      }
      pat.each(p => childs.push(LabelledTree::from_lex_top_pattern(p)))
      LabelledTree::node(loc, "Expr::IsLexMatch", childs)
    }
    Is(expr~, pat~, loc~) => {
      let childs = [
        LabelledTree::from_expr(expr),
        LabelledTree::from_pattern(pat),
      ]
      LabelledTree::node(loc, "Expr::Is", childs)
    }
    Guard(cond~, otherwise~, body~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_expr(cond))
      match otherwise {
        Some(else_expr) => childs.push(LabelledTree::from_expr(else_expr))
        None => ()
      }
      childs.push(LabelledTree::from_expr(body))
      LabelledTree::node(loc, "Expr::Guard", childs)
    }
    If(cond~, ifso~, ifnot~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_expr(cond))
      childs.push(LabelledTree::from_expr(ifso))
      match ifnot {
        Some(else_expr) => childs.push(LabelledTree::from_expr(else_expr))
        None => ()
      }
      LabelledTree::node(loc, "Expr::If", childs)
    }
    Ident(id~, loc~) => {
      let name = match id.name {
        Ident(name~) => name
        Dot(pkg~, id~) => "\{pkg}.\{id}"
      }
      if current_convert_mode.val is Pattern && name == "___" {
        LabelledTree::wildcard(loc)
      } else {
        LabelledTree::node(loc, "Expr::Ident(\{name})", [])
      }
    }
    Function(func~, loc~) => {
      let childs = [LabelledTree::from_func(func)]
      LabelledTree::node(loc, "Expr::Function", childs)
    }
    While(loop_cond~, loop_body~, while_else~, label~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_expr(loop_cond))
      childs.push(LabelledTree::from_expr(loop_body))
      match while_else {
        Some(else_expr) => childs.push(LabelledTree::from_expr(else_expr))
        None => ()
      }
      match label {
        Some(l) =>
          childs.push(LabelledTree::node(l.loc, "Label(\{l.name})", []))
        None => ()
      }
      LabelledTree::node(loc, "Expr::While", childs)
    }
    Constr(constr~, loc~) => {
      let childs = [LabelledTree::from_constructor(constr)]
      LabelledTree::node(loc, "Expr::Constr", childs)
    }
    Constraint(expr~, ty~, loc~) => {
      let childs = [LabelledTree::from_expr(expr), LabelledTree::from_type(ty)]
      LabelledTree::node(loc, "Expr::Constraint", childs)
    }
    Interp(elems~, loc~) => {
      let childs = []
      elems.each(elem => childs.push(LabelledTree::from_interp_elem(elem)))
      LabelledTree::node(loc, "Expr::Interp", childs)
    }
    MultilineString(elems~, loc~) => {
      let childs = []
      elems.each(elem => childs.push(
        LabelledTree::from_multiline_string_elem(elem),
      ))
      LabelledTree::node(loc, "Expr::MultilineString", childs)
    }
    Constant(c~, loc~) => {
      let label = match c {
        String(s) => "Constant::String(\{s})"
        Double(d) => "Constant::Double(\{d})"
        Int(i) => "Constant::Int(\{i})"
        Float(f) => "Constant::Float(\{f})"
        UInt64(u) => "Constant::UInt64(\{u})"
        UInt(u) => "Constant::UInt(\{u})"
        Int64(i) => "Constant::Int64(\{i})"
        Char(c) => "Constant::Char(\{c})"
        Bool(b) => "Constant::Bool(\{b})"
        Bytes(b) => "Constant::Bytes(\{b})"
        Byte(b) => "Constant::Byte(\{b})"
        BigInt(i) => "Constant::BigInt(\{i})"
      }
      LabelledTree::node(loc, label, [])
    }
    ArrayAugmentedSet(op~, array~, index~, value~, loc~) => {
      let childs = []
      let op_name = match op.name {
        Ident(name~) => name
        Dot(pkg~, id~) => "\{pkg}.\{id}"
      }
      childs.push(LabelledTree::node(op.loc, "Op(\{op_name})", []))
      childs.push(LabelledTree::from_expr(array))
      childs.push(LabelledTree::from_expr(index))
      childs.push(LabelledTree::from_expr(value))
      LabelledTree::node(loc, "Expr::ArrayAugmentedSet", childs)
    }
    ArraySet(array~, index~, value~, loc~) => {
      let childs = [
        LabelledTree::from_expr(array),
        LabelledTree::from_expr(index),
        LabelledTree::from_expr(value),
      ]
      LabelledTree::node(loc, "Expr::ArraySet", childs)
    }
    ArrayGetSlice(array~, start_index~, end_index~, index_loc~, loc~) => {
      let childs = []
      childs.push(LabelledTree::from_expr(array))
      match start_index {
        Some(start) => childs.push(LabelledTree::from_expr(start))
        None => childs.push(LabelledTree::node(index_loc, "NoStartIndex", []))
      }
      match end_index {
        Some(end) => childs.push(LabelledTree::from_expr(end))
        None => childs.push(LabelledTree::node(index_loc, "NoEndIndex", []))
      }
      LabelledTree::node(loc, "Expr::ArrayGetSlice", childs)
    }
    ArrayGet(array~, index~, loc~) => {
      let childs = [
        LabelledTree::from_expr(array),
        LabelledTree::from_expr(index),
      ]
      LabelledTree::node(loc, "Expr::ArrayGet", childs)
    }
    ArraySpread(elems~, loc~) => {
      let childs = []
      elems.each(elem => childs.push(LabelledTree::from_spreadable_elem(elem)))
      LabelledTree::node(loc, "Expr::ArraySpread", childs)
    }
    Array(exprs~, loc~) => {
      let childs = []
      exprs.each(expr => childs.push(LabelledTree::from_expr(expr)))
      LabelledTree::node(loc, "Expr::Array", childs)
    }
    Unary(op~, expr~, loc~) => {
      let childs = []
      let op_name = match op.name {
        Ident(name~) => name
        Dot(pkg~, id~) => "\{pkg}.\{id}"
      }
      childs.push(LabelledTree::node(op.loc, "Op(\{op_name})", []))
      childs.push(LabelledTree::from_expr(expr))
      LabelledTree::node(loc, "Expr::Unary", childs)
    }
    Infix(op~, lhs~, rhs~, loc~) => {
      let childs = []
      let op_name = match op.name {
        Ident(name~) => name
        Dot(pkg~, id~) => "\{pkg}.\{id}"
      }
      childs.push(LabelledTree::from_expr(lhs))
      childs.push(LabelledTree::node(op.loc, "Op(\{op_name})", []))
      childs.push(LabelledTree::from_expr(rhs))
      LabelledTree::node(loc, "Expr::Infix", childs)
    }
    Apply(func~, args~, attr~, loc~) => {
      let childs = [LabelledTree::from_expr(func)]
      args.each(arg => childs.push(LabelledTree::from_argument(arg)))
      let attr_label = match attr {
        NoAttr => "NoAttr"
        Exclamation => "Exclamation"
        Question => "Question"
      }
      childs.push(LabelledTree::node(loc, "ApplyAttr(\{attr_label})", []))
      LabelledTree::node(loc, "Expr::Apply", childs)
    }
    StaticAssert(asserts~, body~) => {
      let childs = []
      asserts.each(assert => childs.push(
        LabelledTree::from_static_assertion(assert),
      ))
      childs.push(LabelledTree::from_expr(body))
      LabelledTree::node(body.loc(), "Expr::StaticAssert", childs)
    }
  }
}
