///|
priv struct FunctionLike {
  name : String
  loc : @basic.Location
  params : Array[StoragePath]
  body : @untyped_ast.Node
}

///|
fn function_like_from_impl(node : @untyped_ast.Node) -> FunctionLike raise {
  match node.kind {
    Impl_TopFuncDef => {
      let fun_decl = node_child(node, "fun_decl")
      let decl_body = node_child(node, "decl_body")
      match decl_body {
        Some(body) if body.kind == DeclBody_DeclBody => {
          let body_expr = if node_child(body, "expr") is Some(expr) {
            expr
          } else {
            raise TaintAnalysisError::UnsupportedFunctionLike(
              kind="TopFuncDef.DeclBody",
              loc=node.loc,
            )
          }
          {
            name: function_decl_name(fun_decl),
            loc: node.loc,
            params: paths_from_optional_parameters(fun_decl, "decl_params"),
            body: body_expr,
          }
        }
        Some(body) if body.kind == DeclBody_DeclNone =>
          raise TaintAnalysisError::UnsupportedFunctionLike(
            kind="TopFuncDef.DeclNone",
            loc=node.loc,
          )
        Some(body) if body.kind == DeclBody_DeclStubs =>
          raise TaintAnalysisError::UnsupportedFunctionLike(
            kind="TopFuncDef.DeclStubs",
            loc=node.loc,
          )
        _ =>
          raise TaintAnalysisError::UnsupportedFunctionLike(
            kind="TopFuncDef",
            loc=node.loc,
          )
      }
    }
    Impl_TopImpl => {
      let decl_body = node_child(node, "body")
      match decl_body {
        Some(body) if body.kind == DeclBody_DeclBody => {
          let body_expr = if node_child(body, "expr") is Some(expr) {
            expr
          } else {
            raise TaintAnalysisError::UnsupportedFunctionLike(
              kind="TopImpl.DeclBody",
              loc=node.loc,
            )
          }
          {
            name: impl_method_name(node),
            loc: node.loc,
            params: paths_from_parameter_list(node_child(node, "params")),
            body: body_expr,
          }
        }
        Some(body) if body.kind == DeclBody_DeclNone =>
          raise TaintAnalysisError::UnsupportedFunctionLike(
            kind="TopImpl.DeclNone",
            loc=node.loc,
          )
        Some(body) if body.kind == DeclBody_DeclStubs =>
          raise TaintAnalysisError::UnsupportedFunctionLike(
            kind="TopImpl.DeclStubs",
            loc=node.loc,
          )
        _ =>
          raise TaintAnalysisError::UnsupportedFunctionLike(
            kind="TopImpl",
            loc=node.loc,
          )
      }
    }
    _ =>
      raise TaintAnalysisError::UnsupportedFunctionLike(
        kind=impl_kind_name(node),
        loc=node.loc,
      )
  }
}

///|
fn function_decl_name(fun_decl : @untyped_ast.Node?) -> String {
  if fun_decl is Some(decl) &&
    node_child(decl, "name") is Some(name) &&
    node_binder_name(name) is Some(value) {
    value
  } else {
    ""
  }
}

///|
fn impl_method_name(node : @untyped_ast.Node) -> String {
  if node_child(node, "method_name") is Some(name) &&
    node_binder_name(name) is Some(value) {
    value
  } else {
    ""
  }
}

///|
fn impl_kind_name(node : @untyped_ast.Node) -> String {
  match node.kind {
    Impl_TopExpr => "TopExpr"
    Impl_TopFuncDef => "TopFuncDef"
    Impl_TopImpl => "TopImpl"
    Impl_TopImplRelation => "TopImplRelation"
    Impl_TopLetDef => "TopLetDef"
    Impl_TopTest => "TopTest"
    Impl_TopTrait => "TopTrait"
    Impl_TopTypeDef => "TopTypeDef"
    Impl_TopUsing => "TopUsing"
    Impl_TopView => "TopView"
    _ => node.kind.to_string()
  }
}

///|
fn paths_from_optional_parameters(
  parent : @untyped_ast.Node?,
  name : String,
) -> Array[StoragePath] {
  if parent is Some(node) {
    paths_from_parameter_list(node_optional_child(node, name))
  } else {
    []
  }
}

