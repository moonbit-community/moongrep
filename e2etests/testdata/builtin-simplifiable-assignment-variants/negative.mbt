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
  target = step * 2 + target
  target = other - step
  target = step - target
  target = other * step
  target = step * other
  target = (step + 1) * target
  target = other / step
  target = step / target

  first.left = first.right + step
  first.left = step + first.right
  first.left = step * 2 + first.left
  first.left = first.right - step
  first.left = step - first.left
  first.left = first.right * step
  first.left = step * first.right
  first.left = (step + 1) * first.left
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
  values[0] = step * 2 + values[0]
  values[0] = values[1] - step
  values[0] = step - values[0]
  values[0] = values[1] * step
  values[0] = step * values[1]
  values[0] = (step + 1) * values[0]
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

///|
struct TextAssignmentTarget {
  mut text : String
}

///|
fn unsupported_string_assignments(
  target : TextAssignmentTarget,
  values : Array[String],
) -> Unit {
  let mut text = "world"
  text = "hello " + text
  target.text = "hello " + target.text
  values[0] = "hello " + values[0]
}

///|
struct AssignmentWord {
  value : String
}

///|
impl Mul for AssignmentWord with fn mul(self, other) {
  { value: self.value + other.value }
}

///|
struct WordAssignmentTarget {
  mut word : AssignmentWord
}

///|
fn unsupported_word_assignments(
  target : WordAssignmentTarget,
  values : Array[AssignmentWord],
) -> Unit {
  let prefix : AssignmentWord = { value: "left" }
  let mut word : AssignmentWord = { value: "right" }
  word = prefix * word
  target.word = prefix * target.word
  values[0] = prefix * values[0]
}

///|
fn unsupported_effectful_assignment {
  let mut value = 10
  let other = fn() {
    value = 20
    1
  }
  value = other() + value
}
