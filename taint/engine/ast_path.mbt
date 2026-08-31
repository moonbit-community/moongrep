///|
priv struct FunctionLike {
  name : String
  loc : @basic.Location
  params : Array[StoragePath]
  body : @untyped_cst.CstNode
}

///|
fn function_like_from_impl(node : @untyped_cst.CstNode) -> FunctionLike raise {
  match node.kind {
    @untyped_cst.Impl_Function | @untyped_cst.Impl_ImplMethod => {
      let declaration = if node.kind is @untyped_cst.Impl_ImplMethod {
        @cst.raw_child(node, "method").unwrap_or(node)
      } else {
        node
      }
      guard @cst.raw_child(declaration, "body") is Some(body) else {
        let decl_body_kind = @cst.raw_child(declaration, "decl_body_kind")
        let unsupported_kind = match decl_body_kind.map(item => item.kind) {
          Some(@untyped_cst.DeclBody_EmbeddedString)
          | Some(@untyped_cst.DeclBody_EmbeddedMultilineString)
          | Some(@untyped_cst.DeclBody_Import) =>
            if node.kind is @untyped_cst.Impl_Function {
              "TopFuncDef.DeclStubs"
            } else {
              "TopImpl.DeclStubs"
            }
          _ =>
            if node.kind is @untyped_cst.Impl_Function {
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
        name: @cst.name_node(declaration)
        .bind(@cst.normalized_name)
        .unwrap_or(""),
        loc: node.loc,
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
    @untyped_cst.Impl_Import => "TopImport"
    @untyped_cst.Impl_Extend => "TopExtend"
    @untyped_cst.Impl_Using => "TopUsing"
    @untyped_cst.Impl_Function => "TopFuncDef"
    @untyped_cst.Impl_Let => "TopLetDef"
    @untyped_cst.Impl_Const => "TopLetDef"
    @untyped_cst.Impl_TypeAbstract
    | @untyped_cst.Impl_TypeAlias
    | @untyped_cst.Impl_RecordStruct
    | @untyped_cst.Impl_TupleStruct
    | @untyped_cst.Impl_EnumVariant
    | @untyped_cst.Impl_ExtensibleEnum
    | @untyped_cst.Impl_ExtendEnum
    | @untyped_cst.Impl_Suberror
    | @untyped_cst.Impl_SuberrorEnum
    | @untyped_cst.Impl_EnumView => "TopTypeDef"
    @untyped_cst.Impl_Trait => "TopTrait"
    @untyped_cst.Impl_ImplMethod => "TopImpl"
    @untyped_cst.Impl_ImplRelation => "TopImplRelation"
    @untyped_cst.Impl_Test => "TopTest"
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
      @untyped_cst.Parameter_DiscardPositional => ()
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
    @untyped_cst.Expr_Assign =>
      @cst.raw_child(assignment, "semantic_name")
      .bind(@cst.normalized_name)
      .map(root => { root, segments: [], })
    @untyped_cst.Expr_Mutate =>
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
    @untyped_cst.Expr_Ident =>
      if @cst.normalized_expr_identifier_name(expr) is Some(name) {
        Some({ root: name, segments: [], })
      } else {
        None
      }
    @untyped_cst.Expr_Field =>
      match (@cst.raw_child(expr, "self"), @cst.raw_child(expr, "field")) {
        (Some(record), Some(accessor)) =>
          storage_path_from_expr(record).bind(path => {
            path_with_segment(path, segment_from_accessor(accessor))
          })
        _ => None
      }
    @untyped_cst.Expr_ArrayGet =>
      match (node_child(expr, "array"), node_child(expr, "index")) {
        (Some(array), Some(index)) =>
          storage_path_from_expr(array).map(path => {
            append_path_segment(path, segment_from_index_expr(index))
          })
        _ => None
      }
    @untyped_cst.Expr_Group | @untyped_cst.Expr_Constraint =>
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
    @untyped_cst.Accessor_Label =>
      @cst.normalized_name(accessor).map(label => Field(label))
    @untyped_cst.Accessor_Index =>
      @cst.int_payload(accessor).map(index => TupleIndex(index))
    @untyped_cst.Accessor_Newtype => None
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
  guard expr.kind is @untyped_cst.Expr_Constant else { return None }
  guard @cst.constant(expr) is Some(constant) else { return None }
  match constant.kind {
    @untyped_cst.Constant_Int | @untyped_cst.Constant_UInt =>
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
