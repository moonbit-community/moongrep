# rule/compile 内部说明

本文记录修改 `rule/compile` 包时容易遗漏的实现细节。它面向规则编译器及其调用方的维护者，
而不是规则作者。

## 包职责

`rule/compile` 是已加载 YAML 规则和可执行规则之间的校验与规范化边界。

这个包从 `rule/model` 接收 `RawRuleSpec`，并通过唯一公开入口生成
`CompiledRule`：

- `compile_rules(raw_rules)`

编译职责有意保持收窄。这个包会：

- 检查重复 rule id
- 把每个规则 `shape` 解析成一个 MoonBit 表达式
- 把 metavar 重写成 matcher 可读取的 AST 名称
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
3. `compile_rule_prefilter(definition)` 从编译后的 AST 推导必需源码字面量

prefilter 必须基于编译后的 definition，而不是原始 YAML，因为此时 metavar
已经被规范化，可以从字面量收集中排除。

## Shape 解析

`parse_shape` 使用以下 lexer 配置：

```text
comment = true
enable_metavar = true
```

随后用 `parse_expr` 解析 token 流。因此一个 shape 正好是一个 MoonBit 表达式，
不是文件片段或顶层声明。

词法错误会先于解析错误报告。`InvalidMetavarSyntax` 有专门诊断，因此
`$exp:value` 这样的旧语法可以提示迁移到现代的 `$(value:exp)` 形式。
其他词法错误会报告 lexical errors，解析错误会报告 "not a valid MoonBit expression"。

matcher 不会直接看到 parser AST。metavar 重写完成后，表达式会通过
`@untyped_ast.from_expr` 转成 `@untyped_ast.Node`。

## Metavar 重写

Metavar 编译会对 parser AST 进行两遍遍历：

1. 收集显式声明和 bare `$name` 的出现位置
2. 解析 bare kind，并用具体名称重写 AST

两遍遍历都使用相同形态的 `MetavarRewriteContext`。在收集阶段，显式
`$(name:kind)` 会立即注册 kind；bare `$name` 只记录出现的语法位置，并保持 AST
不变。

Bare kind 推断有意保守：

- 显式声明为 `pat`、`exp`、`id` 或 `const` 的名称保持该 kind
- bare identifier 位置推断为 `id`
- bare pattern-variable 位置不能单独完成推断
- bare expression 位置仅在没有更早规则解析该名称时推断为 `exp`
- `const` 永远不会从 bare `$name` 推断出来

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
- `pat`：简单 pattern-variable 位置，捕获完整候选 pattern AST

重写代码通过 `rewrite_expr_var`、`rewrite_var`、`rewrite_binder`、
`rewrite_label`、`rewrite_constructor` 和 `rewrite_pattern_var_binder`
分派并校验位置。

Pattern metavar 有特殊表示。`$(name:pat)` pattern variable 会被重写成字面
binder 文本 `$(name:pat)`，这样 `matching` 可以从 AST 里识别 whole-pattern
捕获。收集阶段会临时把它注册到其他 kind 数组中，用于发现同名冲突；随后
`cleanup_temporary_pattern_metavars` 会移除这些临时项，并返回单独的
`pattern_metavars` 列表供 guard 校验使用。

Metavar 数组保持首次出现顺序。若干测试会断言这个顺序，不要把这些数组排序当作清理。

## 保留名称

Inline 声明不能使用：

- 只由两个或更多下划线组成的名称，例如 `__` 或 `___`
- `__TARGET__`
- `__SOURCE__`

全下划线名称是 matcher 的忽略占位符。`__TARGET__` 保留给 structural
`inside-expr` 遍历，`__SOURCE__` 保留给 taint sink 和 sanitizer target 选择。

仅仅以下划线开头的名称，例如 `__moongrep_value`，并不是保留名称，除非它正好是上面的内置名，
或完全由下划线组成。

## Structural Rule

`compile_structural_rule` 会在存在 `inside-expr` 时先编译它。

`inside-expr` shape 会被编译成普通 pattern，并使用：

- 无 guard
- `target_metavar = Some("__TARGET__")`
- `source_metavar = None`

它必须包含恰好一个由 `count_supported_name_in_node` 统计到的 `__TARGET__` 名称。
运行时 matcher 只会在完整表达式位置特殊处理 target/source metavar，因此修改 supported-name
统计时必须同时检查 `matching` 行为。

`inside-expr` 中声明的 metavar 在匹配目标表达式时可见，但内部的 `patterns` 和
`patterns-not` 必须重复相同 inline 形式才能复用该绑定。
`ensure_inherited_inside_expr_metavar_forms` 会拒绝内部 pattern 用不同 kind
重新声明继承来的名称。

普通 `patterns` 和 `patterns-not` 会在 `inside-expr` 之后独立编译。它们不能包含
`__TARGET__`。

## Guard

`compile_guards` 只接受 key 为 `$` 前缀捕获名、value 能编译成 regex 的 map 项。

Guard 只能引用 `id` 和 `const` 捕获。它不能引用：

- 未知名称
- `exp` 捕获
- `pat` 捕获

这是规则编译器层面的限制。`rule/apply` 中的 guard 求值期望从规范化 identifier
或 constant 中得到类似字符串的值，而不是任意 expression 或 pattern AST。

## Taint Rule

每个 taint source、sink 和 sanitizer shape 都必须编译成顶层 call AST：

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

新增 parser AST 形式支持时：

1. 更新相关 rewrite walker，保证该形式内部的 metavar 会被访问
2. 保留不需要重写的 source AST 字段
3. 添加 `rule/compile` 校验测试，展示新位置可用
4. 检查 `matching` 是否真的能匹配生成的 untyped AST
5. 如果新 AST 携带字面名称或常量，更新 `rule/prefilter`

修改 metavar kind 或位置时：

1. 同时更新收集、解析和重写校验
2. 如果运行时匹配行为变化，更新 matcher 占位符分派
3. 如果新 kind 可以被 guard，更新 guard 校验
4. 为显式语法、bare 推断、重复捕获和冲突诊断添加测试
5. 只有规则作者可见语义变化时才更新公开规则规格

修改 `inside-expr` 行为时：

1. 保持 `__TARGET__` 编译期检查与 matcher 支持一致
2. 对 `patterns` 和 `patterns-not` 都保留继承 metavar 的 kind 检查
3. 测试含 positive pattern、negative pattern 和 negative-only `inside-expr` 的规则
4. 检查 `rule/apply` 的遍历行为

修改 taint target 行为时：

1. 更新 `ensure_taint_call_shape` 或 `require_source_target`
2. 更新 `rule/taint_lowering.target_value`
3. 如果 `__SOURCE__` 匹配行为变化，保持 `taint/INTERNAL.md` 和
   `matching/INTERNAL.md` 的说明同步
4. 添加编译期校验测试和规则应用测试

对于 package-local 的校验工作，`moon test rule/compile` 是最短反馈循环。
对于通过已加载 YAML 规则可见的行为，还要测试 `rule/apply`、`rule/taint_lowering`
以及相关 e2e snapshot。
