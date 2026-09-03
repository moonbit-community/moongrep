///|
fn query_match_count(pattern : String, source : String) -> Int raise {
  @query.ExprQuery::ExprQuery(pattern)
  .captures(source_name="builtin_rule_example.mbt", source)
  .length()
}

///|
fn query_alternative_match_count(
  patterns : ArrayView[String],
  source : String,
) -> Int raise {
  let mut count = 0
  for pattern in patterns {
    count += query_match_count(pattern, source)
  }
  count
}

///|
test "query implements inspect_boolean structural alternatives" {
  let patterns = [
    "inspect($_, content=\"true\")", "debug_inspect($_, content=\"true\")", "json_inspect($_, content=true)",
    "inspect($_, content=\"false\")", "debug_inspect($_, content=\"false\")", "json_inspect($_, content=false)",
  ]
  let source =
    #|fn snapshots(flag : Bool) -> Unit {
    #|  inspect(flag, content="true")
    #|  debug_inspect(flag, content="true")
    #|  json_inspect(flag, content=true)
    #|  inspect(flag, content="false")
    #|  debug_inspect(flag, content="false")
    #|  json_inspect(flag, content=false)
    #|  inspect(flag, content="not a boolean")
    #|}
    #|
  inspect(query_alternative_match_count(patterns, source), content="6")
}

///|
test "query extracts inspect_number candidates for guard filtering" {
  let pattern = "inspect($_, content=$(snapshot:const))"
  let source =
    #|fn snapshots(expected : String) -> Unit {
    #|  inspect(42, content="42")
    #|  inspect(-3.5, content="-3.5")
    #|  inspect(42, content=expected)
    #|}
    #|
  inspect(query_match_count(pattern, source), content="2")
}

///|
test "query implements match_option structural alternatives" {
  let patterns = [
    (
      #|match $(value:exp) {
      #|  Some($(some:id)) => $(some_body:exp)
      #|  None => $(none_body:exp)
      #|}
      #|
    ),
    (
      #|match $(value:exp) {
      #|  None => $(none_body:exp)
      #|  Some($(some:id)) => $(some_body:exp)
      #|}
      #|
    ),
    (
      #|match $(value:exp) {
      #|  Some(_) => $(some_body:exp)
      #|  None => $(none_body:exp)
      #|}
      #|
    ),
    (
      #|match $(value:exp) {
      #|  None => $(none_body:exp)
      #|  Some(_) => $(some_body:exp)
      #|}
      #|
    ),
  ]
  let source =
    #|fn handle(first : Int?, second : Int?) -> Unit {
    #|  ignore(match first {
    #|    Some(value) => consume(value)
    #|    None => fallback()
    #|  })
    #|  ignore(match second {
    #|    None => fallback()
    #|    Some(_) => consume_default()
    #|  })
    #|  ignore(match result() {
    #|    Ok(value) => consume(value)
    #|    Err(error) => report(error)
    #|  })
    #|}
    #|
  inspect(query_alternative_match_count(patterns, source), content="2")
}

///|
test "query implements simplifiable_assignment repeated targets" {
  let patterns = [
    "$(target:id) = $(target:id) + $_", "$(target:id) = $_ + $(target:id)", "$target.$(field:id) = $target.$(field:id) + $_",
    "$target.$(field:id) = $_ + $target.$(field:id)", "$target[$index] = $target[$index] + $_",
    "$target[$index] = $_ + $target[$index]",
  ]
  let source =
    #|fn update(state : State, values : Array[Int], step : Int) -> Unit {
    #|  let mut left = 0
    #|  left = left + step
    #|  let mut right = 0
    #|  right = step + right
    #|  state.left = state.left + step
    #|  state.right = step + state.right
    #|  values[0] = values[0] + step
    #|  values[1] = step + values[1]
    #|  left = right + step
    #|  state.left = state.right + step
    #|  values[0] = values[1] + step
    #|}
    #|
  inspect(query_alternative_match_count(patterns, source), content="6")
}

///|
test "query implements unnecessary_else alternatives" {
  let patterns = [
    (
      #|if $_ {
      #|  $_
      #|} else {
      #|  ()
      #|}
      #|
    ),
    (
      #|if $_ {
      #|  $_
      #|} else {}
      #|
    ),
  ]
  let source =
    #|fn branches(flag : Bool) -> Unit {
    #|  if flag {
    #|    work()
    #|  } else {
    #|    ()
    #|  }
    #|  if flag {
    #|    work()
    #|  } else {}
    #|  ignore(if flag { first() } else { second() })
    #|}
    #|
  inspect(query_alternative_match_count(patterns, source), content="2")
}

///|
test "query implements catch_all expression alternatives" {
  let patterns = [
    "try $_ catch { _ => $_ }", "$_ catch { _ => $_ }", "try $_ catch { $(error:id) => $_ }",
    "$_ catch { $(error:id) => $_ }",
  ]
  let source =
    #|async fn recover_all -> Unit {
    #|  try first() catch { _ => recover() }
    #|  second() catch { _ => recover() }
    #|  try third() catch { error => report(error) }
    #|  fourth() catch { error => report(error) }
    #|  try fifth() catch { Failure(message) => report(message) }
    #|}
    #|
  inspect(query_alternative_match_count(patterns, source), content="4")
}

///|
test "query recognizes forward and backward simple C-style loops" {
  let patterns = [
    (
      #|for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
      #|  $(body:exp)
      #|}
      #|
    ),
    (
      #|for $(counter:id) = $(start:exp); $(counter:id) > $(limit:exp); $(counter:id) = $(counter:id) - 1 {
      #|  $(body:exp)
      #|}
      #|
    ),
  ]
  let source =
    #|fn loops(limit : Int) -> Unit {
    #|  for i = 0; i < limit; i = i + 1 {
    #|    tick()
    #|  }
    #|  for j = limit; j > 0; j = j - 1 {
    #|    tick_back()
    #|  }
    #|  for k = 0; k < limit; other = other + 1 {
    #|    mismatched_counter()
    #|  }
    #|}
    #|
  inspect(query_alternative_match_count(patterns, source), content="2")
}

///|
test "query recognizes forward and backward C-style array iteration" {
  let patterns = [
    (
      #|for $(counter:id) = 0; $(counter:id) < $(array:id).length(); $(counter:id) = $(counter:id) + 1 {
      #|  $(consume:id)($(array:id)[$(counter:id)])
      #|}
      #|
    ),
    (
      #|for $(counter:id) = $(array:id).length() - 1; $(counter:id) >= 0; $(counter:id) = $(counter:id) - 1 {
      #|  $(consume:id)($(array:id)[$(counter:id)])
      #|}
      #|
    ),
  ]
  let source =
    #|fn iterate(items : Array[Int], others : Array[Int]) -> Unit {
    #|  for i = 0; i < items.length(); i = i + 1 {
    #|    consume(items[i])
    #|  }
    #|  for j = items.length() - 1; j >= 0; j = j - 1 {
    #|    consume_reverse(items[j])
    #|  }
    #|  for k = 0; k < items.length(); k = k + 1 {
    #|    consume(others[k])
    #|  }
    #|}
    #|
  inspect(query_alternative_match_count(patterns, source), content="2")
}
