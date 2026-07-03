///|
fn backward_array_loop(items : Array[Int]) -> Unit {
  for i = items.length() - 1; i >= 0; i = i - 1 {
    consume_reverse(items[i])
  }
}
