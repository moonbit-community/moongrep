# internal/rule/compile 内部说明

`internal/rule/compile` 是模式源码文本与可执行匹配器/规则之间的校验与规范化边界。

## 包职责与公开入口

| 入口 | 输入 | 输出 | 说明 |
| --- | --- | --- | --- |
| `compile_rules(raw_rules)` | `Array[RawRuleSpec]` | `Array[CompiledRule]` | 检查重复 ID、编译规则主体并构造规则级 prefilter。 |
| `compile_expr_pattern(pattern)` | `String` | `matching.CompiledExprPattern` | 直接编译单个普通结构表达式模式，不生成规则元数据、guard 或 prefilter。 |
| `compile_inside_toplevel_pattern(pattern)` | `String` | `matching.CompiledExprPattern` | 按默认 `inside-toplevel` 模式（函数默认 `partial`）与 `__TARGET__` 校验编译单个顶层模式；不接受 guard 或显式 match mode。 |

本包负责：

- 重复 rule ID 检查。
- 将普通 `shape` 解析为 MoonBit 表达式，将 `inside-toplevel` 的 `shape` 解析为
  单个顶层项。
- 记录元变量、校验其在 CST 中的位置，并拒绝保留名与非法 guard。
- 记录污点 sink 与 sanitizer 的 target 元数据。
- 基于编译后的规则定义构建源码文本 prefilter。

其他职责归属：运行时匹配（`internal/matching`）、guard 求值与扫描
（`internal/rule/apply`）、污点 lowering（`internal/rule/taint_lowering`）及
预过滤求值（`internal/rule/prefilter`）。

## 主编译流程

1. `compile_rules` 先调用 `ensure_unique_rule_ids`，再对每条原始规则执行
   `compile_rule`：
   - 结构规则走 `compile_structural_rule`。
   - 污点规则走 `compile_taint_rule`。
   - `compile_rule_prefilter(definition)` 从编译后的 CST 提取必需字面量（必须
     基于编译结果而非原始 YAML，因为元变量此时已完成分类并可被排除）。
2. `compile_expr_pattern` 构造匿名 `patterns[0]` 上下文并调用
   `compile_structural_expr_pattern`（解析、元变量分类、禁止 `__TARGET__`、
   构造 matcher pattern）。调用方可另行通过 `internal/rule/prefilter` 生成单模式
   prefilter。
3. `compile_inside_toplevel_pattern` 构造 `inside-toplevel[0]` 上下文，要求恰好
   一个可绑定表达式位置的 `__TARGET__`，向 matcher 注册它，并将函数默认模式解析
   为 `partial`。
4. `compile_structural_rule` 先经 `compile_inside_toplevel_patterns` 编译顶层
   备选项（在 `inside-toplevel[index]` 诊断路径下按 match mode 确定忽略字段），
   再将外层 shape 交给 `compile_structural_group`，结合 `compile_metavar_shape`
   和 `structural_visible_shapes` 递归编译 `patterns`、`patterns-not` 和嵌套
   `then` 组。

## 模式解析

- `collect_shape_metavars` 以 `comment = true` 和 `enable_metavar = true` 运行
  lexer，记录每个元变量 token 的原始 span 和逻辑语法。
- `parse_shape` 调用 `@untyped_cst.parse_expression(..., enable_metavar=true)`；
  `parse_toplevel_shape` 调用
  `@untyped_cst.parse_structure(..., enable_metavar=true)` 并要求
  `@cst.toplevel_nodes` 恰好返回一个节点。元变量语法直接保留在 parser 的
  `CstNode` 中，不再做标识符替换或二次树转换。
- **插值**：外层 lexer 会把字符串/字节插值作为单个聚合 token 输出；收集器遍历
  CST，以全局起始偏移、`is_interpolation = true` 和 `enable_metavar = true`
  对每个 `InterpSegment_Source` 做子词法分析。parser 在构造片段 `expr` 子树
  （含嵌套插值）时同样透传 metavar 模式。
- **类型名**：`Type_Name` 必须以大写标识符 token 开头，因此显式 `type` 元变量和
  带 `type` 类别的省略号均须大写开头；小写名与关键字名会被 parser 拒绝。
- **诊断顺序**：词法错误优先于解析错误。`InvalidMetavarSyntax` 给出专用提示，
  引导 `$exp:value` 等旧写法迁移到 `$(value:exp)`。解析失败按子句报告
  `"not a valid MoonBit expression"` 或 `"not a valid MoonBit top-level item"`。
  即使 parser 未产生诊断，recovery 节点（`Missing`、`Error`）也会被拒绝。

## 元变量上下文、推导与注册表

元变量编译按记录的源码 span 在只读 CST 中定位每个出现位置，并从节点路径推导
上下文（expression、identifier、pattern、type、whole-argument、binder-only、
qualified-name、ordered-list）。

### 保守的裸名称推导规则

1. 显式声明为 `pat`、`exp`、`id`、`const`、`arg` 或 `type` 的名称保持该类别。
2. 裸标识符位置推导为 `id`。
3. 裸类型位置推导为 `type`。
4. 裸 pattern 变量位置不能单独完成推导（因在 `id`/`const`/`pat` 间有歧义而报错）。
5. 裸表达式位置仅在前述规则均未决定该名称时推导为 `exp`。
6. `const`、`arg` 和 `pat` 绝不从裸 `$name` 自动推导。

