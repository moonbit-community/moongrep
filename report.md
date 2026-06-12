# taint 模块对 MoonBit `is` 操作符的当前处理分析

## 结论

当前 `taint` 引擎对 MoonBit 的 `expr is pattern` 基本按“只分析左侧表达式，忽略右侧 pattern”处理。

具体行为是：

- 会递归分析 `is` 左侧表达式 `expr`。
- 不会分析或绑定右侧 `pattern` 中引入的变量。
- `is` 表达式自身的 taint value 直接沿用左侧表达式的 taint，而不是返回一个干净的 Bool taint。
- `IsLexMatch` 和 `RegexMatch` 目前也采用相同策略。

对应实现位于 `taint/engine.mbt`：

```mbt
Is(expr~, ..) | IsLexMatch(expr~, ..) | RegexMatch(expr~, ..) =>
  eval_expr(expr, state, spec, findings)
```

源码位置：`taint/engine.mbt:1500`

## 求值路径

`eval_expr` 是 taint 引擎的表达式求值入口。它显式处理了常见表达式节点，例如：

- `Ident` 读取 storage path taint。
- `Let` 先求右侧，再用 `bind_pattern` 绑定 pattern。
- `If` 先求 condition，再分别求 then/else。
- `Match` 先求 scrutinee，再对每个 case 调用 `bind_pattern`。
- 调用表达式会进入 call transfer 逻辑。

但是 `Is` 没有在主 `match expr` 中被单独处理，而是落到 `eval_unknown_expr`。在 `eval_unknown_expr` 里，`Is` 被归入“只求子表达式”的类别：

```mbt
Is(expr~, ..) | IsLexMatch(expr~, ..) | RegexMatch(expr~, ..) =>
  eval_expr(expr, state, spec, findings)
```

这意味着 `expr is pattern` 的右侧 pattern 对 taint 状态完全没有贡献。

## 与 `match` 的差异

`match` 的处理路径不同。`eval_match` 会：

1. 先求 scrutinee。
2. 对每个 case 调用 `bind_pattern(case.pattern, scrutinee_result.value, scrutinee_result.state)`。
3. 再在绑定后的 state 中分析 case guard 和 case body。

关键代码位于 `taint/engine.mbt:1112` 附近：

```mbt
let scrutinee_result = eval_expr(scrutinee, state, spec, findings)
...
let bound = bind_pattern(
  case.pattern,
  scrutinee_result.value,
  scrutinee_result.state,
)
```

`bind_pattern` 本身支持多种 pattern taint 投影：

- `Var(binder)`：把整个 value 写入变量。
- `Alias`：同时绑定内部 pattern 和 alias。
- `Tuple`：按 `TupleIndex(index)` 投影。
- `Record`：按 `Field(name)` 投影。
- `Array`：按 const index 或 `AnyIndex` 投影。
- `Constr` / `SpecialConstr`：按参数位置或 label 投影。
- `Or`：合并两侧 pattern 绑定结果。

关键代码位于 `taint/engine.mbt:935` 附近。

因此，当前语义下：

```mbt
match input {
  Some(x) => sink(x)
  _ => ()
}
```

会把 `input` 的 taint 经由 `Some(x)` 绑定到 `x`，而：

```mbt
if input is Some(x) {
  sink(x)
}
```

不会把 `input` 的 taint 绑定到 `x`。

## 对 `if` / `guard` 条件的影响

`if` 的实现是先求条件表达式，然后用条件求值后的 state 分别分析两个分支：

```mbt
let cond_result = eval_expr(cond, state, spec, findings)
...
let then_result = eval_expr(ifso, cond_result.state, spec, findings)
```

源码位置：`taint/engine.mbt:1079`

因为 `input is Some(x)` 当前只会求 `input`，不会绑定 `x`，所以 then 分支中读取 `x` 时，taint state 里没有来自 `input` 的绑定。

这会导致 `is` pattern 引入的变量传播缺失。

## 对表达式返回 taint 的影响

当前 `Is` 返回的是 `eval_expr(expr, ...)` 的结果，因此 `is` 表达式本身会继承左侧表达式的 taint。

例如：

```mbt
fn sample(input) {
  let ok = input is Some(_)
  sink(ok)
}
```

如果 `input` 是 tainted，当前分析很可能会把 `ok` 也视为 tainted。直观上，`ok` 是一个 Bool，通常不应该直接继承 `input` 的 value taint，除非规则显式建模隐式流或控制依赖。

因此当前行为同时存在两类问题：

- 右侧 pattern 绑定缺失，导致 false negative。
- `is` 表达式返回值继承左侧 taint，可能导致 false positive。

## 对 sink/source/sanitizer 规则形状的影响

YAML taint 规则本身要求 source、sink、sanitizer 的 `shape` 必须是 call expression，具体为 `Expr::Apply` 或 `Expr::DotApply`：

```mbt
match ast {
  Apply(..) | DotApply(..) => ()
  _ => raise RuleLoadError::InvalidRule(...)
}
```

源码位置：`rules/compile.mbt:348`

规则规范也说明 taint clauses 必须是 direct call 或 method call：

- source、sink、sanitizer shapes must be call expressions rooted at `Expr::Apply` or `Expr::DotApply`
- YAML taint shapes are written as direct calls or method calls only

源码位置：`rules/RuleSpec.md:119`

所以 `is` 不是作为 YAML taint clause 的顶层匹配形状参与 source/sink/sanitizer 建模；它主要影响函数体内部 taint 数据流求值。

## 与结构匹配模块的差异

结构匹配模块是支持 `Is` 的 AST 结构匹配的。`matching/matching.mbt` 中：

```mbt
(Is(expr=pe, pat=pp, ..), Is(expr=ce, pat=cp, ..)) =>
  match_expr(pe, ce, compiled, bindings) &&
  match_pattern(pp, cp, compiled, bindings)
```

源码位置：`matching/matching.mbt:180`

这说明 structural matcher 能匹配 `is` 的右侧 pattern；问题只是在 taint engine 的数据流语义中没有利用这个 pattern 做 taint 绑定。

## 当前行为示例

### 能传播的情况

```mbt
fn sample(input) {
  sink(input is Some(_))
}
```

因为 `input is Some(_)` 当前返回左侧 `input` 的 taint，`sink(...)` 的参数可能被认为 tainted。

### 不能正确传播的情况

```mbt
fn sample(input) {
  if input is Some(x) {
    sink(x)
  }
}
```

当前 `x` 不会因 `Some(x)` pattern 绑定获得 `input` 的 taint，因此这里可能漏报。

### `match` 可以传播的对应写法

```mbt
fn sample(input) {
  match input {
    Some(x) => sink(x)
    _ => ()
  }
}
```

`match` case 会调用 `bind_pattern`，所以 `x` 可以获得来自 scrutinee 的 taint。

## 总结

当前 taint 模块对 MoonBit `is` 操作符的处理是：

- 它把 `is` 当成只含左侧子表达式的数据流节点。
- 不把右侧 pattern 引入的变量写入 taint state。
- 不区分 `is` 的 Bool 结果和左侧被检测值，导致结果 taint 沿用左侧。
- 与 `match` 的 pattern 绑定语义不一致。

如果后续要改进，合理方向是给 `Is` 增加专门求值逻辑：

1. 先求左侧表达式。
2. 对 true 分支可见的状态应用 `bind_pattern(pat, expr_value, state)`。
3. `is` 表达式自身返回值默认应是空 taint，除非项目决定支持隐式流。
4. 在 `if`、`guard` 这类条件上下文中利用 pattern 绑定后的 true-branch state。

