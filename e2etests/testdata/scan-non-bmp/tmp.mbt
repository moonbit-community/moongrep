///|
test "stringview basic" {
  let str = "Hello🤣🤣🤣"
  let start_offset = 1
  let end_offset = str.offset_of_nth_char(6).unwrap()
  inspect(str.view(start_offset~), content="ello🤣🤣🤣")
}