该顺序使 `$counter` 等重复裸名称能从循环 binder 推导为 `id` 并在后续表达式中
复用，同时拒绝有歧义的 `$item => body`。

### 支持的内联类别与保留名

- **类别**：`exp`（完整裸标识符表达式）、`id`（标识符、binder、标签、构造器、
  类型名、限定名后缀）、`const`（完整裸标识符表达式或简单 pattern 变量）、`arg`
  （完整裸调用参数槽）、`pat`（简单 pattern 变量）、`type`（完整 CST 类型节点）。
- **注册表顺序**：普通表达式模式按首次出现顺序保存；顶层函数模式保留参数 `id`
  元变量排在其他 `id` 之前的既有优先级，不要将其当作清理项排序。
- **保留名**：精确的 `$_`、`__TARGET__` 和 `__SOURCE__` 不能用作内联元变量名，
  限定通配符位置会在校验阶段被拒绝。仅以下划线开头的普通名（如
  `__moongrep_value`）不是保留名。

## 结构规则组与 Guard

- `StructuralRuleSpec` 包含可选有序 `inside_toplevel` 与递归
  `StructuralPatternGroupSpec`。每个正向 `StructuralPatternSpec` 持有原子
  `RulePatternSpec` 与可选 `then_body`；负向条目保持原子。编译后采用对应递归
  类型。
- 编译按组独立下降：
  - 带 `then` 的 shape 要求一个可绑定 `__TARGET__`；叶子和负向条目禁止出现它。
  - 当前 shape 的本地注册表与祖先可见环境分离：后代可按相同类别（含省略号类别）
    复用祖先名，guard 可直接读取祖先 `id`/`const` 而无需本地声明，新名称局限于
    自身分支。
  - 对 `inside-toplevel`，可见环境保留所有备选项，确保深层 shape 或 guard 引用
    的继承变量在每个备选项中均存在且类别一致。
  - 负向模式按组推导：根级负向剪枝；嵌套 `then` 与 `inside-toplevel` 拒绝未覆盖
    负向。
  - guard 使用可见环境编译；matcher 仅使用当前 shape 的注册表。
- **Guard（`compile_guards`）**：要求键带 `$` 前缀且值为合法正则，且仅允许引用
  `id` 和 `const` 捕获（拒绝未知名、`exp`、`arg`、`pat`、`type` 与省略号，因为
  `internal/rule/apply` 只对规范化字符串求值）。

## 污点规则

- 所有 `source`、`sink`、`sanitizer` 的 shape 都必须编译为 `Expr_Apply` 或
  `Expr_DotApply`。
- `sources` 禁止包含 `__SOURCE__`。
- `sinks` 和 `sanitizers` 必须恰好包含一个 `__SOURCE__`，且必须占据整个 receiver
  或单个参数的完整值（嵌套写法如 `sink(wrap(__SOURCE__))` 会被拒绝，因为
  lowering 需要直接从 `CallInfo` 选取已求值的结果）。
- `require_source_target` 将目标记录为 `Receiver`、`PositionalArg(index)` 或
  `LabelledArg(label, index)`（同时保存标签与下标，以便 lowering 确认精确的标签
  参数槽）。

## 集成边界与维护清单

共享占位符语义的包：

- `internal/rule/compile` — 解析并校验内联语法、`__TARGET__` 与 `__SOURCE__`。
- `internal/matching` — 实现运行时占位符匹配与绑定。
- `internal/rule/prefilter` — 从必需字面量中排除匹配器占位符。
- `internal/rule/taint_lowering` — 消费编译后的 `TaintTarget` 元数据。
- `internal/rule/apply` — 在结构匹配成功后执行编译后的 guard。

用户可见规则语义变动时，须同步更新 `internal/docs/RuleSpec.md` 与
`internal/docs/RuleSpec_CN.md`。

### 维护核对清单

- **新增 parser CST 形式**：更新出现位置上下文分类；直接保留 parser `CstNode`；
  添加编译校验测试；确认 `matching` 可正确匹配；若携带字面名称或常量则同步更新
  `prefilter`。
- **修改元变量类别或位置**：同步更新收集、解析与校验；按需更新 matcher 分派与
  guard 校验；覆盖显式语法、裸推导、重复捕获与冲突诊断测试。
- **修改 inside-context 行为**：保持 `__TARGET__` 编译检查与 matcher 一致；为
  `patterns` 和 `patterns-not` 保留继承类别检查；维持有序首项选择语义（guard
  失败可继续，外层一旦选中不回退）；覆盖正向、负向及纯负向组；核对 `apply` 分桶
  与 `prefilter` 的外层×内层组合。
- **修改污点 target 行为**：同步 `ensure_taint_call_shape` /
  `require_source_target` 与 `taint_lowering.target_value`；保持
  `internal/taint/INTERNAL.md` 与 `internal/matching/INTERNAL.md` 同步；添加编译
  与规则应用测试。

修改校验逻辑后运行 `moon test internal/rule/compile`；影响 YAML 规则行为时一并运行
`internal/rule/apply`、`internal/rule/taint_lowering` 及相关端到端快照测试。
