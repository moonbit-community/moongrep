# taint 内部说明

本文记录修改 `taint` 包及其规则集成时容易遗漏的实现细节。它面向
analyzer 及其调用方的维护者，而不是规则作者。

## 包职责

`taint` 是一个基于 MoonBit parser AST 的通用过程内污点分析引擎。

这个包每次通过以下入口分析一个 parser `Impl`：

- `analyze_function_like(node, spec)`
- `analyze_function_like_multi(node, rules)`

只有函数形态的顶层节点是可执行的：

- 带 `DeclBody` 的 `TopFuncDef`
- 带 `DeclBody` 的 `TopImpl`

没有 body 的声明、顶层表达式、测试、类型定义、trait 以及其他 `Impl` 形式都会抛出
`TaintAnalysisError::UnsupportedFunctionLike`。规则应用层在扫描文件时会有意捕获并忽略该错误。

## 主流程

分析从 `analyze_single_function_like` 开始：

1. `function_like_from_impl` 提取函数或方法名称、位置、参数根，以及 body 表达式。
2. 根是真实参数的 `EntryPath` source 会写入初始 `TaintState`。
3. `eval_expr` 解释执行 body。
4. 求值过程中累积的 sink finding 会作为 `AnalysisResult` 返回。

这个引擎不是跨过程分析。它通过 `TaintSpec` 和 `CallInfo` 建模调用，但绝不会查找或分析 callee body。

## 状态和值

这里有两种相关的污点表示：

- `TaintState` 存储具名存储路径上的污点事实。
- `TaintTree` 存储相对于某个已求值表达式值的污点事实。

`TaintState` 是私有 `StateEntry` 值的数组：

```text
StoragePath(root, absolute segments) -> origins
```

`TaintTree` 是公开类型，表示为 `Array[RelativeTaint]`：

```text
relative segments below current value -> origins
```

例如，如果存储中的 `payload.secret` 被污染，那么 state 会包含一个以 `payload`
为根、段为 `Field("secret")` 的路径。求值 `payload` 会返回一棵相对路径为
`Field("secret")` 的 tree；求值 `payload.secret` 会把这棵 tree 投影到空相对路径，
表示这个值自身被污染。

origin 会按结构相等去重。merge 操作会保留同一路径上的所有唯一 origin。

## 存储路径

`StoragePath` 的 root 是局部变量或参数名。segment 会建模简单的投影式存储：

- `Field(name)` 表示 record field 和 label
- `TupleIndex(index)` 表示 tuple 投影
- `ConstIndex(value)` 表示用字面整数下标读取数组
- `AnyIndex` 表示未知数组下标和整个数组的摘要

`storage_path_from_expr` 只识别具有存储形状的表达式：

- identifier
- field
- array get
- 围绕这些形式的 group 和 constraint

调用、infix 表达式、constructor 和任意计算等表达式没有存储路径。它们仍然可以作为临时值携带
`TaintTree`，但 sanitizer 和 kill effect 无法移除后续的存储污点，除非被选择的值有
`StoragePath`。

读和写有意使用不同的前缀语义：

- 读使用 `path_prefix_match_for_read`，其中 `AnyIndex` 和 `ConstIndex`
  可以互相匹配，所以动态数组读取可以观察到摘要化或具体元素污点
- 写和 kill 使用 `path_prefix_match_for_write`，它要求 segment 完全相等，并且只移除被写入的子树

写入 `x.a` 会 kill `x.a` 下已有的事实，然后把新值的相对 tree 写到 `x.a` 下。
`x.b` 这样的 sibling fact 会被保留。

## 表达式求值

`eval_expr` 会按源码求值顺序解释支持的表达式形式。它返回一个 `EvalResult`，其中包含：

- 下一个存储状态
- 表达式值的污点
- 一个 `FlowExit`

常见的值构造会把子值污点移动到相对 subpath 中：

- tuple 第 `i` 项变为 `TupleIndex(i)`
- array 第 `i` 项同时变为 `ConstIndex(i)` 和 `AnyIndex`
- record field `f` 变为 `Field(f)`

路径形态的表达式会优先读取存储。如果表达式有具体存储路径，它的值就是
`state_read_path(state, path)`。否则，field 和 array 投影会先求值 base value，
再使用 `tree_project`。

`let` 和 `let mut` 会先求值右侧表达式，然后用 `bind_pattern` 绑定 pattern，再继续进入 body。
assignment 和 mutation 会在左侧可表示为存储路径时通过 `state_write_path` 更新存储。

