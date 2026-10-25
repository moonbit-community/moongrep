///|
fn sample_graph() -> @cfg.Graph {
  let parsed = @untyped_cst.parse_structure("fn sample {}")
  let loc = parsed.root().loc
  {
    entry: @cfg.BlockId(0),
    blocks: [
      {
        parameters: [],
        instructions: [{ result: @cfg.ValueId(0), operation: Clean, }],
        terminator: Return(@cfg.ValueId(0)),
        loc,
      },
    ],
    bindings: [],
    calls: [],
    value_count: 1,
    scope_count: 0,
    loc,
  }
}

///|
test "validator rejects invalid edges arity and missing_definition values" {
  let valid = sample_graph()
  inspect(valid.validate().length(), content="0")
  debug_inspect(
    { ..valid, value_count: -1, }.validate(),
    content="[\"negative graph count\"]",
  )
  let block = valid.blocks[0]
  let bad_target = {
    ..valid,
    blocks: [
      {
        ..block,
        terminator: Jump({ target: @cfg.BlockId(2), arguments: [], }),
      },
    ],
  }
  debug_inspect(bad_target.validate(), content="[\"invalid edge target\"]")
  let bad_arity = {
    ..valid,
    blocks: [
      {
        ..block,
        terminator: Jump({
          target: @cfg.BlockId(0),
          arguments: [@cfg.ValueId(0)],
        }),
      },
    ],
  }
  debug_inspect(bad_arity.validate(), content="[\"edge arity mismatch\"]")
  let missing_definition = {
    ..valid,
    value_count: 2,
    blocks: [{ ..block, terminator: Return(@cfg.ValueId(1)), }],
  }
  debug_inspect(
    missing_definition.validate(),
    content="[\"value used before definition\"]",
  )
  try @cfg.PreparedFunction::new(missing_definition) catch {
    @cfg.InvalidGraph::InvalidGraph(errors) =>
      assert_eq(errors, missing_definition.validate())
  } noraise {
    _ => fail("expected invalid graph")
  }
}

///|
test "SCCs have stable topological order" {
  let graph = sample_graph()
  let block = graph.blocks[0]
  let graph = {
    ..graph,
    blocks: [
      {
        ..block,
        instructions: [],
        terminator: Jump({ target: @cfg.BlockId(1), arguments: [], }),
      },
      {
        ..block,
        instructions: [],
        terminator: Jump({ target: @cfg.BlockId(2), arguments: [], }),
      },
      {
        ..block,
        instructions: [],
        terminator: Branch(
          @cfg.ValueId(0),
          { target: @cfg.BlockId(1), arguments: [], },
          { target: @cfg.BlockId(3), arguments: [], },
        ),
      },
      block,
    ],
  }
  debug_inspect(
    graph.components().map(component => component.map(block => block.0)),
    content="[[0], [1, 2], [3]]",
  )
}

///|
test "liveness substitutes all jump parameters simultaneously" {
  let original = sample_graph()
  let loc = original.loc
  let graph : @cfg.Graph = {
    ..original,
    value_count: 5,
    blocks: [
      {
        parameters: [],
        instructions: [
          { result: @cfg.ValueId(0), operation: Clean, },
          { result: @cfg.ValueId(1), operation: Clean, },
        ],
        terminator: Jump({
          target: @cfg.BlockId(1),
          arguments: [@cfg.ValueId(0), @cfg.ValueId(1)],
        }),
        loc,
      },
      {
        parameters: [@cfg.ValueId(2), @cfg.ValueId(3)],
        instructions: [],
        terminator: Branch(
          @cfg.ValueId(2),
          {
            target: @cfg.BlockId(1),
            arguments: [@cfg.ValueId(3), @cfg.ValueId(2)],
          },
          { target: @cfg.BlockId(2), arguments: [@cfg.ValueId(2)], },
        ),
        loc,
      },
      {
        parameters: [@cfg.ValueId(4)],
        instructions: [],
        terminator: Return(@cfg.ValueId(4)),
        loc,
      },
    ],
  }
  assert_eq(graph.validate(), [])
  let live = graph.live_values()
  debug_inspect((live[1][2], live[1][3]), content="(true, true)")
}
