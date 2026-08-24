fn named_suffix {
  wrapper({
    let item = source()
    consume(item)
    finish(item)
  })
}

fn ignore_empty {
  wrapper({ let value = load() })
}

fn ignore_one {
  wrapper({
    let value = load()
    use(value)
  })
}

fn ignore_many {
  wrapper({
    let value = load()
    use(value)
    finish(value)
  })
}
