# matching 内部说明

`internal/matching` 负责将编译后的 CST 模式与 MoonBit 源码 CST 进行比较并管理
元变量捕获。本文记录匹配器及其调用方维护者依赖的核心约定。

## 入口与匹配状态

- `match_expr_pattern` 将原始节点包装为表达式候选并委托给
  `match_expr_pattern_candidate`（使用全新的 `HashMap[String, BoundValue]`）。
- `match_expr_pattern_candidate_with_bindings` 在匹配前复制调用方传入的绑定表；
  失败尝试只会污染本地副本，调用方的原始表保持不变。
- 两个入口对 `Direct(CstNode)` 和 `Sequence(ArrayView[CstNode])` 候选使用一致的
  状态规则。成功返回的 `ExprMatch` 包含 `bindings` 及精确的 `loc`（sequence 的
  `loc` 合并首尾语句，不含容器花括号）。

### 回溯、索引与值驻留

- 普通节点从左到右绑定。含省略号的有序子节点列表使用局部回溯：每个候选长度在绑定
  表副本上尝试，仅提交首个完整成功的分支。
- 索引匹配通过 `MatchContext`（捕获 + 可选 `TargetRef`）共用同一套原子匹配器。
  `TargetRef` 只记录选中区域（或 continuation 语句列表及起止偏移，含空尾部），
  词法作用域按需从 `SourceIndex` 查询。
- 省略号回溯会一起提交或回滚捕获、标识符来源和 `TargetRef`。外层 `then` 失败
  不会要求原子匹配器重试另一种省略号划分。
- 独立匹配不建立 `SourceIndex`，因此 `query` 和污点调用匹配没有索引构建开销。
- `ValueInterner` 严格遵循 `bound_value_equal`（包括规范化身份节点及 `Single`
  与 `Multiple` 区分），哈希碰撞时比较完整键。规则环境借助驻留 ID 共享状态，
  公开查询仍返回原始 CST 节点。

## 占位符分派

在回退到通用结构比较前，匹配器会先调用专用占位符匹配函数
（`match_expr_placeholder`、`match_type_placeholder`、
`match_pattern_placeholder`、`match_argument_placeholder`）。返回 `Some(true)`
或 `Some(false)` 即短路；仅返回 `None` 时继续普通节点匹配。

### 表达式位置的占位符优先级

1. 完整且无限定的精确拼写 `$_` — 忽略占位符。
2. `CompiledExprPattern.metavars` 中注册的特殊占位符（`__TARGET__`、
   `__SOURCE__`）— 绑定整个表达式。
3. 已声明的 `exp` 元变量 — 绑定整个表达式节点。
4. 已声明的 `id` 元变量 — 绑定语义名称节点（按规范化标识符比较）。
5. 已声明的 `const` 元变量 — 仅绑定 `Expr_Constant`。
6. 其余名称 — 字面 CST 名称。

所有拼写均通过已编译的 `MetavarRegistry` 解析，匹配器不会从原始文本推导类别。
`@pkg.$_`、`Type::$_` 及带限定的匿名省略号都不是通配符。

### 非表达式位置

| 位置 | 特殊占位符 | 其他名称 |
| --- | --- | --- |
| 类型（`Type_Name`） | 已声明 `type` 元变量绑定完整候选 `Type` 节点 | 字面量 |
| 变量、binder、label | `$_` 与已声明 `id` 元变量 | 字面量 |
| Pattern 变量 | `$(name:pat)`（完整 `Pattern`）、已声明 `const`（`Pattern_Constant`）、已声明 `id`（规范化模式名）、`$_` | 字面量 |

`__TARGET__` 和 `__SOURCE__` 仅在完整表达式位置有特殊含义；未声明的 `__x` 始终是
字面量。

### 字符串与字节插值

parser 在重新词法分析插值片段时会透传 metavar 模式，因此 `InterpSegment_Source`
已带有解析好的 `expr` 子树。匹配器沿用同一绑定表递归匹配各片段，跨片段重复捕获的
相等语义保持不变。

## 绑定表示与相等性

公开 `model.BoundValue` 定义为 `Single(CstNode)` 或 `Multiple(Array[CstNode])`。

- **普通元变量**（`exp`、`id`、`const`、`arg`、`pat`、`type`）：使用 `Single`。
  标识符捕获保留候选真实的语义名称节点，比较或执行 guard 时再规范化。
