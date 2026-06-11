///|
test "taint package exposes public path and site models" {
  let path : StoragePath = { root: "input", segments: [Field("body")] }
  let site = ValueSite::Path(path)
  match site {
    Path(found) => inspect(found.root, content="input")
    _ => fail("expected path site")
  }
}
