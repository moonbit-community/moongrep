///|
test "cleanup cache keeps a snapshot of the original stack" {
  let parsed = @untyped_cst.parse_expression("()")
  guard parsed.diagnostics_view().is_empty() else {
    fail("expected valid cleanup expression")
  }
  let expr = @cst.expression_root(parsed.root())
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
    loc: expr.loc,
  }
  let returned = b.block(1, expr.loc)
  b.blocks[returned.0].terminator = Return(b.blocks[returned.0].parameters[0])
  let target : Target = { block: returned, depth: 0, kind: Returning, }
  let outer : Context = {
    env: [],
    scope: b.scope(),
    cleanups: [],
    controls: [],
    handler: { ..target, kind: Exceptional, },
    returning: target,
  }
  b.cleanups.push({ expr, context: outer, error_only: false, })
  let stack = [0]
  let ctx = { ..outer, cleanups: stack, }
  let entry = b.cleanup_chain(ctx, target, 1)
  let block_count = b.blocks.length()
  stack[0] = 1
  let original = { ..ctx, cleanups: [0], }
  let cached = b.cleanup_chain(original, target, 1)
  inspect(cached == entry, content="true")
  inspect(b.blocks.length() - block_count, content="0")
}
