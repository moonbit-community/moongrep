///|
fn catches_everything() -> Unit {
  try risky() catch {
    _ => recover()
  }
}
