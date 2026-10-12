fn inside {
  wrapper(target())
  wrapper(a, b, target(a, b))
  wrapper(a, b, target(a, other))
}
