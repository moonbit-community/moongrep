# rule/compile 内部说明

本文记录修改 `rule/compile` 包时容易遗漏的实现细节。它面向规则编译器及其调用方的维护者，
不面向规则作者。

## 包职责

`rule/compile` 是 pattern 源文本与可执行 matcher / 规则之间的校验与规范化边界。

这个包提供两个公开入口：

- `compile_rules(raw_rules)`
- `compile_expr_pattern(pattern)`

`compile_rules` 从 `rule/model` 接收 `RawRuleSpec` 并生成 `CompiledRule`。
`compile_expr_pattern` 则把一个普通 structural expression shape 直接编译成
`matching.CompiledExprPattern`，不构造规则元数据、guard 或规则级 prefilter。

编译职责有意保持收窄。这个包会：

- 检查重复 rule id
- 把普通规则 `shape` 解析成 MoonBit 表达式，并把每个
  `inside-toplevel` 条目的 shape 解析成一个顶层项
- 记录 metavar，并校验它在 CST 中的位置
- 拒绝不支持的占位符位置和格式错误的 guard
- 记录 taint sink 和 sanitizer 的 target 元数据
- 为编译后的定义构造源码文本 prefilter

它不匹配源码、不执行 guard、不 lower taint 规则，也不扫描文件。这些职责分别属于
`matching`、`rule/apply`、`rule/taint_lowering` 和 `rule/prefilter`。

## 主流程

`compile_rules` 先调用 `ensure_unique_rule_ids`，再用 `compile_rule`
编译每条 raw rule。

`compile_rule` 会先编译规则主体，再构造 prefilter：

1. structural rule 走 `compile_structural_rule`
2. taint rule 走 `compile_taint_rule`
3. `compile_rule_prefilter(definition)` 从编译后的 CST 推导必需源码字面量

prefilter 必须基于编译后的 definition。此时 metavar 已经完成分类，可以从字面量
收集中排除。原始 YAML 不具备这个条件。

`compile_expr_pattern` 会创建与单个匿名 `patterns[0]` 条目相同的上下文，并调用
`compile_structural_expr_pattern`。普通 structural `patterns` 和
`patterns-not` 也使用这个 helper。该 helper 负责解析表达式、分类 metavar、在存在
inside context 时校验继承绑定、拒绝 `__TARGET__`，并构造 matcher pattern。
直接入口不传入外层 shape，因此继承绑定校验为空操作；调用方可再通过
`rule/prefilter` 单独构造单模式 prefilter。

## Shape 解析

`collect_shape_metavars` 先使用以下 lexer 配置：

```text
comment = true
enable_metavar = true
```

lexer 会识别 metavar token，并记录每个出现位置的原始 span 和逻辑语法。随后
`parse_shape` 直接调用
`@untyped_cst.parse_expression(..., enable_metavar=true)`；
`parse_toplevel_shape` 调用
`@untyped_cst.parse_structure(..., enable_metavar=true)`，并要求
`@cst.toplevel_nodes` 只返回一个节点。metavar 语法会继续保留在 CST 中，
不再替换成保留标识符。

外层 lexer 会把每个 string / bytes 插值保留为一个聚合 token。为记录其中的
metavar，收集器会遍历 parser CST，并使用全局起点、`is_interpolation=true` 和
`enable_metavar=true` 对每个 `InterpSegment_Source` 做子词法分析。parser 在构建每个
片段的 `expr` 子树时也会透传同一 metavar 模式，包括嵌套插值。因此校验和上下文识别
可以直接使用原始 CST。

和 CST 迁移前一样，`Type_Name` 必须从大写 identifier token 开始。因此显式
`type` metavar 和带 `type` kind 的 ellipsis metavar 都必须使用大写名称；小写名称
和关键字名称仍会被 parser 拒绝。

普通 `patterns`、`patterns-not`、每个 `inside-expr` 条目和 taint 子句的 shape
都必须正好是一个 MoonBit 表达式。每个 `inside-toplevel` shape 必须正好是一个
顶层项。编译器直接保留 parser 的 `CstNode`，不再 lower 到 typed syntax，也不再
转换成本地树类型。

