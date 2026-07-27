///|
async fn no_parameters {
  try risky() catch { _ => () }
}
///|
async fn varied_parameters(_, value : Int, fallback? : Int = 0) -> Int {
  try risky() catch { error => value }
}
///|
pub async fn public_noraise(value : Int) noraise {
  try risky() catch { error => () }
}
///|
/// Qualified generic function.
#custom.attribute
priv async fn[T] Box::qualified(value : T) -> T {
  try risky() catch { error => value }
}
///|
fn synchronous_function(value : Int) -> Int {
  try risky() catch { _ => value }
}
