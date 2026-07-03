///|
fn option_match(value : Int?) -> Bool {
  match value {
    Some(inner) => inner > 0
    None => false
  }
}
