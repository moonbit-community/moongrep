///|
fn origin(name : String) -> @domain.TaintValue {
  @domain.TaintValue::source({
    rule_id: "domain",
    origin_id: name,
    site: Synthetic(name),
    note: None,
  })
}

///|
test "whole-value inheritance and exact clean overrides preserve siblings" {
  let whole = origin("whole")
  let clean = @domain.TaintValue::clean()
  let cleared = whole.sanitize([Field("secret")])
  debug_inspect(cleared.project([Field("secret")]).is_clean(), content="true")
  debug_inspect(cleared.project([Field("sibling")]) == whole, content="true")
  debug_inspect(
    cleared.project([Field("sibling"), TupleIndex(0), ConstIndex("1")]) == whole,
    content="true",
  )
  debug_inspect(
    cleared.join(whole).project([Field("secret")]) == whole,
    content="true",
  )
  debug_inspect(
    cleared.join(cleared).project([Field("secret")]) == clean,
    content="true",
  )
  debug_inspect(whole.project([Field("secret")]) == whole, content="true")
}

///|
test "constant array updates are strong and dynamic writes are weak" {
  let tainted = origin("element")
  let clean = @domain.TaintValue::clean()
  let array = clean.write([AnyIndex], tainted).sanitize([ConstIndex("0")])
  debug_inspect(array.project([ConstIndex("0")]).is_clean(), content="true")
  debug_inspect(array.project([ConstIndex("1")]) == tainted, content="true")
  debug_inspect(array.project([AnyIndex]) == tainted, content="true")
  debug_inspect(array.sanitize([AnyIndex]) == array, content="true")
  let rewritten = array.write([AnyIndex], origin("unknown"))
  debug_inspect(
    rewritten.project([ConstIndex("0")]).origins().map(o => o.origin_id),
    content="[\"unknown\"]",
  )
  debug_inspect(
    rewritten.project([ConstIndex("1")]).origins().map(o => o.origin_id),
    content="[\"element\", \"unknown\"]",
  )
  debug_inspect(
    rewritten.sanitize([ConstIndex("0")]).project([ConstIndex("1")]) ==
    rewritten.project([ConstIndex("1")]),
    content="true",
  )
  debug_inspect(
    array.join(clean).project([ConstIndex("0")]).is_clean(),
    content="true",
  )
}

///|
test "semantic join is commutative associative and idempotent" {
  let clean = @domain.TaintValue::clean()
  let a = origin("a")
  let b = origin("b")
  let samples = [
    clean,
    a,
    b,
    a.sanitize([Field("x")]),
    b.sanitize([Field("y")]),
    clean.write([Field("x")], a),
    a.write([AnyIndex], b).sanitize([ConstIndex("0")]),
    clean.write([ConstIndex("0"), Field("x")], b),
  ]
  for a in samples {
    assert_eq(a.join(a), a)
    for b in samples {
      assert_eq(a.join(b), b.join(a))
      for c in samples {
        assert_eq(a.join(b).join(c), a.join(b.join(c)))
      }
    }
  }
}

///|
test "nested projections and writes use the same effective value" {
  let value = origin("root").sanitize([Field("x"), TupleIndex(0)])
  let nested = value.project([Field("x")])
  debug_inspect(nested.project([TupleIndex(0)]).is_clean(), content="true")
  debug_inspect(
    nested.project([TupleIndex(1)]) == origin("root"),
    content="true",
  )
  debug_inspect(
    value.project([Field("x"), TupleIndex(1)]) ==
    nested.project([TupleIndex(1)]),
    content="true",
  )
}
