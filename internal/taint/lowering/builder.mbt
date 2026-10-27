///|
using @cfg {type BlockId, type ValueId, type ScopeId, type Edge, type Operation}

///|
using @domain {type BindingId, type StoragePath, type PathSegment}

///|
pub(all) struct Diagnostic {
  loc : @basic.Location
  reason : String
} derive(Eq, Debug)

///|
pub(all) enum Preparation {
  NotApplicable
  Prepared(@cfg.PreparedFunction)
  Unsupported(Array[Diagnostic])
}

///|
priv suberror LoweringError {
  UnsupportedSyntax(@basic.Location, String)
}

///|
priv enum ExitKind {
  Normal
  Returning
  Exceptional
  Breaking
  Continuing
} derive(Eq, Hash)

///|
priv struct Target {
  block : BlockId
  depth : Int32
  kind : ExitKind
} derive(Eq, Hash)

///|
priv struct Control {
  label : String?
  break_to : Target
  continue_to : Target?
  binders : Array[BindingId]
}

///|
priv struct Context {
  env : Array[(String, BindingId)]
  scope : ScopeId
  cleanups : Array[Int32]
  controls : Array[Control]
  handler : Target
  returning : Target
}

///|
priv struct Cleanup {
  expr : @untyped_cst.CstNode
  context : Context
  error_only : Bool
}

///|
priv struct CleanupKey {
  cleanups : ReadOnlyArray[Int32]
  target : Target
  arity : Int32
} derive(Eq, Hash)

///|
priv struct ScopeKey {
  parent : ScopeId
  source_span : (Int32, Int32)
} derive(Eq, Hash)

///|
priv struct BindingKey {
  scope : ScopeId
  start_cnum : Int32
  end_cnum : Int32
  name : String
} derive(Eq, Hash)

///|
priv struct Builder {
  blocks : Array[@cfg.Block]
  bindings : Array[@cfg.Binding]
  calls : Array[@cfg.CallSite]
  cleanups : Array[Cleanup]
  cleanup_cache : Map[CleanupKey, BlockId]
  scope_cache : Map[ScopeKey, ScopeId]
  binding_cache : Map[BindingKey, BindingId]
  mut current : BlockId?
  mut value_count : Int32
  mut scope_count : Int32
  loc : @basic.Location
}

///|
fn Builder::value(self : Builder) -> ValueId {
  let value = ValueId(self.value_count)
  self.value_count += 1
  value
}

///|
fn Builder::scope(self : Builder) -> ScopeId {
  let scope = ScopeId(self.scope_count)
  self.scope_count += 1
  scope
}

///|
fn Builder::block(
  self : Builder,
  arity : Int32,
  loc : @basic.Location,
) -> BlockId {
  let id = BlockId(self.blocks.length())
  self.blocks.push({
    parameters: Array::makei(arity, _ => self.value()),
    instructions: [],
    terminator: Abort,
    loc,
  })
  id
}

///|
fn Builder::emit(self : Builder, operation : Operation) -> ValueId {
  let result = self.value()
  if self.current is Some(block) {
    self.blocks[block.0].instructions.push({ result, operation, })
  }
  result
}

///|
fn Builder::end(self : Builder, terminator : @cfg.Terminator) -> Unit {
  if self.current is Some(block) {
    self.blocks[block.0].terminator = terminator
  }
  self.current = None
}

///|
fn edge(block : BlockId, arguments : Array[ValueId]) -> Edge {
  { target: block, arguments, }
}

///|
fn Context::resolve(self : Context, name : String) -> BindingId? {
  for i = self.env.length() - 1; i >= 0; i = i - 1 {
    if self.env[i].0 == name {
      return Some(self.env[i].1)
    }
  }
  None
}

///|
fn Builder::bind(
  self : Builder,
  ctx : Context,
  name : String,
  parameter~ : Bool = false,
  site? : @basic.Location,
) -> (Context, BindingId) {
  let key : BindingKey? = site.map(loc => {
    scope: ctx.scope,
    start_cnum: loc.start.cnum,
    end_cnum: loc.end.cnum,
    name,
  })
  let id = if key is Some(key) && self.binding_cache.get(key) is Some(id) {
    id
  } else {
    let id = BindingId(self.bindings.length())
    if key is Some(key) {
      self.binding_cache[key] = id
    }
    self.bindings.push({ id, name, scope: ctx.scope, parameter, })
    id
  }
  let env = ctx.env.copy()
  env.push((name, id))
  ({ ..ctx, env, }, id)
}

