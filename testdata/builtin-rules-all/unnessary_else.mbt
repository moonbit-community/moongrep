///|
fn unnecessary_empty_else(flag : Bool) -> Unit {
  if flag {
    prepare()
    finish()
  } else {}
}
///|
fn non_unit_else(flag : Bool) -> Unit {
  ignore(if flag { first() } else { second() })
}
