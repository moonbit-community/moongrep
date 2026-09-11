///|
priv struct Capture {
  id : Int
  value : @bound_value_model.BoundValue
  identity : Int
  anchor : (String, @cst.BindingId?)?
}

///|
priv struct CaptureEnvironment {
  captures : Array[Capture]
}

///|
priv struct EnvironmentKey {
  values : Array[(Int, Int, (String, @cst.BindingId?)?)]
} derive(Eq, Hash)

///|
fn CaptureEnvironment::get(self : CaptureEnvironment, id : Int) -> Capture? {
  for capture in self.captures {
    if capture.id == id {
      return Some(capture)
    }
  }
  None
}

///|
fn ScanSession::intern_environment(
  self : ScanSession,
  captures : Array[Capture],
) -> Int {
  let key : EnvironmentKey = {
    values: captures.map(c => (c.id, c.identity, c.anchor)),
  }
  if self.environment_ids.get(key) is Some(id) {
    return id
  }
  let id = self.environments.length()
  self.environments.push({ captures, })
  self.environment_ids[key] = id
  id
}

///|
fn ScanSession::project_environment(
  self : ScanSession,
  env : Int,
  group : Int,
) -> Int {
  if self.projections.get((env, group)) is Some(id) {
    return id
  }
  let captures = self.plan.groups[group].needed.filter_map(id => {
    self.environments[env].get(id)
  })
  let result = self.intern_environment(captures)
  self.projections[(env, group)] = result
  result
}

///|
fn ScanSession::environment_blocks(
  self : ScanSession,
  pattern : CompiledRulePattern,
  region : @cst.RegionId,
  env : Int,
) -> Bool {
  if self.environments[env].captures.is_empty() {
    return false
  }
  let scope = self.index.scope(region)
  for capture in self.environments[env].captures {
    if capture.anchor is Some((name, binding)) &&
      self.index.resolve(scope, name) != binding {
      let capture_name = self.plan.capture_names[capture.id]
      if pattern.compiled.metavars.kind_of(capture_name) is Some(_) ||
        pattern.guards.any(guard_entry => guard_entry.name == capture_name) {
        return true
      }
    }
  }
  false
}

///|
fn ScanSession::match_pattern(
  self : ScanSession,
  pattern : CompiledRulePattern,
  region : @cst.RegionId,
  env : Int,
) -> @matching.IndexedExprMatch? {
  if self.environment_blocks(pattern, region, env) {
    return None
  }
  let bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue] = HashMap([],
  )
  for capture in self.environments[env].captures {
    bindings[self.plan.capture_names[capture.id]] = capture.value
  }
  match
    @matching.match_indexed_expr_pattern(
      pattern.compiled,
      self.index,
      region,
      bindings,
    ) {
    Some(matched) if cst_guards_match(pattern.guards, matched.result.bindings) =>
      Some(matched)
    _ => None
  }
}

///|
fn ScanSession::target_environment(
  self : ScanSession,
  pattern : CompiledRulePattern,
  matched : @matching.IndexedExprMatch,
  env : Int,
  child : Int,
) -> Int {
  let target = matched.target.unwrap()
  let inherited = self.environments[env]
  let captures : Array[Capture] = []
  for id in self.plan.groups[child].needed {
    if inherited.get(id) is Some(capture) {
      // Keep the ancestor's lexical identity, even through unused middle levels.
      captures.push(capture)
      continue
    }
    let name = self.plan.capture_names[id]
    if matched.result.bindings.get(name) is Some(value) {
      let anchor = if pattern.compiled.metavars.kind_of(name)
        is Some(Identifier) &&
        value is Single(node) &&
        @cst.normalized_name(node) is Some(text) {
        Some((text, self.index.resolve(target.scope, text)))
      } else {
        None
      }
      captures.push({ id, value, identity: self.values.intern(value), anchor, })
    }
  }
  self.intern_environment(captures)
}
