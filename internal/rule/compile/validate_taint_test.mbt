///|
test "validate taint source placeholder placement" {
  let source =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source(__SOURCE__)
    #|  sinks:
    #|    - shape: sink(__SOURCE__)
    #|
  expect_compile_invalid(source, "the pattern must not contain __SOURCE__")
}

///|
test "validate taint sink requires whole source target" {
  let source =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: sink(wrap(__SOURCE__))
    #|
  expect_compile_invalid(
    source, "the pattern must place __SOURCE__ as the whole receiver or argument value",
  )
}

///|
test "validate compiles taint source target metadata" {
  let source =
    #|id: example
    #|description: Example.
    #|taint:
    #|  sources:
    #|    - shape: source()
    #|  sinks:
    #|    - shape: receiver.sink(__SOURCE__)
    #|    - shape: __SOURCE__.dangerous()
    #|
  let rules = compile_one(source)
  match rules[0].definition {
    Taint(rule) => {
      assert_eq(rule.sinks.length(), 2)
      assert_true(rule.sinks[0].target is PositionalArg(0))
      assert_true(rule.sinks[1].target is Receiver)
    }
    Structural(_) => fail("expected taint rule")
  }
}
