///|
priv struct FunctionLike {
  name : String
  loc : @basic.Location
  params : Array[StoragePath]
  body : @syntax.Expr
}

///|
fn function_like_from_impl(node : @syntax.Impl) -> FunctionLike raise {
  match node {
    TopFuncDef(fun_decl~, decl_body=DeclBody(expr~), loc~, ..) => {
      let params = paths_from_parameters(fun_decl.decl_params)
      { name: fun_decl.name.name, loc, params, body: expr }
    }
    TopFuncDef(decl_body=DeclNone, loc~, ..) =>
      raise TaintAnalysisError::UnsupportedFunctionLike(
        kind="TopFuncDef.DeclNone",
        loc~,
      )
    TopFuncDef(decl_body=DeclStubs(_), loc~, ..) =>
      raise TaintAnalysisError::UnsupportedFunctionLike(
        kind="TopFuncDef.DeclStubs",
        loc~,
      )
    TopImpl(method_name~, params~, body=DeclBody(expr~), loc~, ..) => {
      let paths = paths_from_parameter_list(params)
      { name: method_name.name, loc, params: paths, body: expr }
    }
    TopImpl(body=DeclNone, loc~, ..) =>
      raise TaintAnalysisError::UnsupportedFunctionLike(
        kind="TopImpl.DeclNone",
        loc~,
      )
    TopImpl(body=DeclStubs(_), loc~, ..) =>
      raise TaintAnalysisError::UnsupportedFunctionLike(
        kind="TopImpl.DeclStubs",
        loc~,
      )
    _ =>
      raise TaintAnalysisError::UnsupportedFunctionLike(
        kind=impl_kind_name(node),
        loc=node.loc(),
      )
  }
}

///|
fn impl_kind_name(node : @syntax.Impl) -> String {
  match node {
    TopExpr(..) => "TopExpr"
    TopFuncDef(..) => "TopFuncDef"
    TopImpl(..) => "TopImpl"
    TopImplRelation(..) => "TopImplRelation"
    TopLetDef(..) => "TopLetDef"
    TopTest(..) => "TopTest"
    TopTrait(_) => "TopTrait"
    TopTypeDef(_) => "TopTypeDef"
    TopUsing(..) => "TopUsing"
    TopView(..) => "TopView"
  }
}

///|
fn paths_from_parameters(
  params : @list.List[@syntax.Parameter]?,
) -> Array[StoragePath] {
  if params is Some(items) {
    paths_from_parameter_list(items)
  } else {
    []
  }
}

///|
fn paths_from_parameter_list(
  params : @list.List[@syntax.Parameter],
) -> Array[StoragePath] {
  let paths : Array[StoragePath] = []
  for parameter in params.to_array() {
    if binder_from_parameter(parameter) is Some(binder) {
      paths.push({ root: binder.name, segments: [] })
    }
  }
  paths
}

///|
fn binder_from_parameter(parameter : @syntax.Parameter) -> @syntax.Binder? {
  match parameter {
    Positional(binder~, ..) => Some(binder)
    Labelled(binder~, ..) => Some(binder)
    Optional(binder~, ..) => Some(binder)
    QuestionOptional(binder~, ..) => Some(binder)
    DiscardPositional(..) => None
  }
}

///|
fn storage_path_from_var(var_ : @syntax.Var) -> StoragePath? {
  if @id.normalize_identifier_name_from_var(var_) is Some(name) {
    Some({ root: name, segments: [] })
  } else {
    None
  }
}

///|
fn storage_path_from_expr(expr : @syntax.Expr) -> StoragePath? {
  match expr {
    Ident(id~, ..) => storage_path_from_var(id)
    Field(record~, accessor~, ..) =>
      if storage_path_from_expr(record) is Some(path) {
        path_with_segment(path, segment_from_accessor(accessor))
      } else {
        None
      }
    ArrayGet(array~, index~, ..) =>
      if storage_path_from_expr(array) is Some(path) {
        Some(append_path_segment(path, segment_from_index_expr(index)))
      } else {
        None
      }
    Group(expr~, ..) | Constraint(expr~, ..) => storage_path_from_expr(expr)
    _ => None
  }
}

///|
fn segment_from_accessor(accessor : @syntax.Accessor) -> PathSegment? {
  match accessor {
    Label(label) => Some(Field(label.name))
    Index(tuple_index~, ..) => Some(TupleIndex(tuple_index))
    Newtype(..) => None
  }
}

///|
fn path_with_segment(
  path : StoragePath,
  segment : PathSegment?,
) -> StoragePath? {
  if segment is Some(segment) {
    Some(append_path_segment(path, segment))
  } else {
    None
  }
}

///|
fn append_path_segment(
  path : StoragePath,
  segment : PathSegment,
) -> StoragePath {
  let segments = copy_segments(path.segments)
  segments.push(segment)
  { root: path.root, segments }
}

///|
fn segment_from_index_expr(index : @syntax.Expr) -> PathSegment {
  match index {
    Constant(c=Int(value), ..) => ConstIndex(value)
    Constant(c=UInt(value), ..) => ConstIndex(value)
    _ => AnyIndex
  }
}

///|
fn segment_from_argument_kind(
  kind : @syntax.ArgumentKind,
  positional_index : Int,
) -> PathSegment {
  match kind {
    Labelled(label) | LabelledPun(label) => Field(label.name)
    LabelledOption(label~, ..) | LabelledOptionPun(label~, ..) =>
      Field(label.name)
    Positional => TupleIndex(positional_index)
  }
}

///|
fn argument_label(kind : @syntax.ArgumentKind) -> String? {
  match kind {
    Labelled(label) | LabelledPun(label) => Some(label.name)
    LabelledOption(label~, ..) | LabelledOptionPun(label~, ..) =>
      Some(label.name)
    Positional => None
  }
}
