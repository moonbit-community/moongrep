///|
fn forward_simple_loop() -> Unit {
  for i = 0; i < 10; i = i + 1 {
    tick()
  }
}
