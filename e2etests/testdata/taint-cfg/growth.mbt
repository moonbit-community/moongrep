fn growing(flag) {
  let mut value = { secret: source() };
  sink(value);
  while flag { value = { next: value } };
  sink(value)
}

///|
fn supported {
  sink(source())
}
