///|
priv struct TokPattern {
  keys : ReadOnlyArray[TokKey]
  fallback : FixedArray[Int]
}

///|
/// A match location and its zero-based index in the input patterns.
pub struct Match {
  pattern_index : Int
  loc : @basic.Location
}

///|
/// Compiled token patterns with a KMP table for each pattern.
pub struct Matcher {
  priv patterns : ReadOnlyArray[TokPattern]
}

///|
/// The first invalid pattern, identified by its zero-based input index.
pub(all) suberror PatternError {
  PatternError(index~ : Int, reason~ : String)
}

///|
/// Compiles patterns in input order. Each pattern must lex successfully and
/// contain at least one normalized token. An empty pattern list matches nothing.
pub fn Matcher::compile(
  sources : ArrayView[String],
) -> Matcher raise PatternError {
  let patterns = ReadOnlyArray::makei(sources.length(), index => {
    let tokens = lex_tokscan_tokens(sources[index], pattern=true) catch {
      LexError(reason) => raise PatternError(index~, reason~)
    }
    if tokens.is_empty() {
      raise PatternError(index~, reason="pattern contains no tokens")
    }
    let keys = ReadOnlyArray::makei(tokens.length(), i => tokens[i].key)
    let fallback = FixedArray::make(keys.length(), 0)
    let mut prefix = 0
    for i in 1..<keys.length() {
      while prefix > 0 && keys[i] != keys[prefix] {
        prefix = fallback[prefix - 1]
      }
      if keys[i] == keys[prefix] {
        prefix += 1
      }
      fallback[i] = prefix
    }
    { keys, fallback, }
  })
  { patterns, }
}

///|
/// Lexes and normalizes one source block once, then searches every pattern.
/// Returns all occurrences, including overlaps and duplicates, ordered by start
/// position and then pattern index. Source positions count Unicode characters.
/// Callers split files at `///|` and pass each block separately.
pub fn Matcher::find_matches(
  self : Matcher,
  source : StringView,
  name? : String = "",
) -> Array[Match] raise LexError {
  find_tokscan_matches(lex_tokscan_tokens(source, name~), self.patterns)
}

///|
fn find_tokscan_matches(
  tokens : Array[TokToken],
  patterns : ReadOnlyArray[TokPattern],
) -> Array[Match] {
  let hits : Array[Match] = []
  for pattern_index, pattern in patterns {
    let mut prefix = 0
    for index, token in tokens {
      while prefix > 0 && token.key != pattern.keys[prefix] {
        prefix = pattern.fallback[prefix - 1]
      }
      if token.key == pattern.keys[prefix] {
        prefix += 1
      }
      if prefix == pattern.keys.length() {
        hits.push({
          pattern_index,
          loc: {
            start: tokens[index + 1 - prefix].loc.start,
            end: token.loc.end,
          },
        })
        // Keep the longest shared prefix so overlapping matches survive.
        prefix = pattern.fallback[prefix - 1]
      }
    }
  }
  hits.sort_by_key(hit => (hit.loc.start.cnum, hit.pattern_index))
  hits
}
