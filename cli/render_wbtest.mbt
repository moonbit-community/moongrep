///|
fn render_test_location(
  start_line : Int,
  start_column : Int,
  end_line : Int,
  end_column : Int,
) -> @basic.Location {
  {
    start: {
      fname: "test.mbt",
      lnum: start_line,
      bol: 0,
      cnum: start_column - 1,
    },
    end: { fname: "test.mbt", lnum: end_line, bol: 0, cnum: end_column - 1 },
  }
}

///|
fn render_test_hit(start_line : Int, end_line : Int) -> ScanHit {
  let context_lines : Array[SourceContextLine] = []
  for line_number in (start_line - 1)..<=(end_line + 1) {
    context_lines.push({
      line_number,
      text: "  line \{line_number}",
      is_match: line_number >= start_line && line_number <= end_line,
    })
  }
  let end_text = "  line \{end_line}"
  {
    finding: {
      file: "test.mbt",
      rule_id: "test-rule",
      description: "Test finding.",
      pattern_index: 0,
      loc: render_test_location(start_line, 1, end_line, end_text.length() + 1),
      outer_loc: None,
    },
    matched_source: "line \{start_line}",
    source_context: { lines: context_lines },
  }
}

///|
async test "matched source line prefix is not dimmed" {
  let match_loc = render_test_location(12, 13, 12, 21)
  inspect(
    render_source_context_line(
      { line_number: 12, text: "let value = target()", is_match: true },
      match_loc,
      2,
    ),
    content="12 | let value = \u{1b}[93mtarget()\u{1b}[39m",
  )
  let arr = [5, 6, 7]
  for i = 0; i < arr.length(); i = i + 1 {
    if arr[i] == 0 {
      @stdio.stdout.write("\{i}\n")
    }
  }
}

///|
test "source context honors no color rendering" {
  let context_line = { line_number: 1, text: "fn sample {", is_match: false }
  let match_line = { line_number: 3, text: "  target()", is_match: true }
  let match_loc = render_test_location(3, 3, 3, 11)
  inspect(
    render_source_context_line(context_line, match_loc, 1, no_color=true),
    content="1 | fn sample {",
  )
  inspect(
    render_source_context_line(match_line, match_loc, 1, no_color=true),
    content="3 >   target()",
  )
  inspect(
    render_source_context_line(match_line, match_loc, 1),
    content="3 |   \u{1b}[93mtarget()\u{1b}[39m",
  )
  assert_false(
    render_source_context_line(context_line, match_loc, 1, no_color=true).contains(
      "\u{1b}[90m",
    ),
  )
}

///|
test "matched expression highlighting follows multiline location columns" {
  let match_loc = render_test_location(3, 3, 5, 4)
  inspect(
    render_source_context_line(
      { line_number: 3, text: "  match value {", is_match: true },
      match_loc,
      1,
    ),
    content="3 |   \u{1b}[93mmatch value {\u{1b}[39m",
  )
  inspect(
    render_source_context_line(
      { line_number: 4, text: "    Some(_) => true", is_match: true },
      match_loc,
      1,
    ),
    content="4 | \u{1b}[93m    Some(_) => true\u{1b}[39m",
  )
  inspect(
    render_source_context_line(
      { line_number: 5, text: "  } trailing", is_match: true },
      match_loc,
      1,
    ),
    content="5 | \u{1b}[93m  }\u{1b}[39m trailing",
  )
}

///|
test "matched expression highlighting uses UTF-16 location offsets" {
  let match_loc = render_test_location(7, 6, 7, 14)
  inspect(
    render_source_context_line(
      { line_number: 7, text: "  \u{1f600} target()", is_match: true },
      match_loc,
      1,
    ),
    content="7 |   \u{1f600} \u{1b}[93mtarget()\u{1b}[39m",
  )
}

///|
test "matched expressions collapse after six lines in every color mode" {
  assert_false(
    render_scan_hit(render_test_hit(8, 13), no_color=true).contains("omitted"),
  )
  inspect(
    render_scan_hit(render_test_hit(8, 14), no_color=true),
    content=(
      #|test.mbt:8:1-14:10
      #|rule: test-rule
      #|description:
      #|  Test finding.
      #|source:
      #| 7 |   line 7
      #| 8 >   line 8
      #| 9 >   line 9
      #|10 >   line 10
      #|.. >   line 11: 1 matched line omitted
      #|12 >   line 12
      #|13 >   line 13
      #|14 >   line 14
      #|15 |   line 15
    ),
  )
  inspect(
    render_omitted_source_lines(6, 12, 2, "    ", no_color=true),
    content=" . >     line 6-12: 7 matched lines omitted",
  )
  inspect(
    render_omitted_source_lines(261, 262, 3, "  "),
    content="\u{1b}[90m... |   line 261-262: 2 matched lines omitted\u{1b}[39m",
  )
  inspect(
    render_omitted_source_lines(1000, 1001, 4, "\t", no_color=true),
    content=" ... > \tline 1000-1001: 2 matched lines omitted",
  )
}
