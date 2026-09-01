fn sample {
  let mut x0 = get_user_input()
  let mut x1 = ()
  let mut x2 = ()
  let mut x3 = ()
  let mut x4 = ()
  let mut x5 = ()
  let mut x6 = ()
  let mut x7 = ()
  while clean() {
    x7 = x6
    x6 = x5
    x5 = x4
    x4 = x3
    x3 = x2
    x2 = x1
    x1 = x0
  }
  sink(x7)
}
