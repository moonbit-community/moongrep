///|
struct Span {
  start : Int
  end : Int
} derive(Eq, Hash, Debug)

///|
struct SexpParser {
  input : String
  mut index : Int
}

///|
fn span(start : Int, end : Int) -> Span {
  Span::{ start, end }
}

///|
fn is_whitespace(byte : UInt16) -> Bool {
  byte == 32 || byte == 9 || byte == 10 || byte == 13
}

///|
fn is_atom_byte(byte : UInt16) -> Bool {
  byte != 40 && byte != 41 && !is_whitespace(byte)
}

///|
fn SexpParser::skip_whitespace(self : SexpParser) -> Unit {
  while self.index < self.input.length() &&
        is_whitespace(self.input[self.index]) {
    self.index += 1
  }
}

///|
fn SexpParser::parse_atom_text(self : SexpParser) -> String {
  let start = self.index
  while self.index < self.input.length() && is_atom_byte(self.input[self.index]) {
    self.index += 1
  }
  if start == self.index {
    abort("expected atom")
  }
  self.input.unsafe_substring(start~, end=self.index)
}

///|
fn SexpParser::parse_tree(self : SexpParser) -> @ac.LabelledTree[Span] {
  self.skip_whitespace()
  if self.index == self.input.length() {
    abort("expected tree")
  }
  if self.input[self.index] == 40 {
    self.parse_list()
  } else {
    self.parse_atom_or_metavar()
  }
}

///|
fn SexpParser::parse_atom_or_metavar(
  self : SexpParser,
) -> @ac.LabelledTree[Span] {
  let start = self.index
  let text = self.parse_atom_text()
  if text.has_prefix("$") {
    if text.length() == 1 {
      abort("expected metavar name")
    }
    @ac.LabelledTree::metavar(text.unsafe_substring(start=1, end=text.length()))
  } else {
    @ac.LabelledTree::node(span(start, self.index), text, [])
  }
}

///|
fn SexpParser::parse_list(self : SexpParser) -> @ac.LabelledTree[Span] {
  let start = self.index
  self.index += 1
  self.skip_whitespace()
  let label = self.parse_atom_text()
  if label.has_prefix("$") {
    abort("list label cannot be a metavar")
  }
  let children : Array[@ac.LabelledTree[Span]] = []
  self.skip_whitespace()
  while self.index < self.input.length() && self.input[self.index] != 41 {
    children.push(self.parse_tree())
    self.skip_whitespace()
  }
  if self.index == self.input.length() {
    abort("expected ')'")
  }
  self.index += 1
  @ac.LabelledTree::node(span(start, self.index), label, children)
}

///|
fn parse_sexp(input : String) -> @ac.LabelledTree[Span] {
  let parser = SexpParser::{ input, index: 0 }
  let tree = parser.parse_tree()
  parser.skip_whitespace()
  if parser.index != input.length() {
    abort("unexpected trailing input")
  }
  tree
}

///|
fn text_at(input : String, loc : Span) -> String {
  input.unsafe_substring(start=loc.start, end=loc.end)
}

///|
fn texts_at(input : String, locs : Array[Span]) -> String {
  locs.map(loc => text_at(input, loc)).join(", ")
}

///|
test "blackbox sexp parser feeds grep api with locations" {
  let subject_input = "(root (call f (arg x)) (call g (arg (pair y z))))"
  let subject = parse_sexp(subject_input)
  let pattern = @ac.build_pattern_from_labelled_tree(
    parse_sexp("(call $callee (arg $value))"),
  )
  let matches = @ac.MbtAstGrepEnv::new().grep(pattern, subject)
  let first = span(6, 22)
  let second = span(23, 48)
  assert_eq(matches.length(), 2)
  debug_inspect(
    [
      ("first.match", text_at(subject_input, first)),
      ("first.callee", texts_at(subject_input, matches[first]["callee"])),
      ("first.value", texts_at(subject_input, matches[first]["value"])),
      ("second.match", text_at(subject_input, second)),
      ("second.callee", texts_at(subject_input, matches[second]["callee"])),
      ("second.value", texts_at(subject_input, matches[second]["value"])),
    ],
    content=(
      #|[
      #|  ("first.match", "(call f (arg x))"),
      #|  ("first.callee", "f"),
      #|  ("first.value", "x"),
      #|  ("second.match", "(call g (arg (pair y z)))"),
      #|  ("second.callee", "g"),
      #|  ("second.value", "(pair y z)"),
      #|]
    ),
  )
}
