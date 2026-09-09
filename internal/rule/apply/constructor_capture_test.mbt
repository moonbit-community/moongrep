///|
test "split constructor captures survive inside-toplevel and recursive then" {
  let nested =
    #|id: split-constructor
    #|description: Keep the type and constructor captures separate.
    #|patterns:
    #|  - shape: match $_ { $(Type:id)::$(Ctor:id)($_) => __TARGET__ }
    #|    then:
    #|      patterns:
    #|        - shape: middle(__TARGET__)
    #|          then:
    #|            patterns:
    #|              - shape: sink($_)
    #|                guard:
    #|                  $Type: '^Option$'
    #|                  $Ctor: '^Some$'
  let toplevel =
    #|id: split-constructor
    #|description: Keep the type and constructor captures separate.
    #|inside-toplevel:
    #|  - shape: 'fn $_ { match $_ { $(Type:id)::$(Ctor:id)($_) => __TARGET__ } }'
    #|patterns:
    #|  - shape: middle(__TARGET__)
    #|    then:
    #|      patterns:
    #|        - shape: sink($_)
    #|          guard:
    #|            $Type: '^Option$'
    #|            $Ctor: '^Some$'
  for rule in [nested, toplevel] {
    for
      (result, expected) in [
        ("Option::Some", 1),
        ("Other::Some", 0),
        ("Option::Other", 0),
      ] {
      let source = "fn sample { match input { \{result}(value) => middle(sink(value)) } }"
      assert_eq(apply_structural_rule_findings(source, rule).length(), expected)
    }
  }
}