///|
fn paths_from_parameter_list(params : @untyped_ast.Node?) -> Array[StoragePath] {
  let paths : Array[StoragePath] = []
  if params is Some(list) {
    for parameter in node_items(list) {
      if binder_from_parameter(parameter) is Some(binder) &&
        node_binder_name(binder) is Some(name) {
        paths.push({ root: name, segments: [] })
      }
    }
  }
  paths
}

///|
fn binder_from_parameter(parameter : @untyped_ast.Node) -> @untyped_ast.Node? {
  match parameter.kind {
    Parameter_Positional
    | Parameter_Labelled
    | Parameter_Optional
    | Parameter_QuestionOptional => node_child(parameter, "binder")
    Parameter_DiscardPositional => None
    _ => None
  }
}

///|
fn storage_path_from_var(var_ : @untyped_ast.Node) -> StoragePath? {
  if node_var_name(var_) is Some(name) {
    Some({ root: name, segments: [] })
  } else {
    None
  }
}

///|
fn storage_path_from_expr(expr : @untyped_ast.Node) -> StoragePath? {
  match expr.kind {
    Expr_Ident =>
      if node_child(expr, "id") is Some(id) {
        storage_path_from_var(id)
      } else {
        None
      }
    Expr_Field =>
      match (node_child(expr, "record"), node_child(expr, "accessor")) {
        (Some(record), Some(accessor)) =>
          if storage_path_from_expr(record) is Some(path) {
            path_with_segment(path, segment_from_accessor(accessor))
          } else {
            None
          }
        _ => None
      }
    Expr_ArrayGet =>
      match (node_child(expr, "array"), node_child(expr, "index")) {
        (Some(array), Some(index)) =>
          if storage_path_from_expr(array) is Some(path) {
            Some(append_path_segment(path, segment_from_index_expr(index)))
          } else {
            None
          }
        _ => None
      }
    Expr_Group | Expr_Constraint =>
      if node_child(expr, "expr") is Some(inner) {
        storage_path_from_expr(inner)
      } else {
        None
      }
    _ => None
  }
}

///|
fn segment_from_accessor(accessor : @untyped_ast.Node) -> PathSegment? {
  match accessor.kind {
    Accessor_Label =>
      if node_first_label_name(accessor) is Some(label) {
        Some(Field(label))
      } else {
        None
      }
    Accessor_Index =>
      if node_child(accessor, "tuple_index") is Some(index) &&
        node_leaf_number_int(index) is Some(tuple_index) {
        Some(TupleIndex(tuple_index))
      } else {
        None
      }
    Accessor_Newtype => None
    _ => None
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
fn segment_from_index_expr(index : @untyped_ast.Node) -> PathSegment {
  if constant_integer_text(index) is Some(value) {
    ConstIndex(value)
  } else {
    AnyIndex
  }
}

///|
fn constant_integer_text(expr : @untyped_ast.Node) -> String? {
  guard expr.kind == Expr_Constant else { return None }
  guard node_child(expr, "constant") is Some(constant) else { return None }
  match constant.kind {
    Constant_Int | Constant_UInt =>
      if node_first_child(constant) is Some(value) {
        node_leaf_string(value)
      } else {
        None
      }
    _ => None
  }
}

///|
fn segment_from_argument_kind(
  kind : @untyped_ast.Node,
  positional_index : Int,
) -> PathSegment {
  match kind.kind {
    ArgumentKind_Labelled | ArgumentKind_LabelledPun =>
      if node_first_label_name(kind) is Some(label) {
        Field(label)
      } else {
        TupleIndex(positional_index)
      }
    ArgumentKind_LabelledOption | ArgumentKind_LabelledOptionPun =>
      if node_child(kind, "label") is Some(label) &&
        node_label_name(label) is Some(value) {
        Field(value)
      } else {
        TupleIndex(positional_index)
      }
    ArgumentKind_Positional => TupleIndex(positional_index)
    _ => TupleIndex(positional_index)
  }
}

///|
fn argument_label(kind : @untyped_ast.Node) -> String? {
  match kind.kind {
    ArgumentKind_Labelled | ArgumentKind_LabelledPun =>
      node_first_label_name(kind)
    ArgumentKind_LabelledOption | ArgumentKind_LabelledOptionPun =>
      if node_child(kind, "label") is Some(label) {
        node_label_name(label)
      } else {
        None
      }
    ArgumentKind_Positional => None
    _ => None
  }
}
