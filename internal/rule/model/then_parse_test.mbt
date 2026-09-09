///|
test "then rejects invalid group schema with recursive paths" {
  let cases = [
    ("null", "patterns[0].then must be a mapping"),
    ("[]", "patterns[0].then must be a mapping"),
    ("{}", "patterns[0].then requires patterns or patterns-not"),
    ("{patterns: []}", "patterns[0].then.patterns must not be empty"),
    ("{patterns-not: []}", "patterns[0].then.patterns-not must not be empty"),
    ("{patterns: nope}", "patterns[0].then.patterns must be an array"),
    ("{unexpected: []}", "patterns[0].then contains unsupported key unexpected"),
    (
      "{patterns: [{shape: '__TARGET__', then: {patterns-not: [{shape: target(), then: {}}]}}]}",
      "patterns[0].then.patterns[0].then.patterns-not[0] contains unsupported key then",
    ),
  ]
  for pair in cases {
    let source = "id: example\ndescription: Example.\npatterns:\n  - shape: __TARGET__\n    then: " +
      pair.0
    expect_invalid_rule_info(source, pair.1)
  }
}

///|
test "then is only a positive structural entry field" {
  for
    source in [
      "patterns: [{shape: target()}]\npatterns-not: [{shape: danger(), then: {patterns: [{shape: target()}]}}]",
      "inside-toplevel: [{shape: 'fn f { __TARGET__ }', then: {patterns: [{shape: target()}]}}]\npatterns: [{shape: target()}]",
      "taint: {sources: [{shape: source(), then: {patterns: [{shape: target()}]}}], sinks: [{shape: 'sink(__SOURCE__)'}]}",
    ] {
    try
      RawRuleSpec::from_str(
        "/tmp/example.yaml",
        "/tmp",
        "id: example\ndescription: Example.\n" + source,
      )
    catch {
      RuleLoadError::InvalidRule(info~, ..) =>
        assert_true(info.contains("unsupported key then"))
      err => fail("unexpected error: \{err}")
    } noraise {
      _ => fail("expected invalid rule")
    }
  }
}
