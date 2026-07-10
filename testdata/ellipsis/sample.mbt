fn sample {
  inspect()
  inspect(1)
  inspect(1, content="1")

  anchored(prefix, suffix)
  anchored(prefix, first, second, suffix)
  anchored(other, first, second, suffix)
  anchored(prefix, first, second, other)
}
