///|
fn parse_identifier_source(source : String) -> @untyped_cst.CstNode raise {
  let parsed = @untyped_cst.parse_structure(
    source,
    name="identifier-source-test",
  )
  guard parsed.diagnostics_view().is_empty() else {
    fail("unexpected identifier source diagnostics")
  }
  parsed.root()
}

///|
fn indexed_names(
  index : SourceIndex,
  kind : (@untyped_cst.NodeKind) -> Bool,
  name : String,
) -> Array[@untyped_cst.CstNode] {
  let nodes = index.nodes.filter_map(entry => {
    if kind(entry.node.kind) && normalized_name(entry.node) == Some(name) {
      Some(entry.node)
    } else {
      None
    }
  })
  nodes.sort_by((left, right) => left.source_span.0.compare(right.source_span.0))
  nodes
}

///|
test "identifier origins distinguish declarations from their incoming scope" {
  let root = parse_identifier_source(
    "fn sample(item : Int) { let item = item; if input is Some(item) { sink(item) } else { sink(item) } }",
  )
  let index = SourceIndex::new(root)
  let binders = indexed_names(
    index,
    kind => kind is Name_Binder,
    "item",
  )
  let references = indexed_names(
    index,
    kind => kind is Name_Var,
    "item",
  )
  assert_eq(binders.length(), 3)
  assert_eq(references.length(), 3)
  let origins = binders.map(node => {
    index.identifier_source(node).unwrap().binding
  })
  assert_true(origins.all(origin => origin is Lexical(Some(_))))
  assert_true(origins[0] != origins[1] && origins[1] != origins[2])
  assert_true(
    references.map(node => index.identifier_source(node).unwrap().binding) ==
    [origins[0], origins[2], origins[1]],
  )
  let declaration = index.node_id(binders[1])
  guard origins[0] is Lexical(parameter) else { fail("expected a parameter") }
  assert_true(
    index.resolve(index.scope(index.direct(declaration)), "item") == parameter,
  )
}

///|
test "enumview parameters retain their binding across nested block shadowing" {
  let root = parse_identifier_source(
    "enumview ValueView { Value(Int) } for Int with view(item) { sink(item); { let item = source(); sink(item) }; Value(item) }",
  )
  let index = SourceIndex::new(root)
  let binders = indexed_names(
    index,
    kind => kind is Name_Binder,
    "item",
  )
  let references = indexed_names(
    index,
    kind => kind is Name_Var,
    "item",
  )
  assert_eq(binders.length(), 2)
  assert_eq(references.length(), 3)
  let origins = binders.map(node => {
    index.identifier_source(node).unwrap().binding
  })
  assert_true(origins.all(origin => origin is Lexical(Some(_))))
  assert_true(origins[0] != origins[1])
  assert_true(
    references.map(node => index.identifier_source(node).unwrap().binding) ==
    [origins[0], origins[1], origins[0]],
  )
}

///|
test "field label constructor and type names are not lexical references" {
  let root = parse_identifier_source(
    "fn sample(item : Item) { object.item; call(item=item); let value : Item = Some(item); value }",
  )
  let index = SourceIndex::new(root)
  let roles : Array[((@untyped_cst.NodeKind) -> Bool, String)] = [
    (kind => kind is Accessor_Label, "item"),
    (kind => kind is Name_Label, "item"),
    (kind => kind is Name_ConstrId, "Item"),
    (kind => kind is Name_Constructor, "Some"),
  ]
  for position, (kind, name) in roles {
    let names = indexed_names(index, kind, name)
    guard !names.is_empty() else { fail("missing identifier role \{position}") }
    for node in names {
      assert_eq(index.identifier_source(node).unwrap().binding, NonLexical)
    }
  }
  for
    node in indexed_names(index, kind => kind is Name_Var, "item") {
    assert_true(
      index.identifier_source(node).unwrap().binding is Lexical(Some(_)),
    )
  }
}

