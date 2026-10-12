///|
struct AssignmentTarget {
  mut add_left : Int
  mut add_right : Int
  mut subtract : Int
  mut multiply_left : Int
  mut multiply_right : Int
  mut divide : Int
}

///|
fn supported_local_assignments(step : Int) -> Unit {
  let mut add_left = 0
  add_left = add_left + step * 2
  let mut add_right = 0
  add_right = step * 2 + add_right
  let mut subtract = 0
  subtract = subtract - step
  let mut multiply_left = 1
  multiply_left = multiply_left * (step + 1)
  let mut multiply_right = 1
  multiply_right = (step + 1) * multiply_right
  let mut divide = 1
  divide = divide / step
}

///|
fn supported_field_assignments(
  target : AssignmentTarget,
  step : Int,
) -> Unit {
  target.add_left = target.add_left + step * 2
  target.add_right = step * 2 + target.add_right
  target.subtract = target.subtract - step
  target.multiply_left = target.multiply_left * (step + 1)
  target.multiply_right = (step + 1) * target.multiply_right
  target.divide = target.divide / step
}

///|
fn supported_index_assignments(target : Array[Int], step : Int) -> Unit {
  target[0] = target[0] + step * 2
  target[1] = step * 2 + target[1]
  target[2] = target[2] - step
  target[3] = target[3] * (step + 1)
  target[4] = (step + 1) * target[4]
  target[5] = target[5] / step
}
