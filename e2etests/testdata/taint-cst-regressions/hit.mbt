fn foreach_case {
  for item in get_user_inputs() {
    sink(item)
  }
}

///|
fn try_case {
  try get_user_input() catch {
    _ => ()
  } noraise {
    result => sink(result)
  }
}

///|
fn array_get_case {
  let values = [get_user_input()]
  sink(values[0])
}

///|
fn array_set_case {
  values[0] = sink(get_user_input())
}

///|
fn else_case {
  if clean() {
    ()
  } else {
    sink(get_user_input())
  }
}

///|
fn labelled_block_case {
  labelled~: {
    let value = get_user_input()
    sink(value)
  }
}
