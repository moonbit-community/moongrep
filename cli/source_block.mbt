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
fn attach_source_block_docstrings(
  docstrings : Array[@list.List[(@basic.Location, @tokens.Comment)]],
  toplevels : @list.List[@syntax.Impl],
) -> Unit {
  fn search_docstrings(
    last_pos : @basic.Position,
    loc : @basic.Location,
  ) -> @list.List[(@basic.Location, @tokens.Comment)]? {
    let mut result = None
    while docstrings.last() is Some(comments) &&
          comments.head().unwrap().0.start.lnum <= loc.start.lnum {
      let comments = docstrings.pop().unwrap()
      let line = comments.head().unwrap().0.start.lnum
      if last_pos.lnum < line && line <= loc.start.lnum {
        result = Some(comments)
      }
    }
    result
  }

  fn make_doc(
    comments : @list.List[(@basic.Location, @tokens.Comment)],
  ) -> @syntax.DocString {
    {
      content: comments.map(comment => {
        match comment.1.content {
          [.. "///|", .. remain] =>
            if remain.is_blank() {
              ""
            } else {
              remain.to_owned()
            }
          [.. "///", .. remain] => remain.to_owned()
          _ => panic()
        }
      }),
      loc: {
        start: comments.head().unwrap().0.start,
        end: comments.last().unwrap().0.end,
      },
    }
  }

  let mut last_pos = @basic.Position::{ fname: "", lnum: -1, bol: 0, cnum: 0 }
  for toplevel in toplevels {
    let loc = toplevel.loc()
    let doc = search_docstrings(last_pos, loc)
      .map(make_doc)
      .unwrap_or(@syntax.DocString::empty())
    match toplevel {
      TopTypeDef(type_decl) => {
        type_decl.doc = doc
        last_pos = loc.start
        match type_decl.components {
          Abstract | Alias(_) | Error(NoPayload) | TupleStruct(_) => ()
          Error(EnumPayload(constructors))
          | Variant(constructors)
          | ExtensibleEnum(constructors) =>
            constructors.each(ctor => {
              let previous = search_docstrings(last_pos, ctor.loc)
                .map(make_doc)
                .unwrap_or(@syntax.DocString::empty())
              ctor.doc = previous
              last_pos = ctor.loc.end
            })
          ExtendEnum(constructors~, ..) =>
            constructors.each(ctor => {
              let previous = search_docstrings(last_pos, ctor.loc)
                .map(make_doc)
                .unwrap_or(@syntax.DocString::empty())
              ctor.doc = previous
              last_pos = ctor.loc.end
            })
          Record(fields~) =>
            fields.each(field => {
              let previous = search_docstrings(last_pos, field.loc)
                .map(make_doc)
                .unwrap_or(@syntax.DocString::empty())
              field.doc = previous
              last_pos = field.loc.end
            })
        }
      }
      TopFuncDef(fun_decl~, ..) => fun_decl.doc = doc
      TopLetDef(..) as let_def => let_def.doc = doc
      TopExpr(..) => ()
      TopImplRelation(..) as impl_relation => impl_relation.doc = doc
      TopTest(..) as test_node => test_node.doc = doc
      TopTrait(trait_decl) => trait_decl.doc = doc
      TopView(..) as view => view.doc = doc
      TopImpl(..) as impl_node => impl_node.doc = doc
      TopUsing(..) as using_stmt => using_stmt.doc = doc
    }
    last_pos = loc.end
  }
}

///|
// `@parser.parse_string` requires an owned `String`. Keep block parsing
// zero-copy through lexing while preserving its docstring attachment behavior.
fn parse_source_block(
  source : StringView,
  name : String,
) -> (@list.List[@syntax.Impl], Array[@basic.Report]) {
  let { tokens, docstrings, .. } = @lexer.tokens_from_string(
    source,
    comment=true,
    name~,
  )
  let (impls, reports) = @handrolled_parser.parse(tokens)
  attach_source_block_docstrings(docstrings, impls)
  (impls, reports)
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
  { ..finding, loc: self.rebase_location(finding.loc) }
}
