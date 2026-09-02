///|
test "loops with a possible natural exit preserve zero-iteration paths" {
  let while_source =
    #|fn sample(flag) {
    #|  while flag {
    #|    return ()
    #|  };
    #|  sink(get_user_input())
    #|}
    #|
  let for_source =
    #|fn sample(flag) {
    #|  for ; flag; {
    #|    return ()
    #|  };
    #|  sink(get_user_input())
    #|}
    #|
  let foreach_source =
    #|fn sample(items) {
    #|  for item in items {
    #|    return ()
    #|  };
    #|  sink(get_user_input())
    #|}
    #|
  let counts = [
    analyze_call_source_sink(while_source).findings.length(),
    analyze_call_source_sink(for_source).findings.length(),
    analyze_call_source_sink(foreach_source).findings.length(),
  ]
  debug_inspect(
    counts,
    content=(
      #|[1, 1, 1]
    ),
  )
}

///|
test "unconditional for without break cannot reach nobreak or following code" {
  let source =
    #|fn sample {
    #|  for ;; {
    #|    clean()
    #|  } nobreak {
    #|    sink(get_user_input())
    #|  };
    #|  sink(get_user_input())
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 0)
}

///|
test "matching break reaches following code but skips nobreak" {
  let source =
    #|fn sample {
    #|  current~: for ;; {
    #|    break current~
    #|  } nobreak {
    #|    sink(get_user_input())
    #|  };
    #|  sink(get_user_input())
    #|}
    #|
  assert_eq(analyze_call_source_sink(source).findings.length(), 1)
}

///|
test "loop exits do not feed a header without a back edge" {
  let while_source =
    #|fn sample(flag) {
    #|  let mut x0 = get_user_input();
    #|  let mut x1 = (); let mut x2 = (); let mut x3 = ();
    #|  while {
    #|    x3 = x2; x2 = x1; x1 = x0; flag
    #|  } {
    #|    return ()
    #|  };
    #|  sink(x1); sink(x2); sink(x3)
    #|}
    #|
  let for_source =
    #|fn sample(flag) {
    #|  let mut x0 = get_user_input();
    #|  let mut x1 = (); let mut x2 = (); let mut x3 = ();
    #|  for ; {
    #|    x3 = x2; x2 = x1; x1 = x0; flag
    #|  }; {
    #|    return ()
    #|  };
    #|  sink(x1); sink(x2); sink(x3)
    #|}
    #|
  let counts = [
    analyze_call_source_sink(while_source).findings.length(),
    analyze_call_source_sink(for_source).findings.length(),
  ]
  debug_inspect(
    counts,
    content=(
      #|[1, 1]
    ),
  )
}
