fn taint {
  let dirty = get_user_input()
  sink(prefix, marker, dirty)
  sink(prefix, one, two, marker, dirty, trailing)
  sink(prefix, marker, clean(prefix, around, dirty, trailing), trailing)
}
