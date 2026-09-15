///|
test "then guards require compatible captures in every top-level alternative at depth" {
  let source =
    #|id: recursive
    #|description: Recursive.
    #|inside-toplevel:
    #|  - shape: fn $(name:id) { __TARGET__ }
    #|  - shape: test { __TARGET__ }
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
    #|          guard:
    #|            $name: '^safe_'
  expect_compile_invalid(
    source, "patterns[0].then.patterns[0] cannot use inherited ancestor metavar name as id because ancestor[1] does not declare it",
  )
}

///|
test "then diagnoses deep inherited conflicts and unknown sibling guards" {
  let source =
    #|id: recursive
    #|description: Recursive.
    #|patterns:
    #|  - shape: wrapper($(name:id), __TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: holder(__TARGET__)
    #|          then:
    #|            patterns-not:
    #|              - shape: target($(name:exp))
  expect_compile_invalid(
    source, "patterns[0].then.patterns[0].then.patterns-not[0] cannot use inherited ancestor[0] metavar name as exp because it was declared as id",
  )
  let sibling =
    #|id: recursive
    #|description: Recursive.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: first($(name:id))
    #|        - shape: target()
    #|          guard:
    #|            $name: '^safe_'
  expect_compile_invalid(
    sibling, "patterns[0].then.patterns[1].guard.$name references unknown metavar",
  )
}

///|
test "then target validation includes the complete nested path" {
  let source =
    #|id: recursive
    #|description: Recursive.
    #|patterns:
    #|  - shape: wrapper(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: target()
    #|          then:
    #|            patterns:
    #|              - shape: target()
  expect_compile_invalid(
    source, "patterns[0].then.patterns[0]: the pattern must contain exactly one __TARGET__ placeholder in a supported expression position",
  )
}