不支持或不够具体的表达式形式会走 `eval_unknown_expr`。这个函数在局部意义上是保守的：
它会求值已知的子表达式，使嵌套调用仍然可以报告 sink；在需要值结果时，返回子值污点的并集。
完全不支持的叶子形式不会返回污点。

## Pattern 绑定

`bind_pattern` 会把被绑定值投影到 pattern 变量中：

- variable 和 alias pattern 会把整个值写入 binder
- tuple pattern 按 `TupleIndex` 投影
- record pattern 按 `Field` 投影
- array pattern 按常量下标或 `AnyIndex` 投影
- constructor 和 special-constructor 参数按位置 tuple index 或带标签 field 投影
- `or` pattern 会绑定两侧并合并结果状态

Pattern 绑定是结构化且类型无关的。它不会检查 MoonBit 类型声明、constructor 定义、field 定义或 collection 长度。

当整个值在空相对路径上带有污点时，解构也会把这份 whole-value 污点复制到每个被解构出的
binder 中。这样即使不解析 constructor payload 的类型信息，`input is Some(item)` 也会把
`item` 视为来自被污染的 `input`。

词法 binder 会在离开作用域后恢复。求值器会记录 `let`、case pattern、catch 和 try-else
pattern、lex/regex pattern、循环 binder 以及局部函数名引入的 root name。 scoped body 求值后，
这些 root 的条目会从进入作用域前的 base state 恢复；对未被 shadow 的 root 的 mutation 会被保留。

条件 pattern 会创建单独的 true-branch state。`is`、`lexmatch?`、regex match、grouped
condition 和 `&&` 只会在 true branch 或 loop body/continue 路径中暴露它们的 binder。
else branch、loop else block 以及作用域之后的表达式使用不含这些条件 binder 的 base state。

## 调用

所有调用语法都会先规范化为 `CallInfo`，然后再执行 transfer 逻辑：

- `Apply`
- `DotApply`
- `Pipe`
- `RevPipe`

`CallInfo` 携带：

- 原始调用 AST 和位置
- 可提取时的规范化 `callee_name`
- method-style 调用的 receiver path、site 和 taint
- 已求值参数，表示为 `CallArgument`

pipe desugaring 后的参数下标是语义下标：

- 普通调用参数从下标 `0` 开始
- `lhs |> f(arg)` 会让 `lhs` 成为参数 `0`，显式参数从 `1` 开始
- `f <| rhs` 会让 `rhs` 成为参数 `0`
- receiver 与参数保持分离

如果某个参数求值为 `return` 这类非 normal flow，则不会执行 call transfer。
这样可以避免某个参数已经退出控制流后，sink 调用仍然报告 finding。

## Transfer 顺序

`apply_call_transfer` 会把每次调用的第一次处理机会交给 `spec.custom_transfer_call`。
如果它返回 `Some(transfer)`：

1. 从存储中移除 `transfer.killed_paths`。
2. 按原样追加 `transfer.findings`。
3. `transfer.return_taint` 成为调用值。
4. 跳过声明式 source、声明式 call model，以及 unknown-call policy。

如果 custom transfer 返回 `None`，则执行 `apply_declared_call_transfer`：

1. 匹配到的 `SourceModel::CallReturn` 条目会添加新的 return taint
2. 所有匹配到的 `CallModel` 会按数组顺序应用
3. 如果没有任何匹配项，则由 `unknown_call_policy` 决定 return taint

声明式 model 匹配不是 first-match-wins。每个匹配到的 call model 都会贡献 effect。

Sink effect 会从被选择的值中收集 origin，并且只在至少存在一个 origin 时报告。
Custom transfer 需要自己维护这个不变量；引擎不会过滤它们的 finding。

Kill effect 只影响后续的存储读取。它不会重写同一次调用中已经为其他 effect 求值好的
receiver/argument taint。

## 控制流

`FlowExit` 会记录求值是正常继续，还是通过以下方式退出：

- `return`
- `raise`
- `break`
- `continue`

顺序求值遇到任何非 normal flow 都会停止。这就是为什么无条件 `return` 后面的 sink 不会被报告。

分支是 path-insensitive 的：

- `if` 会求值一次 condition，从 condition true-state 求值 true branch，从 base
  post-condition state 求值 false branch，恢复条件 binder，然后合并 normal 分支状态和值
