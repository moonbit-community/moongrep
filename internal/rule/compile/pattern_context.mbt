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
  RuleLoadError::InvalidPattern(path=self.path, shape=self.shape, info~)
}