///|
fn root_path(root : BindingId) -> StoragePath {
  { root, segments: [], }
}

///|
fn child_path(path : StoragePath, segment : PathSegment) -> StoragePath {
  let segments = path.segments.copy()
  segments.push(segment)
  { root: path.root, segments, }
}

///|
fn required(
  node : @untyped_cst.CstNode,
  name : String,
) -> @untyped_cst.CstNode raise LoweringError {
  let found = if name == "semantic_name" {
    @cst.raw_child(node, name)
  } else {
    @cst.child(node, name)
  }
  guard found is Some(child) &&
    !(child.kind is (Missing | Expr_MissingExpr | Error)) else {
    raise UnsupportedSyntax(
      node.loc,
      "missing required field \{name} in \{Repr(node.kind)}",
    )
  }
  child
}

///|
fn items(
  node : @untyped_cst.CstNode,
  field : String,
) -> Array[@untyped_cst.CstNode] raise LoweringError {
  @cst.raw_children(required(node, field), "item")
}

///|
fn name_of(node : @untyped_cst.CstNode) -> String? {
  if @cst.normalized_name(node) is Some(name) {
    Some(name)
  } else {
    @cst.name_node(node).bind(@cst.normalized_name)
  }
}

///|
fn required_name(node : @untyped_cst.CstNode) -> String raise LoweringError {
  guard name_of(node) is Some(name) else {
    raise UnsupportedSyntax(node.loc, "missing binding name")
  }
  name
}

///|
fn accessor(node : @untyped_cst.CstNode) -> PathSegment raise LoweringError {
  match node.kind {
    Accessor_Label => Field(required_name(node))
    Accessor_Index => {
      guard @cst.int_payload(node) is Some(index) else {
        raise UnsupportedSyntax(node.loc, "missing tuple index")
      }
      TupleIndex(index)
    }
    _ => raise UnsupportedSyntax(node.loc, "unsupported field accessor")
  }
}

///|
fn index_segment(node : @untyped_cst.CstNode) -> PathSegment {
  if @cst.constant(node) is Some(constant) &&
    constant.kind is (Constant_Int | Constant_UInt) &&
    @cst.string_payload(constant) is Some(text) {
    let normalized = @string.parse_int64(text).to_string() catch { _ => text }
    ConstIndex(normalized)
  } else {
    AnyIndex
  }
}

///|
fn storage_path(
  node : @untyped_cst.CstNode,
  ctx : Context,
) -> StoragePath? raise LoweringError {
  match node.kind {
    Expr_Ident =>
      @cst.normalized_expr_identifier_name(node)
      .bind(name => ctx.resolve(name))
      .map(root_path)
    Expr_Group | Expr_Constraint => storage_path(required(node, "expr"), ctx)
    Expr_Field => {
      let base = storage_path(required(node, "self"), ctx)
      let segment = accessor(required(node, "field"))
      base.map(path => child_path(path, segment))
    }
    Expr_ArrayGet => {
      let base = storage_path(required(node, "self"), ctx)
      let segment = index_segment(required(node, "index"))
      base.map(path => child_path(path, segment))
    }
    _ => None
  }
}

///|
fn label_of(node : @untyped_cst.CstNode) -> String? {
  @cst.raw_child(node, "label").bind(label => {
    if name_of(label) is Some(name) {
      Some(name)
    } else {
      @cst.raw_child(label, "name_value").bind(name_of)
    }
  })
}

///|
fn Builder::exit(
  self : Builder,
  ctx : Context,
  target : Target,
  arguments : Array[ValueId],
) -> Unit raise LoweringError {
  guard self.current is Some(_) else { return }
  let entry = self.cleanup_chain(ctx, target, arguments.length())
  self.end(Jump(edge(entry, arguments)))
}

