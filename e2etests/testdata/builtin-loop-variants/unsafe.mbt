///|
fn backward_array_mutation(items : Array[Int]) -> Array[Int] {
  let output = []
  for i = items.length() - 1; i >= 0; i = i - 1 {
    output.push(items[i])
    items.push(0)
    items[0] = 10
  }
  output
}

///|
fn shrinking_upper_bound() -> Int {
  let mut limit = 3
  let mut count = 0
  for i = 0; i < limit; i = i + 1 {
    count += 1
    limit -= 1
  }
  count
}

///|
fn growing_lower_bound() -> Int {
  let mut lower = 0
  let mut count = 0
  for i = 3; i > lower; i = i - 1 {
    lower += 1
    count += 1
  }
  count
}

///|
fn effectful_bound(limit : () -> Int) -> Unit {
  for i = 0; i < limit(); i = i + 1 {
    ()
  }
  for i = 3; i > limit(); i = i - 1 {
    ()
  }
}

///|
fn growing_queue_without_index() -> Int {
  let queue = [0]
  let mut count = 0
  for i = 0; i < queue.length(); i = i + 1 {
    count += 1
    if count < 3 {
      queue.push(count)
    }
  }
  count
}

///|
fn custom_counter_updates(items : Array[Int]) -> Unit {
  for i = 0; i < 2; i = i + 1 {
    continue 2
  }
  for i = 2; i > 0; i = i - 1 {
    continue 0
  }
  for i = 0; i < items.length(); i = i + 1 {
    ignore(items[i])
    continue 2
  }
  for i = items.length() - 1; i >= 0; i = i - 1 {
    ignore(items[i])
    continue -1
  }
}
