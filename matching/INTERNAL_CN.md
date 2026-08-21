# matching 内部说明

本文记录修改 `matching` 包时容易遗漏的实现细节。它面向 matcher
及其调用方的维护者，不面向规则作者。

## 匹配状态

`match_expr_pattern` 会从一个新的 `HashMap[String, BoundValue]` 开始。
`match_expr_pattern_with_bindings` 会在匹配前复制调用方传入的 map。失败的匹配可能在这个本地副本里留下部分捕获。
调用方的 map 保持不变。

普通节点从左到右完成绑定。包含 ellipsis 的有序 child 列表使用局部回溯：
每个候选长度都在 bindings 副本上运行，只有首个完整成功分支会被提交。

## 占位符分派

匹配会先调用 `match_expr_placeholder`、`match_type_placeholder`、
`match_pattern_placeholder` 和 `match_argument_placeholder` 这类占位符 matcher。如果其中一个返回
`Some(true)` 或 `Some(false)`，就会跳过结构化 CST 比较。只有 `None`
会继续落到普通的节点类型匹配。

表达式位置里的占位符优先级如下：

1. 精确拼写 `$_` 是忽略占位符
2. `target_metavar` 和 `source_metavar` 在 `CompiledExprPattern`
   中存在时，会绑定整个表达式
3. 声明过的 expression metavar 绑定整个表达式值
4. 声明过的 identifier metavar 绑定规范化后的标识符字符串
5. 声明过的 constant metavar 只绑定 `Expr_Constant`
6. 未声明的名字是字面 CST 名称

对于类型节点，一个简单 `Type_Name` 标记如果名称出现在
`CompiledExprPattern.type_metavars` 中，就会绑定整个候选 type 节点。
重复的 type 捕获使用与其他 CST 节点捕获相同的忽略位置结构相等性。

对 var、binder 和 label，只有忽略占位符和声明过的 identifier metavar 有特殊含义；其他名称都是字面量。对 pattern variable，`$(name:pat)` 会绑定整个候选 `Pattern` CST，声明过的 constant metavar 只匹配
`Pattern_Constant`，声明过的 identifier metavar 捕获规范化后的 pattern 名称。
`__TARGET__` 和 `__SOURCE__` 只在整个表达式位置有特殊含义。例如，未声明的
`__x` 是字面量：只有精确拼写 `$_` 本身才是忽略占位符。

## 绑定种类

`BoundValue` 是 `Single(CstNode)` 或 `Multiple(Array[CstNode])`。

expression、constant、argument、pattern、type 和 identifier metavar 使用
`Single`。identifier 捕获保留候选中真实的语义名称 CST 节点；比较或执行 guard 时
再做名称规范化。ellipsis metavar 使用 `Multiple`，并保留完整的有序 sibling 节点。

expression metavar 会捕获该位置上的候选表达式节点。重复使用时比较节点结构和 leaf
值，并忽略源码位置。

identifier metavar 会跨 expression、binder、label、constructor、accessor、
type-name 和 qualified-name 节点规范化源码名称。即使两次出现使用不同 CST 名称 kind，
重复绑定也按规范化后的拼写比较。

constant 占位符只接受常量表达式或常量 pattern 节点。pattern metavar 绑定完整
pattern 节点。type metavar 绑定完整类型节点。重复的 constant、pattern 和 type
捕获使用与所有其他绑定相同的语义 CST 相等性。

## 相等性忽略位置

matcher 在比较重复的 expression、argument、pattern 和 type 捕获时会忽略源码位置。重复绑定比较由
`bound_value_equal` 处理：`Single` 只和 `Single` 比较，`Multiple` 只和
`Multiple` 比较，混合 variant 不相等。

`node_equal_ignoring_loc` 会先比较规范化名称。其他节点要求 kind 相同，并按顺序递归
比较语义子节点视图。Leaf payload 仍有意义；位置从不进入这个视图。

## 语义 CST 视图

matcher 不直接比较原始 `CstNode.children`。`@cst.semantic_children` 会移除
`_loc` 字段、`Aggregate_Span`、EOF、`doc` 字段、`Syntax_Comment`、delimiter、
separator 和其他纯标点。因此，任何嵌套层级、任何匹配模式都把 docstring 视为
无语义注释。该视图还会从 parser wrapper 中展开语义名称、常量、操作符、
attribute、插值片段和 flag。冗余的 constructor qualification 元数据会被忽略，
因为规范化名称已经保留该 identity。

之前树表示会消除的 `Pattern_Group` 和 `Type_Group` wrapper 会被展开。普通表达式块
仍保留结构；但作为带标签 `body` 容器的 block 如果只包含一个 whole-body 表达式
占位符，可以把候选 block 整体绑定给它。这保留了 loop 和 function-context 规则的
多语句 body 捕获行为。

表达式容器还保留了省略 let/guard body 与尾部 unit 之间的旧拼写兼容。显式 body
仍按结构匹配。

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

- `matching/matching.mbt`
- `rule/prefilter/prefilter.mbt`
- `rule/compile/compile.mbt` 中关于保留名字和受支持
  `__TARGET__` / `__SOURCE__` 位置的校验

新增 CST 节点支持时：

1. 新增或调整根级 `match_expr` 分支
2. 必要时为子结构添加辅助 matcher
3. 如果该节点可以被 metavar 绑定，更新重复捕获相等性
4. 更新 prefilter 的字面量收集，保证规则可搜索
5. 在 `matching/matching_test.mbt` 添加聚焦测试
6. 如果 compiled rule 行为发生变化，添加 `rule/apply` 或 taint 集成测试

对于只影响 matcher 的修改，`moon test matching/matching_test.mbt` 是最短反馈循环。
对于通过 YAML 规则可见的行为，也要测试相关调用方包。
