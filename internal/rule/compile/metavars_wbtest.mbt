///|
fn metavar_names(
  registry : @matching.MetavarRegistry,
  kind : @matching.MetavarKind,
) -> Array[String] {
  let names : Array[String] = []
  for entry in registry.entries {
    if entry.kind == kind {
      names.push(entry.name)
    }
  }
  names
}

///|
fn compile_toplevel_shape_for_test(source : String) -> MetavarShape raise {
  compile_toplevel_metavar_shape(
    pattern_compile_context(
      "/tmp/rules/example.yaml", "inside-toplevel[0]", source,
    ),
  )
}

///|
test "top-level type declarations record type metavars" {
  let type_alias = compile_toplevel_shape_for_test("pub type Alias = $(T:type)")
  debug_inspect(metavar_names(type_alias.metavars, Type), content="[\"T\"]")
  let record_source =
    #|struct Box {
    #|  value : $(T:type)
    #|}
    #|
  let record = compile_toplevel_shape_for_test(record_source)
  debug_inspect(metavar_names(record.metavars, Type), content="[\"T\"]")
  let variant_source =
    #|enum Choice {
    #|  Some($(T:type))
    #|}
    #|
  let variant = compile_toplevel_shape_for_test(variant_source)
  debug_inspect(metavar_names(variant.metavars, Type), content="[\"T\"]")
}

///|
test "top-level trait declarations record method type metavars" {
  let trait_source =
    #|trait Reader {
    #|  read(Self) -> $(T:type)
    #|}
    #|
  let trait_shape = compile_toplevel_shape_for_test(trait_source)
  debug_inspect(metavar_names(trait_shape.metavars, Type), content="[\"T\"]")
}

///|
test "top-level function parameters retain identifier priority" {
  let shape = compile_toplevel_shape_for_test(
    "fn $(function:id)($(param:id) : Int) { $(body:exp) }",
  )
  debug_inspect(
    metavar_names(shape.metavars, Identifier),
    content="[\"param\", \"function\"]",
  )
  debug_inspect(metavar_names(shape.metavars, Expr), content="[\"body\"]")
}
