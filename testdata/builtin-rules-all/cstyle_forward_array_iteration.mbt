///|
fn forward_array_loop(items : Array[Int]) -> Unit {
  for i = 0; i < items.length(); i = i + 1 {
    consume(items[i])
  }
}
