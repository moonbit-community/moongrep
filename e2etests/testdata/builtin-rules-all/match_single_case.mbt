///|
fn single_case_match(value : Int?) -> Unit {
  match value {
    Some(inner) => consume(inner)
    _ => ()
  }
}
