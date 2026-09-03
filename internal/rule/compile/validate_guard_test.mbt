///|
test "validate rejects guard on type metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: |
    #|      let value : $(T:type) = input
    #|    guard:
    #|      $T: "^Int$"
    #|
  expect_compile_invalid(
    source, "patterns[0].guard.$T cannot reference type metavar T",
  )
}

///|
test "validate rejects unknown guard key" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(name:id)
    #|    guard:
    #|      $other: "^safe_"
    #|
  expect_compile_invalid(
    source, "patterns[0].guard.$other references unknown metavar",
  )
}

///|
test "validate rejects guard on exp and pat metavars" {
  let exp_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:exp))
    #|    guard:
    #|      $value: "^safe_"
    #|
  expect_compile_invalid(
    exp_source, "patterns[0].guard.$value cannot reference exp metavar value",
  )
  let pat_source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: match input { $(item:pat) => body }
    #|    guard:
    #|      $item: "^Some"
    #|
  expect_compile_invalid(
    pat_source, "patterns[0].guard.$item cannot reference pat metavar item",
  )
}

///|
test "validate rejects guard on arg metavars" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: sink($(value:arg))
    #|    guard:
    #|      $value: "^safe_"
    #|
  expect_compile_invalid(
    source, "patterns[0].guard.$value cannot reference arg metavar value",
  )
}

///|
test "validate rejects invalid guard regex" {
  let source =
    #|id: example
    #|description: Example.
    #|patterns:
    #|  - shape: $(name:id)
    #|    guard:
    #|      $name: "("
    #|
  expect_compile_invalid(source, "patterns[0].guard.$name has invalid regex")
}
