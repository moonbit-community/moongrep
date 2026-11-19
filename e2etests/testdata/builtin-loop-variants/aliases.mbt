///|
fn forward_alias() -> Array[Int] {
  let items = [0]
  let alias_items = items
  let output = []
  for i = 0; i < items.length(); i = i + 1 {
    let item = items[i]
    output.push(item)
    if item < 2 {
      alias_items.push(item + 1)
    }
  }
  output
}

///|
fn backward_alias() -> Array[Int] {
  let items = [1, 2, 3]
  let alias_items = items
  let output = []
  for i = items.length() - 1; i >= 0; i = i - 1 {
    let item = items[i]
    output.push(item)
    if item == 3 {
      alias_items.push(4)
      alias_items[0] = 10
    }
  }
  output
}
