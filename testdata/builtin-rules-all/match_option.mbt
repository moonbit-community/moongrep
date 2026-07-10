///|
fn option_match(value : Int?) -> Bool {
  match value {
    Some(inner) => {
      let prepared = prepare(inner)
      let validated = validate(prepared)
      let normalized = normalize(validated)
      finish(normalized)
    }
    None => false
  }
}