- **省略号元变量**：使用 `Multiple`，保留完整的有序 sibling 节点。
- **Continuation 尾部**：在 continuation owner（`let`、`let mut`、局部函数、
  `letrec`、`guard`、`defer`、`errdefer`）之后，末尾具名 `exp` 元变量或特殊
  target 会保留展开的 CST suffix——单语句为 `Single`，空或多语句为 `Multiple`。
  末尾精确 `$_` 吸收完整 suffix 且不产生绑定；其他位置的 `$_` 仅匹配单个表达式。
- **构造器**：单个 `id` 元变量绑定完整构造器身份（表达式保留 `Expr_Constr`，
  pattern 保留完整跨度语义名称节点），统一规范化 `@pkg.Ctor`、`Type::Ctor`、
  `@pkg.Type::Ctor` 与 `@pkg.Type::@other.Ctor`。显式写出
  `$(Type:id)::$(Ctor:id)` 时两部分独立绑定。

重复捕获相等性（`bound_value_equal`）：

- `Single` 仅与 `Single` 比较，`Multiple` 仅与 `Multiple` 比较，混合变体不相等。
- `node_equal_ignoring_loc` 优先比较规范化身份节点。由 `pat` 捕获的完整构造器
  pattern 不是身份节点，仍需匹配节点种类并递归比较语义子节点（含构造器参数）。
  叶节点 payload 参与比较，源码位置从不进入比较视图。

## 语义 CST 视图与遍历

匹配基于 `@cst.semantic_children` 而非原始 `CstNode.children`：

- 移除 `doc` 字段并过滤纯标点 token（`TK_EOF`、`TK_COMMENT`、分隔符等），使
  docstring 在任意层级与模式下均不具语义。
- 从 parser wrapper 中展开语义名称、常量、操作符、attribute、插值片段（使用
  解析后的 `expr` 替代原始文本 payload）和 flag。
- 忽略已包含在规范化名称中的冗余构造器限定元数据。
- 展开 `Pattern_Group` 和 `Type_Group`。
- 保留普通表达式块结构；但带标签 `body` 容器的块若只含单个 whole-body 表达式
  占位符，可将候选块整体绑定给它（支持循环和函数上下文规则）。

候选遍历（`internal/cst`）：

- 函数、方法、测试、lambda、局部函数和 `letrec` 函数体生成不含花括号的 `Sequence`
  候选；显式嵌套块保持 `Direct(Expr_Block)` 且 `loc` 包含花括号。
- 普通规则和 `query` 直接遍历 CST（不构建节点 ID、作用域或缓存），sequence 和
  continuation 借用 `ArrayView`。递归规则与 `inside-toplevel` 规则共用
  `SourceIndex`，一次记录候选、函数体角色与不可变词法作用域，不再按源码范围重扫
  定位目标。
- 索引匹配在 `BoundValue` 之外返回标识符来源；继承的 `id`（含带类别的 `id` 省略
  号）仅在来源与使用均为词法变量时校验绑定，同 `shape` 内的新捕获维持原有相等规则。
- sequence 仅接受完整多语句 `Expression` 或普通 `let`/`guard` 的省略 body 快捷
  形式（`let mut`、局部函数、`letrec`、`defer`、`errdefer` 不享受该快捷形式）。
  `proof_let` 不是 continuation owner，仍可独立匹配。

## 精确性规则

- 大多数语义 CST 节点要求相同 `NodeKind`、相同语义子节点数量以及一致的 child
  label 与顺序。
- 参数种类和标签必须匹配（已声明标签占位符可捕获变化标签）。
- 常量保留 parser 种类与源码拼写。
- 操作符、名称、参数结构、attribute、flag、open/closed pattern 与 parser hole
  （按 hole kind）均参与匹配；注释、格式、位置、分隔符和尾随标点被忽略。
- 语义 CST 形状不同的等价代码不会匹配，除非由占位符吸收差异。

## 维护清单

修改占位符名称或行为时，须同步更新三处：

- `internal/matching/matching.mbt`
- `internal/rule/prefilter/prefilter.mbt`
- `internal/rule/compile/compile.mbt`（保留名及 `__TARGET__` / `__SOURCE__` 校验）

新增 CST 节点支持时：

1. 先确认 `match_node` 中的通用 `structural_match` 是否已覆盖，仅在需要专用语义时
   新增分派。
2. 按需补充子结构辅助匹配函数。
3. 若该节点可被元变量绑定，更新重复捕获相等性。
4. 更新 prefilter 的字面量收集以保持可搜索性。
5. 在 `internal/matching/matching_test.mbt` 添加聚焦测试；若影响已编译规则行为，
   补充 `internal/rule/apply` 或 taint 集成测试。

改动匹配器后运行 `moon test internal/matching/matching_test.mbt`；涉及 YAML 规则
行为时一并测试调用方包。
