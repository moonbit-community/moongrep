///|
async fn catches_everything(_) -> Unit {
  try risky() catch {
    _ => recover()
  }
}