///|
test "free references retain an unbound origin before later declarations" {
  let root = parse_identifier_source(
    "fn sample { sink(item); let item = source(); sink(item) }",
  )
  let index = SourceIndex::new(root)
  let references = indexed_names(
    index,
    kind => kind is Name_Var,
    "item",
  )
  assert_eq(references.length(), 2)
  debug_inspect(
    index.identifier_source(references[0]).unwrap().binding,
    content="Lexical(None)",
  )
  assert_true(
    index.identifier_source(references[1]).unwrap().binding is Lexical(Some(_)),
  )
}

///|
fn check_wrapped_binder_source(body : String) -> Unit raise {
  let root = parse_identifier_source(
    "fn sample(item : Int) { sink(item); \{body} }",
  )
  let index = SourceIndex::new(root)
  let owners = index.nodes.filter_map(entry => {
    if entry.node.kind
      is (Pattern_Alias
      | RegexPattern_Alias
      | Expr_Quantifier) {
      Some(entry.node)
    } else {
      None
    }
  })
  guard owners is [owner] else { fail("expected one wrapped binder") }
  let syntax = raw_child(owner, "name").unwrap()
  let semantic = child(owner, "name").unwrap()
  let origin = index.identifier_source(syntax).unwrap()
  assert_eq(origin.binding, Lexical(Some(index.node_id(owner))))
  assert_eq(index.identifier_source(semantic), Some(origin))
  assert_true(index.node_id(syntax) != index.node_id(semantic))
  let binders = indexed_names(
    index,
    kind => kind is Name_Binder,
    "item",
  )
  let references = indexed_names(
    index,
    kind => kind is Name_Var,
    "item",
  )
  assert_eq(binders.length(), 2)
  assert_eq(
    references.map(node => index.identifier_source(node).unwrap().binding),
    [
      index.identifier_source(binders[0]).unwrap().binding,
      origin.binding,
      index.identifier_source(binders[1]).unwrap().binding,
    ],
  )
  guard index.identifier_source(binders[0]).unwrap().binding
    is Lexical(parameter) else {
    fail("expected a parameter binding")
  }
  assert_eq(
    index.resolve(index.scope(index.direct(index.node_id(syntax))), "item"),
    parameter,
  )
}

///|
test "alias syntax and semantic names retain declaration identity" {
  for
    body in [
      "match input { Some(_) as item => { sink(item); let item = source(); sink(item) } }",
      "lexmatch input { (re\"a\" as item) => { sink(item); let item = source(); sink(item) } }",
    ] {
    check_wrapped_binder_source(body)
  }
}

///|
test "quantifier syntax and semantic names retain declaration identity" {
  for quantifier in ["∀", "∃"] {
    check_wrapped_binder_source(
      "\{quantifier} item : Int, { sink(item); let item = source(); sink(item) }",
    )
  }
}

///|
test "assignment targets resolve at the assignment occurrence" {
  for operator in ["=", "+="] {
    let root = parse_identifier_source(
      "fn sample { item \{operator} 0; let mut item = 1; item \{operator} 2; { let mut item = 3; item \{operator} 4 }; item \{operator} 5; object.item \{operator} 6 }",
    )
    let index = SourceIndex::new(root)
    let binders = indexed_names(
      index,
      kind => kind is Name_Binder,
      "item",
    )
    let references = indexed_names(
      index,
      kind => kind is Name_Var,
      "item",
    )
    assert_eq(binders.length(), 2)
    let outer = index.identifier_source(binders[0]).unwrap().binding
    let inner = index.identifier_source(binders[1]).unwrap().binding
    assert_true(outer != inner)
    assert_eq(
      references.map(node => index.identifier_source(node).unwrap().binding),
      [Lexical(None), outer, inner, outer],
    )
    let fields = indexed_names(
      index,
      kind => kind is Accessor_Label,
      "item",
    )
    assert_eq(fields.length(), 1)
    assert_eq(index.identifier_source(fields[0]).unwrap().binding, NonLexical)
  }
}

