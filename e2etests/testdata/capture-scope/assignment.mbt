///|
fn assign_shadowed {
  let mut item = 0
  wrapper(item, { let mut item = 0; item = 1 })
}
///|
fn assign_visible {
  let mut item = 0
  wrapper(item, { let mut other = 0; item = 1 })
}
///|
fn augmented_shadowed {
  let mut item = 0
  wrapper(item, { let mut item = 0; item += 1 })
}
///|
fn augmented_visible {
  let mut item = 0
  wrapper(item, { let mut other = 0; item += 1 })
}
