async fn nested {
  let outer = fn() {
    if ready() {
      let inner = fn() {
        target()
        try risky() catch { _ => () }
      }
      inner()
    }
  }
  outer()
}
///|
async fn separate {
  target()
  target()
  try risky() catch { _ => () }
}
