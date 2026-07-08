///|
fn compile_toplevel_shape_for_test(source : String) -> MetavarShape raise {
  compile_toplevel_metavar_shape(
    "/tmp/rules/example.yaml", "inside-toplevel", source,
  )
}

///|
test "top-level type declarations record type metavars" {
  let type_alias = compile_toplevel_shape_for_test("pub type Alias = $(T:type)")
  debug_inspect(type_alias.type_metavars, content="[\"T\"]")
  let record_source =
    #|struct Box {
    #|  value : $(T:type)
    #|}
    #|
  let record = compile_toplevel_shape_for_test(record_source)
  debug_inspect(record.type_metavars, content="[\"T\"]")
  let variant_source =
    #|enum Choice {
    #|  Some($(T:type))
    #|}
    #|
  let variant = compile_toplevel_shape_for_test(variant_source)
  debug_inspect(variant.type_metavars, content="[\"T\"]")
}

///|
test "top-level trait declarations record method type metavars" {
  let trait_source =
    #|trait Reader {
    #|  read(Self) -> $(T:type)
    #|}
    #|
  let trait_shape = compile_toplevel_shape_for_test(trait_source)
  debug_inspect(trait_shape.type_metavars, content="[\"T\"]")
}
