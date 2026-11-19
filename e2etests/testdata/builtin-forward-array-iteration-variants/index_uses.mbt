///|
fn copy_items(items : Array[Int]) -> Array[Int] {
  let output = []
  for i = 0; i < items.length(); i = i + 1 {
    output.push(items[i])
  }
  output
}

///|
fn collect_indexed_items(items : Array[Int]) -> Array[(Int, Int)] {
  let output = []
  for i = 0; i < items.length(); i = i + 1 {
    output.push((i, items[i]))
  }
  output
}
