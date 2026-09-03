# matching 内部说明

本文记录修改 `internal/matching` 包时容易遗漏的实现细节。它面向 matcher
及其调用方的维护者，不面向规则作者。

## 匹配状态

`match_expr_pattern` 会先把原始节点转换为 expression candidate，再委托给
`match_expr_pattern_candidate`。candidate 入口会从一个新的
`HashMap[String, BoundValue]` 开始。
`match_expr_pattern_candidate_with_bindings` 会在匹配前复制调用方传入的 map。
失败的匹配可能在这个本地副本里留下部分捕获。调用方的 map 保持不变。

`match_expr_pattern_candidate` 和
`match_expr_pattern_candidate_with_bindings` 对 `Direct(CstNode)` 与
`Sequence(Array[CstNode])` 候选使用相同的状态规则。每个成功的 `ExprMatch` 都携带
候选的精确 `loc`；sequence location 合并首尾语句，因此不包含容器花括号。

普通节点从左到右完成绑定。包含 ellipsis 的有序 child 列表使用局部回溯：
每个候选长度都在 bindings 副本上运行，只有首个完整成功分支会被提交。

## 占位符分派

匹配会先调用 `match_expr_placeholder`、`match_type_placeholder`、
`match_pattern_placeholder` 和 `match_argument_placeholder` 这类占位符 matcher。如果其中一个返回
`Some(true)` 或 `Some(false)`，就会跳过结构化 CST 比较。只有 `None`
会继续落到普通的节点类型匹配。

表达式位置里的占位符优先级如下：

1. 完整且未限定的精确源码拼写 `$_` 是忽略占位符
2. `CompiledExprPattern.metavars` 中注册的特殊表达式占位符（如
   `__TARGET__` 和 `__SOURCE__`）会绑定整个表达式
3. 声明过的 expression metavar 绑定整个表达式值
4. 声明过的 identifier metavar 绑定规范化后的标识符字符串
5. 声明过的 constant metavar 只绑定 `Expr_Constant`
6. 未声明的名字是字面 CST 名称

所有源码拼写都通过已编译的 `MetavarRegistry` 解析。matcher 不会再从原始拼写
推断 metavar kind。限定形式对命名 metavar 仍有意义，但 `@pkg.$_`、`Type::$_`
和限定的匿名 ellipsis 拼写都不是 wildcard。

对于类型节点，一个包含已声明 type metavar payload 的简单 `Type_Name` 会绑定整个候选
type 节点。
重复的 type 捕获使用与其他 CST 节点捕获相同的忽略位置结构相等性。

对 var、binder 和 label，只有忽略占位符和声明过的 identifier metavar 有特殊含义；其他名称都是字面量。对 pattern variable，`$(name:pat)` 会绑定整个候选 `Pattern` CST，声明过的 constant metavar 只匹配
`Pattern_Constant`，声明过的 identifier metavar 捕获规范化后的 pattern 名称。
`__TARGET__` 和 `__SOURCE__` 只在整个表达式位置有特殊含义。例如，未声明的
`__x` 是字面量：只有完整且未限定的精确拼写 `$_` 本身才是忽略占位符。

parser 会在重新词法分析 string / bytes 插值源码时透传 metavar 模式。因此
`InterpSegment_Source` 已包含正确解析的 `expr` 子树，matcher 通过普通的 CST 递归
匹配处理它。所有片段共享同一个 bindings，因此跨插值片段的重复捕获仍遵循正常的
相等性语义。

## 绑定种类

公开 `model` 包将 `BoundValue` 定义为 `Single(CstNode)` 或
`Multiple(Array[CstNode])`。

expression、constant、argument、pattern、type 和 identifier metavar 通常使用
`Single`。identifier 捕获保留候选中真实的语义名称 CST 节点；比较或执行 guard 时
再做名称规范化。ellipsis metavar 使用 `Multiple`，并保留完整的有序 sibling 节点。
continuation header 后的末尾有名 expression metavar 或特殊 target 也会保留展开的
CST suffix：单语句 suffix 仍使用 `Single`，空或多语句 suffix 使用 `Multiple`。
continuation owner header 后精确的末尾 `$_` 也匹配完整 suffix，但它仍然不绑定，
不会产生 `BoundValue`。其他位置的 `$_` 只匹配一个表达式。

expression metavar 会捕获该位置上的候选表达式节点。重复使用时比较节点结构和 leaf
值，并忽略源码位置。

identifier metavar 会跨 expression、binder、label、constructor、accessor、
type-name 和 qualified-name 节点规范化源码名称。即使两次出现使用不同 CST 名称 kind，
重复绑定也按规范化后的拼写比较。

