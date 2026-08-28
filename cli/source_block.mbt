///|
priv struct SourceBlock {
  source : StringView
  start_line : Int
  start_cnum : Int
}

///|
fn split_source_blocks(source : StringView) -> Array[SourceBlock] {
  let blocks : Array[SourceBlock] = []
  if source.length() == 0 {
    return blocks
  }
  let mut block_start = 0
  let mut block_start_line = 1
  let mut block_start_cnum = 0
  let mut line_start = 0
  let mut line_start_cnum = 0
  let mut line_number = 1
  for line in source.split("\n") {
    if line.has_prefix("///|") && line_start > block_start {
      blocks.push({
        source: source[block_start:line_start],
        start_line: block_start_line,
        start_cnum: block_start_cnum,
      })
      block_start = line_start
      block_start_line = line_number
      block_start_cnum = line_start_cnum
    }
    line_start += line.length()
    line_start_cnum += line.char_length()
    if line_start < source.length() && source[line_start] == '\n' {
      line_start += 1
      line_start_cnum += 1
    }
    line_number += 1
  }
  blocks.push({
    source: source[block_start:],
    start_line: block_start_line,
    start_cnum: block_start_cnum,
  })
  blocks
}

///|
fn parse_source_block(
  source : StringView,
  name : String,
) -> (Array[@untyped_cst.CstNode], Array[@basic.Report]) {
  let parsed = @untyped_cst.parse_structure(source.to_owned(), name~)
  let reports = parsed.diagnostics_view().to_owned()
  if reports.is_empty() &&
    @cst.first_recovery_node(parsed.root()) is Some(recovery) {
    reports.push({
      loc: recovery.loc,
      msg: "Unexpected end of file, missing simple expression here.",
    })
  }
  (@cst.toplevel_nodes(parsed.root()), reports)
}

///|
fn SourceBlock::rebase_position(
  self : SourceBlock,
  position : @basic.Position,
) -> @basic.Position {
  {
    fname: position.fname,
    lnum: position.lnum + self.start_line - 1,
    bol: position.bol + self.start_cnum,
    cnum: position.cnum + self.start_cnum,
  }
}

///|
fn SourceBlock::rebase_location(
  self : SourceBlock,
  location : @basic.Location,
) -> @basic.Location {
  {
    start: self.rebase_position(location.start),
    end: self.rebase_position(location.end),
  }
}

///|
fn SourceBlock::rebase_finding(
  self : SourceBlock,
  finding : @rule_model.RuleFinding,
) -> @rule_model.RuleFinding {
  { ..finding, loc: self.rebase_location(finding.loc), }
}
