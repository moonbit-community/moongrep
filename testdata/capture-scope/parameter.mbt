fn shadowed(item : Int) {
  let item = source()
  sink(item)
}

fn visible(item : Int) {
  let other = source()
  sink(item)
}
