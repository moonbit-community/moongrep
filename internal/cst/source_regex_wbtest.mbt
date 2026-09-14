///|
test "explicit regex binders share semantic declaration identity across shadowing" {
  for label in ["before", "after"] {
    for
      expression in [
        "lexscan input { (re\"a\", \{label}=item) => { BODY } }",
        "if input =~ (re\"a\", \{label}=item) { BODY }",
      ] {
      let body = "sink(item); let item = source(); sink(item)"
      let root = parse_identifier_source(
        "fn sample(item : Int) { sink(item); " +
        expression.replace(old="BODY", new=body) +
        "; sink(item) }",
      )
      let index = SourceIndex::new(root)
      let bindings = index.nodes.filter_map(entry => {
        if entry.node.kind is @untyped_cst.Binding_Regex {
          Some(entry.node)
        } else {
          None
        }
      })
      guard bindings is [binding] else { fail("expected one regex binding") }
      let syntax = raw_child(binding, "binder").unwrap()
      let semantic = raw_child(binding, "semantic_binder").unwrap()
      let origin = index.identifier_source(semantic).unwrap()
      assert_eq(origin.binding, Lexical(Some(index.node_id(semantic))))
      assert_eq(index.identifier_source(syntax), Some(origin))
      assert_true(index.node_id(syntax) != index.node_id(semantic))
      assert_eq(
        index.identifier_source(raw_child(syntax, "name_value").unwrap()),
        Some(origin),
      )
      for label_field in ["name", "semantic_label"] {
        let name = raw_child(binding, label_field).unwrap()
        assert_eq(index.identifier_source(name).unwrap().binding, NonLexical)
      }
      let binders = indexed_names(
        index,
        kind => kind is @untyped_cst.Name_Binder,
        "item",
      )
      let references = indexed_names(
        index,
        kind => kind is @untyped_cst.Name_Var,
        "item",
      )
      assert_eq(binders.length(), 3)
      let outer = index.identifier_source(binders[0]).unwrap().binding
      let shadow = index.identifier_source(binders[2]).unwrap().binding
      assert_true(outer != origin.binding && shadow != origin.binding)
      assert_eq(
        references.map(node => index.identifier_source(node).unwrap().binding),
        [outer, origin.binding, shadow, outer],
      )
      guard outer is Lexical(parameter) else { fail("expected a parameter") }
      assert_eq(
        index.resolve(index.scope(index.direct(index.node_id(syntax))), "item"),
        parameter,
      )
      ignore(assert_direct_indexed_compatible(root))
    }
  }
}

///|
test "regex labels and absent or wildcard binders do not declare variables" {
  for bindings in ["before~, after~", "before=_, after=_"] {
    let index = SourceIndex::new(
      parse_identifier_source(
        "fn sample { lexscan input { (re\"a\", \{bindings}) => sink(before, after) } }",
      ),
    )
    for name in ["before", "after"] {
      let references = indexed_names(
        index,
        kind => kind is @untyped_cst.Name_Var,
        name,
      )
      assert_eq(references.length(), 1)
      let reference = references[0]
      assert_eq(
        index.identifier_source(reference).unwrap().binding,
        Lexical(None),
      )
      assert_eq(
        index.resolve(index.scope(index.direct(index.node_id(reference))), "_"),
        None,
      )
    }
    inspect(index.scopes.length(), content="0")
  }
}