///|
test "parameter defaults see preceding parameters and bodies see all parameters" {
  for
    source in [
      "fn sample(item : Int, next~ : Int = item, last~ : Int = next) { sink(item, next, last) }",
      "fn sample { fn nested(item : Int, next~ : Int = item, last~ : Int = next) { sink(item, next, last) } }",
      "fn sample { fn(item : Int, next~ : Int = item, last~ : Int = next) { sink(item, next, last) } }",
      "fn sample { letrec nested = fn(item : Int, next~ : Int = item, last~ : Int = next) { sink(item, next, last) } }",
    ] {
    let index = SourceIndex::new(parse_identifier_source(source))
    for (name, count) in [("item", 2), ("next", 2), ("last", 1)] {
      let binders = indexed_names(
        index,
        kind => kind is Name_Binder,
        name,
      )
      let references = indexed_names(
        index,
        kind => kind is Name_Var,
        name,
      )
      assert_eq(binders.length(), 1)
      assert_eq(references.length(), count)
      let binding = index.identifier_source(binders[0]).unwrap().binding
      assert_true(binding is Lexical(Some(_)))
      for reference in references {
        assert_eq(index.identifier_source(reference).unwrap().binding, binding)
      }
    }
  }
}

///|
test "current and later parameters do not shadow outer bindings in defaults" {
  let index = SourceIndex::new(
    parse_identifier_source(
      "fn sample(item : Int, later : Int) { fn nested(first~ : Int = later, item~ : Int = item, later~ : Int = item) { sink(first, item, later) } }",
    ),
  )
  for
    (name, expected) in [("item", [0, 1, 1]), ("later", [0, 1]), ("first", [0])] {
    let binders = indexed_names(
      index,
      kind => kind is Name_Binder,
      name,
    )
    let references = indexed_names(
      index,
      kind => kind is Name_Var,
      name,
    )
    let bindings = binders.map(node => {
      index.identifier_source(node).unwrap().binding
    })
    assert_true(bindings.all(binding => binding is Lexical(Some(_))))
    if name != "first" {
      assert_eq(bindings.length(), 2)
      assert_true(bindings[0] != bindings[1])
    }
    assert_eq(
      references.map(node => index.identifier_source(node).unwrap().binding),
      expected.map(position => bindings[position]),
    )
  }
}

///|
test "for update names retain init bindings across condition and body shadowing" {
  let index = SourceIndex::new(
    parse_identifier_source(
      "fn sample { for i = 0, j = 1; next(i) is Some(i); j = i, i = j { sink(i, j); let i = source(); sink(i) } }",
    ),
  )
  let loop_nodes = index.nodes.filter_map(entry => {
    if entry.node.kind is Expr_For {
      Some(entry.node)
    } else {
      None
    }
  })
  guard loop_nodes is [loop_node] else { fail("expected one for loop") }
  let loop_id = index.node_id(loop_node)
  let initializers = index.raw_all(index.raw(loop_id, "init").unwrap(), "item")
  let updates = index.raw_all(index.raw(loop_id, "continue").unwrap(), "item")
  assert_eq(initializers.length(), 2)
  assert_eq(updates.length(), 2)
  let origins = initializers.map(id => {
    index.identifier_source(name_node(index.node(id)).unwrap()).unwrap().binding
  })
  assert_true(origins.all(origin => origin is Lexical(Some(_))))
  assert_true(origins[0] != origins[1])
  // Updates are deliberately in the opposite order to their declarations.
  for position, update in updates {
    let name = name_node(index.node(update)).unwrap()
    let origin = index.identifier_source(name).unwrap()
    assert_eq(origin.binding, origins[1 - position])
  }
  let binders = indexed_names(
    index,
    kind => kind is Name_Binder,
    "i",
  )
  assert_eq(binders.length(), 4)
  let condition = index.identifier_source(binders[1]).unwrap().binding
  let body_binding = index.identifier_source(binders[3]).unwrap().binding
  assert_true(
    condition != origins[0] &&
    body_binding != condition &&
    body_binding != origins[0],
  )
  let references = indexed_names(
    index,
    kind => kind is Name_Var,
    "i",
  )
  assert_true(
    references.map(node => index.identifier_source(node).unwrap().binding) ==
    [origins[0], condition, condition, body_binding],
  )
  let j_references = indexed_names(
    index,
    kind => kind is Name_Var,
    "j",
  )
  assert_true(
    j_references.map(node => index.identifier_source(node).unwrap().binding) ==
    [origins[1], origins[1]],
  )
  // Only the two loop variables, condition binder, and local are declarations.
  assert_eq(index.scopes.length(), 4)
}