词法错误会先于解析错误报告。`InvalidMetavarSyntax` 有专门诊断，因此
`$exp:value` 这样的旧语法可以提示迁移到现代的 `$(value:exp)` 形式。
其他词法错误会报告 lexical errors，解析错误会根据子句报告
"not a valid MoonBit expression" 或 "not a valid MoonBit top-level item"。

即使 parser 没有生成诊断，编译器也会拒绝 recovery 节点（`Missing` 和 `Error`）。

## Metavar 上下文

Metavar 编译会按记录的源码 span 在 CST 中定位每个出现位置，并从节点路径推导
上下文。上下文记录 expression、identifier、pattern、type、whole-argument、
binder-only、qualified-name 和 ordered-list 信息。kind 校验只使用这些上下文，
不会修改或重建只读 CST。插值表达式节点及其 metavar span 已使用全局源码偏移，
因此所有 occurrence 都使用同一个 CST 根节点。

Bare kind 推断有意保守：

- 显式声明为 `pat`、`exp`、`id`、`const`、`arg` 或 `type` 的名称保持该 kind
- bare identifier 位置推断为 `id`
- bare type 位置推断为 `type`
- bare pattern-variable 位置不能单独完成推断
- bare expression 位置仅在没有更早规则解析该名称时推断为 `exp`
- `const`、`arg` 和 `pat` 永远不会从 bare `$name` 推断出来

这个顺序让 `$counter` 这类重复 bare 名称可以从 binder 位置推断为 `id`，
并在后续表达式位置复用该 kind。它也会拒绝 `$item => body` 这种普通 match
pattern，因为该位置在 `id`、`const` 和 `pat` 之间有歧义。

## Metavar Kind

当前只支持以下 inline kind：

- `exp`：完整的 bare identifier 表达式，捕获候选表达式
- `id`：源码层面的名称，例如 identifier、binder、label、constructor、
  type name，以及 qualified name 的后缀
- `const`：完整的 bare identifier 表达式或简单 pattern-variable 位置，
  并且必须匹配解析后的常量
- `arg`：完整的裸调用参数槽
- `pat`：简单 pattern-variable 位置，捕获完整候选 pattern CST
- `type`：完整的 CST type 节点

matcher 会通过编译后的 `MetavarRegistry` 解析 `$name`、`$(name:kind)`、
`$$$name` 和 wildcard 拼写。只有完整且未限定的 `$_` 是单节点忽略占位符；
限定 wildcard 会在 occurrence 校验阶段被拒绝。

普通 expression shape 的 registry entry 按首次出现顺序保存。Top-level function
shape 保留既有的 identifier 优先级：参数中的 identifier metavar 排在其他
identifier entry 之前。不要把 registry entry 排序当作清理。

## 保留名称

Inline 声明不能使用：

- `$_`
- `__TARGET__`
- `__SOURCE__`

完整且未限定的 `$_` 是 matcher 的忽略占位符。`__TARGET__` 保留给 structural
inside-context 遍历，`__SOURCE__` 保留给 taint sink 和 sanitizer target 选择。

以下划线开头不会自动成为保留名称。`__moongrep_value` 等名称不是保留名称。上面列出的精确内置名是保留名称。

## Structural Rule

`compile_structural_rule` 会在存在 inside context 时，先编译
`inside-expr` 或 `inside-toplevel` 的所有有序备选项，再编译内部
positive / negative pattern。

每个 inside-context shape 会被编译成普通 pattern，并使用：

- 它的 pattern object 上声明的 guard
- 在其 `MetavarRegistry` 中注册为特殊表达式占位符的 `__TARGET__`

每个备选项都必须包含恰好一个由
`count_bindable_expr_identifier_in_node` 统计到的完整表达式标识符位置
`__TARGET__`。这与运行时 matcher 分派特殊表达式元变量的位置相同。
Pattern variable、binder、label 和其他字面名称节点不计入其中。更广义的
`count_supported_name_in_node` 仍用于 `__SOURCE__` 校验。

选中的 inside 备选项中声明的 metavar 在匹配目标表达式时可见。内部的
`patterns` 和 `patterns-not` 必须重复相同 inline 形式才能复用该绑定。
被复用的捕获必须由每个外层备选项以相同 kind 声明，包括命名 ellipsis
捕获。`ensure_inherited_inside_context_metavar_forms_for_all` 同时检查跨备选项
可用性和 kind 一致性。内部未引用的捕获保持分支局部，不要求一致。

