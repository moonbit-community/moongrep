fn bindings {
  split(a, marker, b, marker)
  split(a, marker, b, marker, trailing)

  repeated([], [])
  repeated([a, b], [a, b])
  repeated([a], [b])
  repeated([a, b], [a])

  arguments_equal(left(1, label=2), right(1, label=2))
  arguments_equal(left(1, label=2), right(1, other=2))

  anonymous([a], [b, c])
  typed_anonymous([1, 2], [a, b])
  typed_anonymous([1, value], [a, b])

  propagated([1, 2], [1, 2])
  propagated([a, b], [a, b])

  restore(first, selected, marker, selected)
  restore(first, selected, marker, other)
}
