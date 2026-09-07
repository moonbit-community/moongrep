///|
fn tokscan_test_hits(
  source : String,
  patterns : Array[String],
) -> Array[String] raise {
  @tokmatch.Matcher::compile(patterns)
  .find_matches(source, name="sample.mbt")
  .map(hit => {
    let loc = hit.loc
    let start = source
      .offset_of_nth_char(loc.start.cnum)
      .unwrap_or(source.length())
    let end = source.offset_of_nth_char(loc.end.cnum).unwrap_or(source.length())
    "\{hit.pattern_index + 1}:sample.mbt:\{loc.start.lnum}:\{loc.start.column()}-\{loc.end.lnum}:\{loc.end.column()}:\{source[start:end]}"
  })
}

///|
test "compiled matcher can be reused for independent source blocks" {
  let matcher = @tokmatch.Matcher::compile(["a a"])
  debug_inspect(
    matcher
    .find_matches("a a a", name="first.mbt")
    .map(hit => (hit.pattern_index, hit.loc.start.fname, hit.loc.start.column())),
    content=(
      #|[(0, "first.mbt", 1), (0, "first.mbt", 3)]
    ),
  )
  debug_inspect(
    matcher
    .find_matches("b a a", name="second.mbt")
    .map(hit => (hit.pattern_index, hit.loc.start.fname, hit.loc.start.column())),
    content=(
      #|[(0, "second.mbt", 3)]
    ),
  )
  inspect(
    @tokmatch.Matcher::compile([]).find_matches("a").length(),
    content="0",
  )
}

///|
test "matcher distinguishes indexed pattern errors from source lexical errors" {
  try @tokmatch.Matcher::compile(["a", "", "$later"]) catch {
    @tokmatch.PatternError(index~, reason~) =>
      debug_inspect(
        (index, reason),
        content=(
          #|(1, "pattern contains no tokens")
        ),
      )
  } noraise {
    _ => fail("expected empty pattern error")
  }
  try @tokmatch.Matcher::compile(["a", "#tag($bad)", ""]) catch {
    @tokmatch.PatternError(index~, reason~) =>
      debug_inspect(
        (index, reason),
        content=(
          #|(1, "attribute #tag: line 1, column 2: unrecognized character u32: $")
        ),
      )
  } noraise {
    _ => fail("expected pattern lexical error")
  }
  let matcher = @tokmatch.Matcher::compile(["a"])
  try matcher.find_matches("a\n#tag($bad)") catch {
    @tokmatch.LexError(reason) =>
      inspect(
        reason,
        content="attribute #tag: line 1, column 2: unrecognized character u32: $",
      )
  } noraise {
    _ => fail("expected source lexical error")
  }
}

///|
test "tokscan keeps duplicates overlaps shared prefixes and source order" {
  debug_inspect(
    tokscan_test_hits("a a a b a", ["a a", "a", "a a", "a a b"]),
    content=(
      #|[
      #|  "1:sample.mbt:1:1-1:4:a a",
      #|  "2:sample.mbt:1:1-1:2:a",
      #|  "3:sample.mbt:1:1-1:4:a a",
      #|  "1:sample.mbt:1:3-1:6:a a",
      #|  "2:sample.mbt:1:3-1:4:a",
      #|  "3:sample.mbt:1:3-1:6:a a",
      #|  "4:sample.mbt:1:3-1:8:a a b",
      #|  "2:sample.mbt:1:5-1:6:a",
      #|  "2:sample.mbt:1:9-1:10:a",
      #|]
    ),
  )
  debug_inspect(
    tokscan_test_hits("a b a b a b a c", ["a b a b a c", "a b a"]),
    content=(
      #|[
      #|  "2:sample.mbt:1:1-1:6:a b a",
      #|  "1:sample.mbt:1:5-1:16:a b a b a c",
      #|  "2:sample.mbt:1:5-1:10:a b a",
      #|  "2:sample.mbt:1:9-1:14:a b a",
      #|]
    ),
  )
}