在 constructor 位置，一个 identifier metavar 会绑定完整 constructor identity。
expression constructor 保留真实的 `Expr_Constr` 节点；constructor pattern 保留真实、
覆盖完整 identity span 的语义名称节点。两者都会规范化 `@pkg.Ctor`、
`Type::Ctor`、`@pkg.Type::Ctor` 和 `@pkg.Type::@other.Ctor` 等形式。
显式写成 `$(Type:id)::$(Ctor:id)` 时，两部分仍分别绑定。

constant 占位符只接受常量表达式或常量 pattern 节点。pattern metavar 绑定完整
pattern 节点。type metavar 绑定完整类型节点。重复的 constant、pattern 和 type
捕获使用与所有其他绑定相同的语义 CST 相等性。

## 相等性忽略位置

matcher 在比较重复的 expression、argument、pattern 和 type 捕获时会忽略源码位置。重复绑定比较由
`bound_value_equal` 处理：`Single` 只和 `Single` 比较，`Multiple` 只和
`Multiple` 比较，混合 variant 不相等。

`node_equal_ignoring_loc` 会先比较规范化 identity 节点。由 `pat` 捕获的完整
constructor pattern 不是 identity 节点，仍要求 kind 相同并递归比较包含 constructor
参数在内的语义子节点视图。Leaf payload 仍有意义；位置从不进入这个视图。

## 语义 CST 视图

matcher 不直接比较原始 `CstNode.children`。`@cst.semantic_children` 会移除
`_loc` 字段、`Aggregate_Span`、EOF、`doc` 字段、`Syntax_Comment`、delimiter、
separator 和其他纯标点。因此，任何嵌套层级、任何匹配模式都把 docstring 视为
无语义注释。该视图还会从 parser wrapper 中展开语义名称、常量、操作符、
attribute、插值片段和 flag。插值源码的原始 payload 会被忽略，改用解析后的表达式。
冗余的 constructor qualification 元数据会被忽略，因为规范化名称已经保留该
identity。

之前树表示会消除的 `Pattern_Group` 和 `Type_Group` wrapper 会被展开。普通表达式块
仍保留结构；但作为带标签 `body` 容器的 block 如果只包含一个 whole-body 表达式
占位符，可以把候选 block 整体绑定给它。这保留了 loop 和 function-context 规则的
多语句 body 捕获行为。

expression matching 之前先执行 `internal/cst/scoped.mbt` 中的候选遍历。函数、方法、测试、
lambda、局部函数和 letrec body block 会生成不带花括号的 `Sequence` 候选，而不是
直接 block 候选。显式嵌套 block 仍是 `Direct(Expr_Block)`，其匹配 location 包含
花括号。

sequence 只接受完整的多语句 `Expression` shape，或普通 `let` / `guard` 的
omitted-continuation shortcut。`let`、`let mut`、`guard` 或其他 continuation owner
header 后的末尾有名 expression metavar、特殊 target 或精确 `$_` 会吸收完整的剩余
suffix；只有 `$_` 会丢弃该 suffix 而不绑定。
`let mut`、局部函数、`letrec` 和 `defer` 不使用 omitted-continuation shortcut。
这些 header 后存在语句时，遍历会生成 sequence suffix，而不会暴露 header-only
direct 候选。`proof_let` 不是 continuation owner，仍可独立匹配。

## 精确性

大多数语义 CST 节点都要求 kind 相同、语义子节点列表长度相同。child label 和顺序
都有意义。

值得注意的精确性细节：

- argument kind 必须匹配；label 也必须匹配，已声明的 label 占位符可以捕获变化的 label
- 常量保留 parser kind 和源码拼写
- 操作符、名称拼写、参数结构、attribute、flag 和 pattern 的 open/closed 结构有意义
- 注释（包括 docstring）、格式、位置、delimiter 和尾随标点没有意义
- parser hole 仍是字面 CST 节点，会按 hole kind 比较

语义 CST 形状不同的等价代码不会匹配。占位符可以吸收形状差异。

## 集成说明

修改占位符行为时，要更新所有知道占位符名字的三个位置：

- `internal/matching/matching.mbt`
- `internal/rule/prefilter/prefilter.mbt`
- `internal/rule/compile/compile.mbt` 中关于保留名字和受支持
  `__TARGET__` / `__SOURCE__` 位置的校验

新增 CST 节点支持时：

1. 先确认 `match_node` 的通用 `structural_match` 回退是否已经能够处理该节点；只有
   节点需要特殊匹配语义时，才新增或调整专用分派
2. 必要时为子结构添加辅助 matcher
3. 如果该节点可以被 metavar 绑定，更新重复捕获相等性
4. 更新 prefilter 的字面量收集，保证规则可搜索
5. 在 `internal/matching/matching_test.mbt` 添加聚焦测试
6. 如果 compiled rule 行为发生变化，添加 `internal/rule/apply` 或 taint 集成测试

对于只影响 matcher 的修改，`moon test internal/matching/matching_test.mbt` 是最短反馈循环。
对于通过 YAML 规则可见的行为，也要测试相关调用方包。
