///|
priv struct PatternCompileContext {
  path : String
  location : String
  shape : String
}

///|
fn pattern_compile_context(
  path : String,
  location : String,
  shape : String,
) -> PatternCompileContext {
  { path, location, shape, }
}

///|
fn PatternCompileContext::invalid_pattern(
  self : PatternCompileContext,
  info : String,
) -> RuleLoadError {
  let info = if self.location.contains(".then.") {
    "\{self.location}: \{info}"
  } else {
    info
  }
  RuleLoadError::InvalidPattern(path=self.path, shape=self.shape, info~)
}
