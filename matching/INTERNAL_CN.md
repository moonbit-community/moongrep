# matching 内部说明

本文记录修改 `matching` 包时容易遗漏的实现细节。它面向 matcher
及其调用方的维护者，而不是规则作者。

## 匹配状态

`match_expr_pattern` 会从一个新的 `HashMap[String, BoundValue]` 开始。
`match_expr_pattern_with_bindings` 会在匹配前复制调用方传入的 map。失败的匹配可能在这个本地副本里留下部分捕获，
但绝不会修改调用方的 map。

这里没有回溯引擎。辅助函数会在从左到右遍历时完成绑定；如果后面的子节点失败，整个候选匹配失败。
这没有问题，因为当前 matcher 没有需要回滚的替代分支。

## 占位符分派

表达式匹配会先调用 `match_expr_placeholder`。如果它返回 `Some(true)` 或
`Some(false)`，就会跳过结构化 AST 比较。类型节点还会先经过
`match_type_placeholder`。只有 `None` 会继续落到普通的节点类型匹配。

表达式位置里的占位符优先级如下：

1. 只由下划线组成且长度至少为 2 的名字，是忽略占位符
2. `target_metavar` 和 `source_metavar` 在 `CompiledExprPattern`
   中存在时，会绑定整个表达式
3. 声明过的 expression metavar 绑定整个表达式值
4. 声明过的 identifier metavar 绑定规范化后的标识符字符串
5. 声明过的 constant metavar 只绑定 `Expr::Constant`
6. 未声明的名字是字面 AST 名称

对于类型节点，一个简单 `Type::Name` 标记如果名称出现在
`CompiledExprPattern.type_metavars` 中，就会绑定整个候选 `Type_*` 节点。
重复的 type 捕获使用与其他 AST 节点捕获相同的忽略位置结构相等性。

对 var、binder 和 label，只有忽略占位符和声明过的 identifier metavar 有特殊含义；其他名称都是字面量。对 pattern variable，`$(name:pat)` 会绑定整个候选 `Pattern` AST，声明过的 constant metavar 只匹配
`Pattern::Constant`，声明过的 identifier metavar 捕获规范化后的 pattern 名称。
`__TARGET__` 和 `__SOURCE__` 只在整个表达式位置有特殊含义。例如，未声明的
`__x` 是字面量：只有 `__` 或 `___` 这种拼写本身才是忽略占位符。

## 绑定种类

`BoundValue` 是 `@untyped_ast.Node`。

每个绑定都会直接存为 untyped AST 节点。expression、constant、argument、pattern
和 type metavar 绑定它们匹配到的节点。identifier metavar 会把归一化名称编码成
`Leaf(PString(_))` 节点。

expression metavar 会捕获该位置上的候选表达式节点。重复使用时比较节点结构和 leaf
值，并忽略源码位置。

identifier metavar 会在绑定前归一化源码层面的名称。Expr、var 和 pattern 值会在可能时经过
`untyped_ast` 规范化 helper。Binder 和 label 匹配直接使用候选名称，因为这些节点已经携带了用于比较的短名称。

constant 占位符只接受常量表达式或常量 pattern 节点。pattern metavar 绑定完整
pattern 节点。type metavar 绑定完整类型节点。重复的 constant、pattern 和 type
捕获使用与所有其他绑定相同的 untyped 节点相等性。

## 相等性忽略位置

matcher 在比较重复的 expression、argument、pattern 和 type 捕获时会忽略源码位置。重复绑定比较由
`bound_value_equal` 处理，并委托给 `node_equal_ignoring_loc`。

`node_equal_ignoring_loc` 要求节点 kind 相同，并按顺序递归比较子节点标签和子值。
Leaf 值通过节点 kind 比较；整个遍历都会忽略 `loc` 字段。

## Let 头部匹配

MoonBit 会把 `let (__, __) = __` 这样的表达式解析为 `Expr::Let`，
其 body 是 parser 合成的 `Unit(faked=true)`。

matcher 会把这个 faked unit 视为“pattern 中省略了 body”。仅对 `Expr::Let` 而言，
它仍会匹配绑定 pattern 和右侧表达式，但不要求候选 body 也匹配。

显式的 let body 仍使用普通结构匹配。以下形式保持原有含义：

- `let (__, __) = __; finish(__)`
- `let x = __; __`
- `let x = __; ()`

`LetMut`、`LetFn` 和 `LetAnd` 不使用 faked-unit 快捷路径。

这个行为属于 matcher，而不是 parser，因此 `inside-expr` 仍可以使用嵌套 let 表达式，
例如 `let println = ___; __TARGET__`，并正常遍历目标 body。

## 精确性和小例外

大多数 AST 节点都要求节点种类相同且子节点列表长度完全一致。untyped matcher
会先检查长度相等，再按存储顺序比较子节点。

值得注意的精确性细节：

- argument kind 和 label 必须匹配，除非 label 是已声明的占位符
- record/map 的 trailing marker 和 open/closed flag 都有意义
- `Unit(faked=...)` 会比较 `faked` flag
- parser hole 是字面 AST 节点，会按 hole kind 比较
- interpolation 的 `Source(_)` 节点只按节点种类匹配；不会比较 parser token 内部结构

除了 identifier metavar 使用的显式标识符规范化之外，没有其他语义规范化。
例如，语义等价但 AST 形状不同的代码不会匹配，除非差异被占位符吸收。

## 集成说明

修改占位符行为时，要更新所有知道占位符名字的三个位置：

- `matching/matching.mbt`
- `rule/prefilter/prefilter.mbt`
- `rule/compile/compile.mbt` 中关于保留名字和受支持
  `__TARGET__` / `__SOURCE__` 位置的校验

新增 AST 节点支持时：

1. 新增或调整根级 `match_expr` 分支
2. 必要时为子结构添加辅助 matcher
3. 如果该节点可以被 metavar 绑定，更新重复捕获相等性
4. 更新 prefilter 的字面量收集，保证规则仍然可搜索
5. 在 `matching/matching_test.mbt` 添加聚焦测试
6. 如果 compiled rule 行为发生变化，添加 `rule/apply` 或 taint 集成测试

对于只影响 matcher 的修改，`moon test matching/matching_test.mbt` 是最短反馈循环。
对于通过 YAML 规则可见的行为，也要测试相关调用方包。
