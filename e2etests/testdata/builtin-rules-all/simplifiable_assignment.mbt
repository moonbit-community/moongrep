///|
fn simplifiable_assignment(step : Int) -> Int {
  let mut foo = 0
  foo = foo + step
  foo
}

///|
fn already_augmented(step : Int) -> Int {
  let mut foo = 0
  foo += step
  foo
}