- `match` 和 `catch` 会独立绑定每个 case，合并 normal case 状态，并且仅在没有 normal case 时保留 exit state
- `try` 会立即传播 `return`、`break` 和 `continue`；`raise` 会分派给 catch case
- 当 `try` body 正常完成时，catch 和 try-else case body 也会从 post-body state 出发，作为可能的 normal 分支求值

循环使用由 `spec.max_fixpoint_iterations` 控制的有界不动点。`while`、`for` 和
`foreach` 会反复从当前 join state 求值 body，直到下一轮没有添加新的污点事实或达到上限。
`return` 和 `raise` 会立即逃逸。`break` 会 join break state，然后离开循环。
`continue` 被视为 loop-body exit，但仍参与 join 路径。

`foreach` 会在 body fixpoint 开始前，把循环变量绑定到 collection 的 `AnyIndex` 投影。

## YAML 规则集成

YAML taint 规则在这个包之外编译：

1. `rule/compile` 校验 taint clause 并记录 `TaintTarget`。
2. `matching` 匹配编译后的 source、sink 和 sanitizer call pattern。
3. `rule/taint_lowering` 构造带 `custom_transfer_call` 的 `TaintSpec`。
4. `rule/apply` 运行 `@taint.analyze_function_like`，并把 sink finding 映射为 scanner `RuleFinding`。

lowering 层会把 YAML taint 语义实现为 custom transfer：

- 匹配 source call 时添加新的 return taint
- 匹配 sanitizer call 时，如果被选择的 target path 存在，则 kill 它
- 匹配 sink call 时，如果被选择的 target value 被污染，则报告

`rule/compile` 层保证 `__SOURCE__` 在 sink 或 sanitizer 中恰好出现一次，
并且是完整 receiver 或完整 argument。正因如此，`rule/taint_lowering` 可以直接从
`CallInfo` 中选择 target，而不需要遍历任意 subexpression。

Lowered YAML taint spec 使用：

- 没有 entry-path source
- 没有声明式 call model
- `unknown_call_policy = NoEffect`
- `max_fixpoint_iterations = 6`

这有意比通用 `taint` API 更窄。`TaintSpec` 的直接用户可以建模 entry source、
传播 unknown call，以及声明式 call effect，而这些目前都没有暴露给 YAML 规则。

## 重要限制

这个 analyzer 对简单存储路径是 path-sensitive 的，但除此之外是 path-insensitive 且类型无关的。

它不会：

- 跨函数边界分析
- 解析 import、overload、method、field、constructor 或 type
- 证明分支可行性
- 建模别名，除非通过显式存储写入和值拷贝
- 把任意 subexpression 表示为可被 kill 的存储
- 保证不支持 AST 形式的完整语义

这些限制是当前 scanner 的有意选择。如果某个改动需要更强的语义，请在 package boundary 和
YAML 规则集成 boundary 添加聚焦测试。

## 维护清单

新增一种具有存储形状的表达式时：

1. 更新 `storage_path_from_expr`
2. 必要时更新 `eval_expr` 中的读取/投影行为
3. 为 read、write、kill 和 merge 行为添加 domain 测试
4. 添加 taint 测试，展示 sink 行为能通过新的路径形式传播

新增一种能产生值的表达式时：

1. 按源码顺序求值 children
2. 遇到非 normal `FlowExit` 立即停止
3. 当该表达式构造 compound value 时，把 child taint 移到相对路径中
4. 为直接 sink 报告和 `let` 后存储两种情况添加测试

修改调用语义时：

1. 为所有应共享该行为的调用语法更新 `CallInfo` 构造
2. 保持 pipe 参数下标规则
3. 检查 `CallMatcher` 对 `CalleeName`、`MethodName` 和 `AnyCall` 的行为
4. 添加直接的 `taint/taint_test.mbt` 覆盖
5. 如果 YAML 行为变化，添加 `rule/apply` 或 `rule/taint_lowering` 测试

修改 YAML taint 行为时：

1. 更新 `rule/compile` 中的校验
2. 更新 `rule/taint_lowering` 中的 target 提取或 transfer 生成
3. 如果 `__SOURCE__` 匹配行为变化，保持 `matching/INTERNAL.md` 的占位符说明同步
4. 仅在用户可见语义变化时更新规则作者文档
5. 在 `rule/apply` 或 `rule/taint_lowering` 下添加集成测试

对于 package-local 的引擎工作，`moon test taint` 是最短反馈循环。对于通过 YAML
规则可见的变化，还要运行相关的 `rule/compile`、`rule/taint_lowering` 和 `rule/apply` 测试。
