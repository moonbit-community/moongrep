fn unsupported {
  sink(source());
  let values = [for x in xs => x];
  sink(values)
}

///|
fn supported {
  sink(source())
}
