///|
fn cst_guards_match(
  guards : Array[CompiledRuleGuard],
  bindings : @hashmap.HashMap[String, @bound_value_model.BoundValue],
) -> Bool {
  for guard_entry in guards {
    match guard_entry.capture_kind {
      IdentifierGuard =>
        match bindings.get(guard_entry.name) {
          Some(Single(value)) => {
            guard @cst.normalized_name(value) is Some(text) else {
              return false
            }
            if guard_entry.regex.execute(text) is None {
              return false
            }
          }
          _ => return false
        }
      ConstantGuard =>
        match bindings.get(guard_entry.name) {
          Some(Single(value)) => {
            guard constant_guard_value(value) is Some(text) else {
              return false
            }
            if guard_entry.regex.execute(text) is None {
              return false
            }
          }
          _ => return false
        }
    }
  }
  true
}

///|
fn constant_guard_value(constant : @untyped_cst.CstNode) -> String? {
  if @cst.string_payload(constant) is Some(value) {
    Some(value)
  } else if @cst.bool_payload(constant) is Some(value) {
    Some(value.to_string())
  } else {
    None
  }
}