普通 `patterns` 和 `patterns-not` 会在 inside context 之后，通过与
`compile_expr_pattern` 相同的 helper 独立编译。它们不能在完整表达式位置包含
`__TARGET__`；非表达式字面名称中的相同拼写仍按字面处理。

## Guard

`compile_guards` 只接受 key 为 `$` 前缀捕获名、value 能编译成 regex 的 map 项。

Guard 只能引用 `id` 和 `const` 捕获。它不能引用：

- 未知名称
- `exp` 捕获
- `arg` 捕获
- `pat` 捕获
- `type` 捕获

这是规则编译器层面的限制。`rule/apply` 中的 guard 求值期望从规范化 identifier
或 constant 中得到类似字符串的值。它不接受任意 expression、pattern、argument 或 type CST。

## Taint Rule

每个 taint source、sink 和 sanitizer shape 都必须编译成顶层 call CST：

- `Expr_Apply`
- `Expr_DotApply`

Source 不能包含 `__SOURCE__`。匹配到 source call 后，后续
`rule/taint_lowering` 会添加新的 return taint。

Sink 和 sanitizer 必须包含恰好一个 `__SOURCE__`，且它必须是完整 receiver 或某个参数的完整
value。`sink(wrap(__SOURCE__))` 这类嵌套形式会被拒绝，因为 lowering 需要从
`CallInfo` 里直接选择一个已经求值好的 call value。

`require_source_target` 会把被选择的值记录为：

- `Receiver`
- `PositionalArg(index)`
- `LabelledArg(label, index)`

对于 labelled argument，会同时存 label 和 index。lowering 层用 index 找到已求值的
call argument，并用 label 确认选中的是同一个 labelled slot。

## 集成边界

有几个包会有意共享同一套占位符语义：

- `rule/compile` 解析和校验 inline 语法、`__TARGET__`、`__SOURCE__`
- `matching` 实现实际的占位符匹配和绑定行为
- `rule/prefilter` 从必需字面量收集中排除 matcher 占位符
- `rule/taint_lowering` 消费编译后的 `TaintTarget` 元数据
- `rule/apply` 在 structural match 之后执行编译后的 guard

修改用户可见的规则语义时，要更新所有受影响的边界，以及规则作者文档
`docs/RuleSpec.md` 和 `docs/RuleSpec_CN.md`。

## 维护清单

新增 parser CST 形式支持时：

1. 为新的路径或包装节点更新 CST occurrence-context 分类
2. 直接保留 parser 节点，不要增加第二套树表示
3. 添加 `rule/compile` 校验测试，展示新位置可用
4. 检查 `matching` 是否真的能匹配生成的 untyped CST
5. 如果新 CST 携带字面名称或常量，更新 `rule/prefilter`

修改 metavar kind 或位置时：

1. 同时更新收集、解析和重写校验
2. 如果运行时匹配行为变化，更新 matcher 占位符分派
3. 如果新 kind 可以被 guard，更新 guard 校验
4. 为显式语法、bare 推断、重复捕获和冲突诊断添加测试
5. 只有规则作者可见语义变化时才更新公开规则规格

修改 inside-context 行为时：

1. 保持 `__TARGET__` 编译期检查与 matcher 支持一致
2. 对 `patterns` 和 `patterns-not` 都保留继承 metavar 的 kind 检查
3. 保持有序首项选择语义：guard 失败可以继续，但外层条目一旦选中就不回退
4. 测试含 positive pattern、negative pattern 和 negative-only
   `inside-expr` / `inside-toplevel` 的规则
5. 检查 `rule/apply` root buckets，以及 `rule/prefilter` 的外层×内层备选项

修改 taint target 行为时：

1. 更新 `ensure_taint_call_shape` 或 `require_source_target`
2. 更新 `rule/taint_lowering.target_value`
3. 如果 `__SOURCE__` 匹配行为变化，保持 `taint/INTERNAL.md` 和
   `matching/INTERNAL.md` 的说明同步
4. 添加编译期校验测试和规则应用测试

对于 package-local 的校验工作，`moon test rule/compile` 是最短反馈循环。
对于通过已加载 YAML 规则可见的行为，还要测试 `rule/apply`、`rule/taint_lowering`
以及相关 e2e snapshot。