///|
test "tokscan matches token boundaries and ignores comments" {
  debug_inspect(
    tokscan_test_hits("targeted target // target\n(target)", ["target", "get"]),
    content=(
      #|["1:sample.mbt:1:10-1:16:target", "1:sample.mbt:2:2-2:8:target"]
    ),
  )
  debug_inspect(
    tokscan_test_hits("foo( // ignored\n 1 )", [
      "foo(1)", "foo( // pattern\n 1)",
    ]),
    content=(
      #|[
      #|  "1:sample.mbt:1:1-2:5:foo( // ignored\n 1 )",
      #|  "2:sample.mbt:1:1-2:5:foo( // ignored\n 1 )",
      #|]
    ),
  )
  debug_inspect(
    tokscan_test_hits("x.field .Field .0 .(x)", [
      "field", ".field", ".Field", ".0", ".(x)",
    ]),
    content=(
      #|[
      #|  "2:sample.mbt:1:2-1:8:.field",
      #|  "3:sample.mbt:1:9-1:15:.Field",
      #|  "4:sample.mbt:1:16-1:18:.0",
      #|  "5:sample.mbt:1:19-1:23:.(x)",
      #|]
    ),
  )
}

///|
test "tokscan normalizes semicolons and only trims trailing pattern ASI" {
  debug_inspect(
    tokscan_test_hits("a\nb; c", [
      "a;b", "a\nb", "b;", "a\n", "c\n\n// comment\n",
    ]),
    content=(
      #|[
      #|  "1:sample.mbt:1:1-2:2:a\nb",
      #|  "2:sample.mbt:1:1-2:2:a\nb",
      #|  "4:sample.mbt:1:1-1:2:a",
      #|  "3:sample.mbt:2:1-2:3:b;",
      #|  "5:sample.mbt:2:4-2:5:c",
      #|]
    ),
  )
  debug_inspect(
    tokscan_test_hits("a", ["a;", "a;\n", "a\n", "a // comment\n"]),
    content=(
      #|["3:sample.mbt:1:1-1:2:a", "4:sample.mbt:1:1-1:2:a"]
    ),
  )
  debug_inspect(
    tokscan_test_hits("a b", ["a b", "a\nb"]),
    content=(
      #|["1:sample.mbt:1:1-1:4:a b"]
    ),
  )
}

///|
test "tokscan preserves literal kinds spelling and escapes" {
  let source =
    #|1 01 1.0 1.0F "a" "\u0061" 'a' b'a' b"a" re"a" #|a
  debug_inspect(
    tokscan_test_hits(source, [
      "1", "01", "1.0", "1.0F", "\"a\"", "\"\\u0061\"", "'a'", "b'a'", "b\"a\"",
      "re\"a\"", "#|a",
    ]),
    content=(
      #|[
      #|  "1:sample.mbt:1:1-1:2:1",
      #|  "2:sample.mbt:1:3-1:5:01",
      #|  "3:sample.mbt:1:6-1:9:1.0",
      #|  "4:sample.mbt:1:10-1:14:1.0F",
      #|  "5:sample.mbt:1:15-1:18:\"a\"",
      #|  "6:sample.mbt:1:19-1:27:\"\\u0061\"",
      #|  "7:sample.mbt:1:28-1:31:'a'",
      #|  "8:sample.mbt:1:32-1:36:b'a'",
      #|  "9:sample.mbt:1:37-1:41:b\"a\"",
      #|  "10:sample.mbt:1:42-1:47:re\"a\"",
      #|  "11:sample.mbt:1:48-1:51:#|a",
      #|]
    ),
  )
}

