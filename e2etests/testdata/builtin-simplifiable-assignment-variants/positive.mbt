///|
struct AssignmentTarget {
  mut add_left : Int
  mut subtract : Int
  mut multiply_left : Int
  mut divide : Int
}

///|
fn supported_local_assignments(step : Int) -> Unit {
  let mut add_left = 0
  add_left = add_left + step * 2
  let mut subtract = 0
  subtract = subtract - step
  let mut multiply_left = 1
  multiply_left = multiply_left * (step + 1)
  let mut divide = 1
  divide = divide / step
}

///|
fn supported_field_assignments(
  target : AssignmentTarget,
  step : Int,
) -> Unit {
  target.add_left = target.add_left + step * 2
  target.subtract = target.subtract - step
  target.multiply_left = target.multiply_left * (step + 1)
  target.divide = target.divide / step
}

///|
fn supported_index_assignments(target : Array[Int], step : Int) -> Unit {
  target[0] = target[0] + step * 2
  target[1] = target[1] - step
  target[2] = target[2] * (step + 1)
  target[3] = target[3] / step
}

///|
struct StringAssignmentTarget {
  mut text : String
}

///|
fn supported_string_assignments(
  target : StringAssignmentTarget,
  values : Array[String],
) -> Unit {
  let mut text = "hello"
  text = text + " world"
  target.text = target.text + " world"
  values[0] = values[0] + " world"
}
