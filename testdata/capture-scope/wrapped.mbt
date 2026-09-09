///|
fn alias_visible(item : Int) {
  match input {
    Some(_) as item => middle({ let other = source(); sink(item) })
  }
}
///|
fn alias_shadowed(item : Int) {
  match input {
    Some(_) as item => middle({ let item = source(); sink(item) })
  }
}
///|
fn regex_visible(item : Int) {
  lexmatch input {
    (re"a" as item) => middle({ let other = source(); sink(item) })
  }
}
///|
fn regex_shadowed(item : Int) {
  lexmatch input {
    (re"a" as item) => middle({ let item = source(); sink(item) })
  }
}
///|
fn forall_visible(item : Int) {
  ∀ item : Int, middle({ let other = source(); sink(item) })
}
///|
fn forall_shadowed(item : Int) {
  ∀ item : Int, middle({ let item = source(); sink(item) })
}
///|
fn exists_visible(item : Int) {
  ∃ item : Int, middle({ let other = source(); sink(item) })
}
///|
fn exists_shadowed(item : Int) {
  ∃ item : Int, middle({ let item = source(); sink(item) })
}