///|
test "tokscan recursively compares complete interpolation tokens" {
  let source =
    #|"prefix \{ foo ( 1 ) } suffix" "\{ "\{ x + 1 }" }" b"\{ x + 1 }" re"\{ x + 1 }"
  let patterns = [
    (
      #|"prefix \{foo(1)} suffix"
    ),
    (
      #|"\{"\{x+1}"}"
    ),
    (
      #|b"\{x+1}"
    ),
    (
      #|re"\{x+1}"
    ),
    (
      #|"prefix \{foo(1)} different"
    ),
    "foo(1)",
    "x + 1",
  ]
  debug_inspect(
    tokscan_test_hits(source, patterns),
    content=(
      #|[
      #|  "1:sample.mbt:1:1-1:31:\"prefix \\{ foo ( 1 ) } suffix\"",
      #|  "2:sample.mbt:1:32-1:51:\"\\{ \"\\{ x + 1 }\" }\"",
      #|  "3:sample.mbt:1:52-1:65:b\"\\{ x + 1 }\"",
      #|  "4:sample.mbt:1:66-1:80:re\"\\{ x + 1 }\"",
      #|]
    ),
  )
  debug_inspect(
    tokscan_test_hits("$|value \\{ x + 1 }\n", ["$|value \\{x+1}\n"]),
    content=(
      #|["1:sample.mbt:1:1-1:19:$|value \\{ x + 1 }"]
    ),
  )
}

///|
test "tokscan recursively compares attributes and allows empty payloads" {
  let source =
    #|#tag( a , "\{ x + 1 }" )
    #|#outer #inner( a + b )
    #|#moongrep.skip
    #|#tag
    #|#tag()
  debug_inspect(
    tokscan_test_hits(source, [
      (
        #|#tag(a,"\{x+1}")
      ),
      "#outer #inner(a+b)",
      "#moongrep.skip",
      "#tag ",
      "#tag()",
      "x+1",
      "#other.skip",
    ]),
    content=(
      #|[
      #|  "1:sample.mbt:1:1-1:25:#tag( a , \"\\{ x + 1 }\" )",
      #|  "2:sample.mbt:2:1-2:23:#outer #inner( a + b )",
      #|  "3:sample.mbt:3:1-3:15:#moongrep.skip",
      #|  "4:sample.mbt:4:1-4:5:#tag",
      #|  "5:sample.mbt:5:1-5:7:#tag()",
      #|]
    ),
  )
}

///|
test "tokscan accepts lexically valid incomplete syntax" {
  debug_inspect(
    tokscan_test_hits("let = + )", ["= + )"]),
    content=(
      #|["1:sample.mbt:1:5-1:10:= + )"]
    ),
  )
  debug_inspect(
    tokscan_test_hits("#tag(\n\"\\{a +}\"", ["#tag(", "\"\\{ a + }\""]),
    content=(
      #|["1:sample.mbt:1:1-1:6:#tag(", "2:sample.mbt:2:1-2:9:\"\\{a +}\""]
    ),
  )
}

///|
test "tokscan positions include dot prefixes and count Unicode characters" {
  debug_inspect(
    tokscan_test_hits("\"😀\".field .Case .01 .(x)\n  \"中文😀\".field", [
      ".field", ".Case", ".1", ".(x)", "\"中文😀\".field",
    ]),
    content=(
      #|[
      #|  "1:sample.mbt:1:4-1:10:.field",
      #|  "2:sample.mbt:1:11-1:16:.Case",
      #|  "3:sample.mbt:1:17-1:20:.01",
      #|  "4:sample.mbt:1:21-1:25:.(x)",
      #|  "5:sample.mbt:2:3-2:14:\"中文😀\".field",
      #|  "1:sample.mbt:2:8-2:14:.field",
      #|]
    ),
  )
}

///|
test "tokscan KMP agrees with exhaustive binary word occurrences" {
  for source_length in 0..<=7 {
    for source_bits in 0..<(1 << source_length) {
      let words = Array::makei(source_length, i => {
        if (source_bits & (1 << i)) == 0 {
          "a"
        } else {
          "b"
        }
      })
      let source = words.join(" ")
      for pattern_length in 1..<=4 {
        for pattern_bits in 0..<(1 << pattern_length) {
          let pattern = Array::makei(pattern_length, i => {
            if (pattern_bits & (1 << i)) == 0 {
              "a"
            } else {
              "b"
            }
          })
          let expected : Array[Int] = []
          for start in 0..<(source_length - pattern_length + 1) {
            if words[start:start + pattern_length].to_owned() == pattern {
              expected.push(start * 2)
            }
          }
          let actual = @tokmatch.Matcher::compile([pattern.join(" ")])
            .find_matches(source)
            .map(hit => hit.loc.start.cnum)
          assert_eq(actual, expected)
        }
      }
    }
  }
}
