///|
priv struct FunctionLike {
  params : Array[StoragePath]
  body : @untyped_cst.CstNode
}

///|
fn function_like_from_impl(node : @untyped_cst.CstNode) -> FunctionLike raise {
  match node.kind {
    Impl_Function | Impl_ImplMethod => {
      let declaration = if node.kind is Impl_ImplMethod {
        @cst.raw_child(node, "method").unwrap_or(node)
      } else {
        node
      }
      guard @cst.raw_child(declaration, "body") is Some(body) else {
        let decl_body_kind = @cst.raw_child(declaration, "decl_body_kind")
        let unsupported_kind = match decl_body_kind.map(item => item.kind) {
          Some(DeclBody_EmbeddedString)
          | Some(DeclBody_EmbeddedMultilineString)
          | Some(DeclBody_Import) =>
            if node.kind is Impl_Function {
              "TopFuncDef.DeclStubs"
            } else {
              "TopImpl.DeclStubs"
            }
          _ =>
            if node.kind is Impl_Function {
              "TopFuncDef.DeclNone"
            } else {
              "TopImpl.DeclNone"
            }
        }
        raise TaintAnalysisError::UnsupportedFunctionLike(
          kind=unsupported_kind,
          loc=node.loc,
        )
      }
      {
        params: paths_from_parameter_list(@cst.raw_child(declaration, "params")),
        body,
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
fn impl_kind_name(node : @untyped_cst.CstNode) -> String {
  match node.kind {
    Impl_Import => "TopImport"
    Impl_Extend => "TopExtend"
    Impl_Using => "TopUsing"
    Impl_Function => "TopFuncDef"
    Impl_Let => "TopLetDef"
    Impl_Const => "TopLetDef"
    Impl_TypeAbstract
    | Impl_TypeAlias
    | Impl_RecordStruct
    | Impl_TupleStruct
    | Impl_EnumVariant
    | Impl_ExtensibleEnum
    | Impl_ExtendEnum
    | Impl_Suberror
    | Impl_SuberrorEnum
    | Impl_EnumView => "TopTypeDef"
    Impl_Trait => "TopTrait"
    Impl_ImplMethod => "TopImpl"
    Impl_ImplRelation => "TopImplRelation"
    Impl_Test => "TopTest"
    _ => "CstNode"
  }
}

///|
fn paths_from_parameter_list(
  params : @untyped_cst.CstNode?,
) -> Array[StoragePath] {
  let paths : Array[StoragePath] = []
  guard params is Some(list) else { return paths }
  for parameter in @cst.raw_children(list, "item") {
    match parameter.kind {
      Parameter_DiscardPositional => ()
      _ =>
        if @cst.raw_child(parameter, "pattern") is Some(pattern) {
          let roots = pattern_bound_roots(pattern)
          for root in roots {
            paths.push({ root, segments: [], })
          }
        } else if @cst.name_node(parameter).bind(@cst.normalized_name)
          is Some(name) {
          paths.push({ root: name, segments: [], })
        }
    }
  }
  paths
}

///|
fn storage_path_from_assignment(
  assignment : @untyped_cst.CstNode,
) -> StoragePath? {
  match assignment.kind {
    Expr_Assign =>
      @cst.raw_child(assignment, "semantic_name")
      .bind(@cst.normalized_name)
      .map(root => { root, segments: [], })
    Expr_Mutate =>
      match
        (
          @cst.raw_child(assignment, "self"),
          @cst.raw_child(assignment, "field"),
        ) {
        (Some(record), Some(accessor)) =>
          storage_path_from_expr(record).bind(path => {
            path_with_segment(path, segment_from_accessor(accessor))
          })
        _ => None
      }
    _ => None
  }
}

///|
fn storage_path_from_expr(expr : @untyped_cst.CstNode) -> StoragePath? {
  match expr.kind {
    Expr_Ident =>
      if @cst.normalized_expr_identifier_name(expr) is Some(name) {
        Some({ root: name, segments: [], })
      } else {
        None
      }
    Expr_Field =>
      match (@cst.raw_child(expr, "self"), @cst.raw_child(expr, "field")) {
        (Some(record), Some(accessor)) =>
          storage_path_from_expr(record).bind(path => {
            path_with_segment(path, segment_from_accessor(accessor))
          })
        _ => None
      }
    Expr_ArrayGet =>
      match (node_child(expr, "array"), node_child(expr, "index")) {
        (Some(array), Some(index)) =>
          storage_path_from_expr(array).map(path => {
            append_path_segment(path, segment_from_index_expr(index))
          })
        _ => None
      }
    Expr_Group | Expr_Constraint =>
      if @cst.raw_child(expr, "expr") is Some(inner) {
        storage_path_from_expr(inner)
      } else if @cst.raw_child(expr, "body") is Some(inner) {
        storage_path_from_expr(inner)
      } else {
        None
      }
    _ => None
  }
}

///|
fn segment_from_accessor(accessor : @untyped_cst.CstNode) -> PathSegment? {
  match accessor.kind {
    Accessor_Label =>
      @cst.normalized_name(accessor).map(label => Field(label))
    Accessor_Index =>
      @cst.int_payload(accessor).map(index => TupleIndex(index))
    Accessor_Newtype => None
    _ => None
  }
}

///|
fn path_with_segment(
  path : StoragePath,
  segment : PathSegment?,
) -> StoragePath? {
  segment.map(value => append_path_segment(path, value))
}

///|
fn append_path_segment(
  path : StoragePath,
  segment : PathSegment,
) -> StoragePath {
  let segments = copy_segments(path.segments)
  segments.push(segment)
  { root: path.root, segments, }
}

///|
fn segment_from_index_expr(index : @untyped_cst.CstNode) -> PathSegment {
  if constant_integer_text(index) is Some(value) {
    ConstIndex(value)
  } else {
    AnyIndex
  }
}

///|
fn constant_integer_text(expr : @untyped_cst.CstNode) -> String? {
  guard expr.kind is Expr_Constant else { return None }
  guard @cst.constant(expr) is Some(constant) else { return None }
  match constant.kind {
    Constant_Int | Constant_UInt =>
      @cst.string_payload(constant)
    _ => None
  }
}

///|
fn segment_from_argument_kind(
  argument : @untyped_cst.CstNode,
  positional_index : Int,
) -> PathSegment {
  if @cst.argument_label_name(argument) is Some(label) {
    Field(label)
  } else {
    TupleIndex(positional_index)
  }
}

///|
fn argument_label(argument : @untyped_cst.CstNode) -> String? {
  @cst.argument_label_name(argument)
}
