///|
test "metavar registry preserves mixed declaration order" {
  let registry = MetavarRegistry::new()
  assert_true(registry.register("name", Identifier) == Registered)
  assert_true(registry.register("value", Expr) == Registered)
  assert_true(registry.register("items", Ellipsis(ConstItem)) == Registered)
  assert_true(registry.register("T", Type) == Registered)
  debug_inspect(
    [
      for entry in registry.entries => entry.name
    ],
    content="[\"name\", \"value\", \"items\", \"T\"]",
  )
  debug_inspect(registry.names(Identifier), content="[\"name\"]")
  debug_inspect(registry.names(Expr), content="[\"value\"]")
  debug_inspect(registry.names(Ellipsis(ConstItem)), content="[\"items\"]")
}

///|
test "metavar registry centralizes duplicate and conflict checks" {
  let registry = MetavarRegistry::new()
  assert_true(registry.register("value", Expr) == Registered)
  assert_true(registry.register("value", Expr) == AlreadyRegistered)
  assert_true(
    registry.register("value", Identifier) == RegistrationConflict(Expr),
  )
  assert_true(
    registry.register("value", Ellipsis(ExpItem)) == RegistrationConflict(Expr),
  )
  assert_eq(registry.entries.length(), 1)
  assert_true(registry.kind_of("value") == Some(Expr))
}

///|
test "shared metavar syntax parses bare typed qualified and wildcard forms" {
  assert_true(parse_metavar_syntax("$value") == Bare("value"))
  assert_true(
    parse_metavar_syntax("$(value:const)") == Typed("value", Constant),
  )
  assert_true(
    parse_metavar_syntax("@pkg.$(callee:id)") == Typed("callee", Identifier),
  )
  assert_true(parse_metavar_syntax("$_") == Wildcard)
  assert_true(parse_metavar_syntax("ordinary") == NotMetavar)
  assert_true(
    parse_metavar_syntax("$(value:unknown)") ==
    UnsupportedMetavarKind("unknown"),
  )
}

///|
test "shared metavar syntax preserves ellipsis constraints" {
  assert_true(parse_metavar_syntax("$$$items") == EllipsisSyntax("items", None))
  assert_true(
    parse_metavar_syntax("$$$(items:arg)") ==
    EllipsisSyntax("items", Some(ArgItem)),
  )
  assert_true(
    parse_metavar_syntax("@pkg.$$$(items:type)") ==
    EllipsisSyntax("items", Some(TypeItem)),
  )
}

///|
test "registry resolves named wildcard ellipsis and special placeholders" {
  let registry = MetavarRegistry::new()
  ignore(registry.register("value", Expr))
  ignore(registry.register("items", Ellipsis(IdItem)))
  registry.register_special_expr_placeholder("__TARGET__")
  registry.register_special_expr_placeholder("__SOURCE__")
  assert_true(registry.is_placeholder("$value"))
  assert_true(registry.is_placeholder("value"))
  assert_true(registry.is_wildcard("$_"))
  assert_true(registry.is_wildcard("$$$_"))
  match registry.resolve("@pkg.$value") {
    Some(ResolvedNamed(entry)) => {
      inspect(entry.name, content="value")
      assert_true(entry.kind == Expr)
    }
    _ => fail("expected qualified named metavar")
  }
  match registry.resolve("$$$items") {
    Some(ResolvedNamed(entry)) => assert_true(entry.kind == Ellipsis(IdItem))
    _ => fail("expected named ellipsis metavar")
  }
  match registry.resolve("$$$(_ : const)") {
    Some(ResolvedWildcard(Some(Ellipsis(kind)))) =>
      assert_true(kind == ConstItem)
    _ => fail("expected typed ellipsis wildcard")
  }
  assert_true(
    registry.resolve("__TARGET__") is Some(ResolvedSpecialExpr("__TARGET__")),
  )
  assert_true(
    registry.resolve("__SOURCE__") is Some(ResolvedSpecialExpr("__SOURCE__")),
  )
}
