///|
// These tests execute on the installed compiler; they pin the language
// contracts used by lowering rather than exercising the analyzer itself.
priv suberror SemanticError {
  SemanticError(String)
} derive(Debug)

///|
test "compiler loop initializers see outer binders and updates are simultaneous" {
  let x = 7
  let seen : Array[(Int32, Int32)] = []
  for x = 1, y = x, i = 0; i < 2; x = 2, y = x, i = i + 1 {
    seen.push((x, y))
  }
  debug_inspect(seen, content="[(1, 7), (2, 1)]")
}

///|
test "compiler explicit continue skips updates and passes parameters" {
  let seen : Array[Int32] = []
  let mut updates = 0
  for x = 0
      x < 2
      x = ({
          updates += 1
          x + 10
        }) {
    seen.push(x)
    continue x + 1
  }
  debug_inspect((seen, updates), content="([0, 1], 0)")
}

///|
test "compiler defer reads exit state in reverse order and snapshots the result" {
  let effects : Array[Int32] = []
  let mut x = 1
  let value = {
    defer effects.push(x)
    defer {
      x = 3
      effects.push(2)
    }
    x = 9
    x
  }
  debug_inspect((effects, value, x), content="([2, 3], 9, 3)")
}

///|
test "compiler cleanup errors replace the body error and activate outer errdefer" {
  let effects : Array[String] = []
  let message = try {
    errdefer effects.push("error")
    defer {
      raise SemanticError("cleanup")
    }
    raise SemanticError("body")
  } catch {
    SemanticError(message) => message
  }
  debug_inspect((effects, message), content="([\"error\"], \"cleanup\")")
}

///|
fn semantic_return(
  effects : Array[Int32],
  fail : Bool,
) -> Int32 raise SemanticError {
  errdefer effects.push(1)
  if fail {
    raise SemanticError("fail")
  }
  return 7
}

///|
test "compiler errdefer does not run on return" {
  let effects : Array[Int32] = []
  let value = semantic_return(effects, false)
  debug_inspect((effects, value), content="([], 7)")
}

///|
test "compiler short circuit evaluates operands once" {
  let mut side_effects = 0
  let left = false
  let _ = left &&
    ({
      side_effects += 1
      true
    })
  let _ = !left ||
    ({
      side_effects += 1
      false
    })
  inspect(side_effects, content="0")
}
