///|
fn lexscan_before_shadowed {
  lexscan input {
    (re"a", before=item) => middle({ let item = source(); sink(item) })
  }
}
///|
fn lexscan_before_visible {
  lexscan input {
    (re"a", before=item) => middle({ let other = source(); sink(item) })
  }
}
///|
fn lexscan_after_shadowed {
  lexscan input {
    (re"a", after=item) => middle({ let item = source(); sink(item) })
  }
}
///|
fn lexscan_after_visible {
  lexscan input {
    (re"a", after=item) => middle({ let other = source(); sink(item) })
  }
}
///|
fn regex_before_shadowed {
  if input =~ (re"a", before=item) {
    middle({ let item = source(); sink(item) })
  }
}
///|
fn regex_before_visible {
  if input =~ (re"a", before=item) {
    middle({ let other = source(); sink(item) })
  }
}
///|
fn regex_after_shadowed {
  if input =~ (re"a", after=item) {
    middle({ let item = source(); sink(item) })
  }
}
///|
fn regex_after_visible {
  if input =~ (re"a", after=item) {
    middle({ let other = source(); sink(item) })
  }
}
