///|
struct AssignmentPair {
  mut left : Int
  mut right : Int
}

///|
fn unsupported_assignments(
  first : AssignmentPair,
  second : AssignmentPair,
  values : Array[Int],
  other_values : Array[Int],
  step : Int,
) -> Unit {
  let mut remainder = 1
  remainder = remainder % step

  let mut target = 0
  let other = 1
  target = other + step
  target = step + other
  target = other - step
  target = step - target
  target = other * step
  target = step * other
  target = other / step
  target = step / target

  first.left = first.right + step
  first.left = step + first.right
  first.left = first.right - step
  first.left = step - first.left
  first.left = first.right * step
  first.left = step * first.right
  first.left = first.right / step
  first.left = step / first.left

  first.left = second.left + step
  first.left = step + second.left
  first.left = second.left - step
  first.left = second.left * step
  first.left = step * second.left
  first.left = second.left / step

  values[0] = values[0] % step
  values[0] = values[1] + step
  values[0] = step + values[1]
  values[0] = values[1] - step
  values[0] = step - values[0]
  values[0] = values[1] * step
  values[0] = step * values[1]
  values[0] = values[1] / step
  values[0] = step / values[0]

  values[0] = other_values[0] + step
  values[0] = step + other_values[0]
  values[0] = other_values[0] - step
  values[0] = other_values[0] * step
  values[0] = step * other_values[0]
  values[0] = other_values[0] / step

  let mut add = 0
  add += step
  let mut subtract = 0
  subtract -= step
  let mut multiply = 1
  multiply *= step
  let mut divide = 1
  divide /= step

  values[0] += step
  values[0] -= step
  values[0] *= step
  values[0] /= step
}
