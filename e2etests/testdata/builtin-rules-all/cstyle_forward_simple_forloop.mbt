///|
fn forward_simple_loop(limit : Int) -> Unit {
  for i = 0; i < limit; i = i + 1 {
    tick()
  }
}
