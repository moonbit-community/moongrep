///|
/// Immutable value: default taint inherited by descendants, with explicit
/// overrides (including clean overrides). All projections use this domain.
pub struct TaintValue {
  priv defaults : Array[TaintOrigin]
  priv children : Array[(PathSegment, TaintValue)]
} derive(Debug)

///|
pub fn TaintValue::clean() -> TaintValue {
  { defaults: [], children: [], }
}

///|
pub fn TaintValue::source(origin : TaintOrigin) -> TaintValue {
  { defaults: [origin], children: [], }
}

///|
fn union_origins(
  a : Array[TaintOrigin],
  b : Array[TaintOrigin],
) -> Array[TaintOrigin] {
  let result = a.copy()
  for origin in b {
    if !result.contains(origin) {
      result.push(origin)
    }
  }
  result
}

///|
fn same_origins(a : Array[TaintOrigin], b : Array[TaintOrigin]) -> Bool {
  a.length() == b.length() && a.all(origin => b.contains(origin))
}

///|
pub impl Eq for TaintValue with fn equal(a, b) {
  same_origins(a.defaults, b.defaults) &&
  a.children.length() == b.children.length() &&
  a.children.all(pair => {
    b.children.any(other => pair.0 == other.0 && pair.1 == other.1)
  })
}

///|
fn TaintValue::inherited(self : TaintValue) -> TaintValue {
  { defaults: self.defaults, children: [], }
}

///|
fn TaintValue::child(self : TaintValue, segment : PathSegment) -> TaintValue {
  for pair in self.children {
    if pair.0 == segment {
      return pair.1
    }
  }
  match segment {
    ConstIndex(_) => self.child(AnyIndex)
    _ => self.inherited()
  }
}

///|
pub fn TaintValue::project(
  self : TaintValue,
  path : Array[PathSegment],
) -> TaintValue {
  let mut value = self
  for segment in path {
    value = match segment {
      AnyIndex => {
        let mut elements = value.child(AnyIndex)
        for (key, child) in value.children {
          if key is ConstIndex(_) {
            elements = elements.join(child)
          }
        }
        elements
      }
      _ => value.child(segment)
    }
  }
  value
}

///|
fn TaintValue::replace_child(
  self : TaintValue,
  key : PathSegment,
  value : TaintValue,
) -> TaintValue {
  let children = self.children.filter(pair => pair.0 != key)
  let fallback = match key {
    ConstIndex(_) => self.child(AnyIndex)
    _ => self.inherited()
  }
  if value != fallback {
    children.push((key, value))
  }
  { defaults: self.defaults, children, }
}

///|
pub fn TaintValue::write(
  self : TaintValue,
  path : Array[PathSegment],
  value : TaintValue,
) -> TaintValue {
  guard path is [key, .. rest] else { return value }
  let tail = rest.to_owned()
  match key {
    AnyIndex => {
      let summary = self.child(AnyIndex)
      let next_summary = summary.join(summary.write(tail, value))
      let mut next = self.replace_child(AnyIndex, next_summary)
      // Unknown writes may hit each existing constant override, including a
      // previously sanitized element. Preserve the unaffected possibility.
      for (key, child) in self.children {
        if key is ConstIndex(_) {
          next = next.replace_child(key, child.join(child.write(tail, value)))
        }
      }
      next
    }
    _ => self.replace_child(key, self.child(key).write(tail, value))
  }
}

///|
pub fn TaintValue::sanitize(
  self : TaintValue,
  path : Array[PathSegment],
) -> TaintValue {
  if path.contains(AnyIndex) {
    self
  } else {
    self.write(path, TaintValue::clean())
  }
}

///|
pub fn TaintValue::join(a : TaintValue, b : TaintValue) -> TaintValue {
  let defaults = union_origins(a.defaults, b.defaults)
  let keys : Array[PathSegment] = a.children.map(pair => pair.0)
  for (key, _) in b.children {
    if !keys.contains(key) {
      keys.push(key)
    }
  }
  // Install the element summary first so constant override normalization uses
  // the joined summary, never one input's override marker.
  let mut result : TaintValue = { defaults, children: [], }
  if keys.contains(AnyIndex) {
    result = result.replace_child(
      AnyIndex,
      a.child(AnyIndex).join(b.child(AnyIndex)),
    )
  }
  for key in keys {
    if key != AnyIndex {
      result = result.replace_child(key, a.child(key).join(b.child(key)))
    }
  }
  result
}

///|
pub fn TaintValue::origins(self : TaintValue) -> Array[TaintOrigin] {
  let mut origins = self.defaults.copy()
  for (_, child) in self.children {
    origins = union_origins(origins, child.origins())
  }
  origins
}

///|
/// Computations depend on all subvalues and return a scalar taint value.
pub fn TaintValue::collapse(self : TaintValue) -> TaintValue {
  { defaults: self.origins(), children: [], }
}

///|
pub fn TaintValue::is_clean(self : TaintValue) -> Bool {
  self.defaults.is_empty() && self.children.all(pair => pair.1.is_clean())
}

///|
pub extend TaintValue with Eq::{equal, not_equal}

///|
pub extend TaintValue with Debug::{to_repr}
