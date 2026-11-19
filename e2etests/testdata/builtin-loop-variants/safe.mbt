///|
fn fixed_upper_bound(skip : Bool) -> Int {
  let mut count = 0
  for i = 0; i < 0x10; i = i + 1 {
    if skip {
      continue
    }
    count += 1
  }
  count
}

///|
fn fixed_lower_bound(start : Int) -> Int {
  let mut count = 0
  for i = start; i > -1_000; i = i - 1 {
    count += 1
  }
  count
}

///|
fn copy_backwards(items : Array[Int]) -> Array[Int] {
  let output = []
  for i = items.length() - 1; i >= 0; i = i - 1 {
    output.push(items[i])
  }
  output
}
