fn ordered_lists {
  tuple_expr((first, second, tail))
  tuple_expr((first, other))

  if condition {
    before()
    middle()
    tail
  }

  array_expr([first, second])
  array_expr([first, ..rest])

  match tuple_input { (first, second, tail) => tuple_pattern }
  match constructor_input { Some(first, second) => constructor_pattern }
  match array_input { [first, _, 1] => array_pattern }
  match id_input { [first, second] => id_patterns }
  match id_input { [first, 1] => id_patterns }
  match const_input { [1, "two"] => const_patterns }
  match const_input { [1, value] => const_patterns }
}

fn type_list {
  let value : (Int, String, Bool) = input
}

fn parameter_lists {
  fn(
    positional,
    labelled~ : Int,
    optional~ : Int = 1,
    question? : String,
  ) { body }
  fn() { body }
}