///|
fn Builder::cleanup_chain(
  self : Builder,
  ctx : Context,
  target : Target,
  arity : Int32,
) -> BlockId raise LoweringError {
  if ctx.cleanups.length() <= target.depth {
    return target.block
  }
  let key : CleanupKey = {
    cleanups: ReadOnlyArray::from_array(ctx.cleanups),
    target,
    arity,
  }
  if self.cleanup_cache.get(key) is Some(block) {
    return block
  }
  let stack = ctx.cleanups.copy()
  let cleanup = self.cleanups[stack.pop().unwrap()]
  let remaining = { ..ctx, cleanups: stack, }
  if cleanup.error_only && target.kind != Exceptional {
    return self.cleanup_chain(remaining, target, arity)
  }
  let saved = self.current
  let entry = self.block(arity, cleanup.expr.loc)
  self.cleanup_cache[key] = entry
  self.current = Some(entry)
  // Capture lexical identities at declaration; read their values at exit.
  let cleanup_ctx = { ..cleanup.context, cleanups: stack, }
  let _ = self.lower(cleanup.expr, cleanup_ctx)
  self.exit(remaining, target, self.blocks[entry.0].parameters)
  self.current = saved
  entry
}

///|
pub fn prepare_function_like(
  node : @untyped_cst.CstNode,
) -> Preparation raise @cfg.InvalidGraph {
  if !(node.kind is (Impl_Function | Impl_ImplMethod)) {
    return NotApplicable
  }
  let declaration = if node.kind is Impl_ImplMethod {
    @cst.raw_child(node, "method").unwrap_or(node)
  } else {
    node
  }
  guard @cst.raw_child(declaration, "body") is Some(body) else {
    if @cst.raw_child(declaration, "decl_body_kind").map(kind => kind.kind)
      is Some(DeclBody_Expr) {
      return Unsupported([
        { loc: node.loc, reason: "missing required function body", },
      ])
    }
    return NotApplicable
  }
  let b : Builder = {
    blocks: [],
    bindings: [],
    calls: [],
    cleanups: [],
    cleanup_cache: {},
    scope_cache: {},
    binding_cache: {},
    current: None,
    value_count: 0,
    scope_count: 0,
    loc: node.loc,
  }
  let entry = b.block(0, node.loc)
  let returned = b.block(1, node.loc)
  b.blocks[returned.0].terminator = Return(b.blocks[returned.0].parameters[0])
  let raised = b.block(1, node.loc)
  b.blocks[raised.0].terminator = Raise(b.blocks[raised.0].parameters[0])
  let mut ctx : Context = {
    env: [],
    scope: b.scope(),
    cleanups: [],
    controls: [],
    handler: { block: raised, depth: 0, kind: Exceptional, },
    returning: { block: returned, depth: 0, kind: Returning, },
  }
  b.current = Some(entry)
  try {
    if @cst.raw_child(declaration, "params") is Some(params) {
      for param in @cst.raw_children(params, "item") {
        if !(param.kind is Parameter_DiscardPositional) {
          let name = if @cst.raw_child(param, "pattern") is Some(pattern) {
            required_name(pattern)
          } else {
            required_name(param)
          }
          let (next, _) = b.bind(ctx, name, parameter=true, site=param.loc)
          ctx = next
        }
      }
    }
    let result = b.lower(body, ctx)
    b.exit(ctx, ctx.returning, [result])
  } catch {
    UnsupportedSyntax(loc, reason) => return Unsupported([{ loc, reason, }])
  }
  Prepared(
    @cfg.PreparedFunction::new({
      entry,
      blocks: b.blocks,
      bindings: b.bindings,
      calls: b.calls,
      value_count: b.value_count,
      scope_count: b.scope_count,
      loc: node.loc,
    }),
  )
}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with Debug::{to_repr}

///|
fn Builder::scope_for(
  self : Builder,
  node : @untyped_cst.CstNode,
  parent : ScopeId,
) -> ScopeId {
  let key : ScopeKey = { parent, source_span: node.source_span, }
  if self.scope_cache.get(key) is Some(scope) {
    return scope
  }
  let scope = self.scope()
  self.scope_cache[key] = scope
  scope
}
