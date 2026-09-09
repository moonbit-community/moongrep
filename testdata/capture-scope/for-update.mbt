fn shadowed {
  for i = 0; i < 10; i = i + 1 {
    let i = source()
    sink(i)
  }
}
///|
fn visible {
  for i = 0; i < 10; i = i + 1 {
    let other = source()
    sink(i)
  }
}
