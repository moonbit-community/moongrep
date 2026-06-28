///|
fn has_builtin_hits(value : Int?) -> Unit {
  inspect(1, content="1")
  assert_true(
    match value {
      Some(inner) => inner > 0
      None => false
    },
  )
}

