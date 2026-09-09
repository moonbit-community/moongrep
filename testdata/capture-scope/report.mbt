fn condition {
  let item = outer()
  if input is Some(item) {
    consume(item)
  } else {
    sink(item)
  }
}

fn sequence {
  wrapper(item, {
    let item = source()
    sink(item)
  })
}

fn field {
  wrapper(object.field, {
    let field = source()
    sink(object.field)
  })
}

fn list {
  wrapper(a, b, {
    let a = source()
    sink(a, b)
  })
}
