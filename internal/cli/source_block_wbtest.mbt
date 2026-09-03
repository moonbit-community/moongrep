///|
test "source block splitter uses exact line prefixes" {
  let source =
    #|header
    #|  ///|
    #|still first
    #|///| docs
    #|fn second { target() }
    #|
  let blocks = split_source_blocks(source)
  guard blocks is [first, second] else { fail("expected two source blocks") }
  let _ : StringView = first.source
  inspect(first.source, content="header\n  ///|\nstill first\n")
  assert_eq(first.source.start_offset(), 0)
  assert_eq(first.start_line, 1)
  assert_eq(first.start_cnum, 0)
  inspect(second.source, content="///| docs\nfn second { target() }\n")
  assert_eq(second.source.start_offset(), first.source.length())
  assert_eq(second.start_line, 4)
  assert_eq(second.start_cnum, first.source.char_length())
}

///|
test "source block splitter preserves fallback and consecutive delimiters" {
  let unsplit = "fn sample { target() }\n"
  guard split_source_blocks(unsplit) is [whole] else {
    fail("expected an unsplit source block")
  }
  assert_eq(whole.source, unsplit)
  assert_eq(whole.start_line, 1)
  assert_eq(whole.start_cnum, 0)
  let consecutive = split_source_blocks("///|\n///|\nfn sample { target() }\n")
  guard consecutive is [empty_doc, sample] else {
    fail("expected consecutive source blocks")
  }
  inspect(empty_doc.source, content="///|\n")
  assert_eq(empty_doc.start_line, 1)
  assert_eq(empty_doc.start_cnum, 0)
  inspect(sample.source, content="///|\nfn sample { target() }\n")
  assert_eq(sample.start_line, 2)
  assert_eq(sample.start_cnum, empty_doc.source.char_length())
}

///|
fn assert_block_position_equal(
  actual : @basic.Position,
  expected : @basic.Position,
) -> Unit raise {
  assert_eq(actual.fname, expected.fname)
  assert_eq(actual.lnum, expected.lnum)
  assert_eq(actual.bol, expected.bol)
  assert_eq(actual.cnum, expected.cnum)
  assert_eq(actual.column(), expected.column())
}

///|
test "source block rebases parser locations to the original source" {
  let source = "fn first { \"🤣\" }\r\n///|\r\nfn second {\r\n  target()\r\n}\r\n"
  let blocks = split_source_blocks(source)
  guard blocks is [_, second_block] else { fail("expected two source blocks") }
  let whole = @untyped_cst.parse_structure(source, name="sample.mbt")
  guard whole.diagnostics_view().is_empty() else {
    fail("expected whole source to parse")
  }
  guard @cst.toplevel_nodes(whole.root()) is [_, expected_node] else {
    fail("expected two whole-source nodes")
  }
  let (block_impls, block_reports) = parse_source_block(
    second_block.source,
    "sample.mbt",
  )
  guard block_reports is [] else { fail("expected source block to parse") }
  guard block_impls is [block_node] else {
    fail("expected one source-block node")
  }
  let actual = second_block.rebase_location(block_node.loc)
  let expected = expected_node.loc
  assert_block_position_equal(actual.start, expected.start)
  assert_block_position_equal(actual.end, expected.end)
}

///|
test "source block view parser preserves parser CST semantics" {
  let source =
    #|///| API documentation
    #|fn documented(value : Int) -> Int {
    #|  value + 1
    #|}
    #|
  guard split_source_blocks(source) is [block] else {
    fail("expected one source block")
  }
  let whole = @untyped_cst.parse_structure(source, name="documented.mbt")
  let (block_impls, block_reports) = parse_source_block(
    block.source,
    "documented.mbt",
  )
  guard whole.diagnostics_view().is_empty() && block_reports is [] else {
    fail("expected both parser entries to succeed")
  }
  guard (@cst.toplevel_nodes(whole.root()), block_impls)
    is ([whole_node], [block_node]) else {
    fail("expected one top-level node from both parser entries")
  }
  assert_eq("\{Repr(whole_node)}", "\{Repr(block_node)}")
}

///|
test "source block parser preserves recovery diagnostics" {
  let source = "fn sample { target()\n"
  let (nodes, reports) = parse_source_block(source, "bad.mbt")
  assert_eq(nodes.length(), 1)
  assert_true(reports.length() > 0)
}
