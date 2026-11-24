# internal/rule/prefilter 内部说明

`internal/rule/prefilter` 为编译后的规则和独立表达式模式构造并执行保守的源码文本
预过滤器，在必需字面量缺失时提前跳过解析与匹配。

## 包职责与安全性不变量

预过滤发生在解析和 CST 匹配之前：

- **允许假阳性**（例如字面量仅出现在注释、字符串或无关表达式中），后续 CST 匹配
  会将其排除。
- **严禁假阴性**：

> 如果对应规则分支能在待搜索源码切片中产生 finding，则至少有一个备选项中的全部
> 字面量必然逐字出现在该切片中。

由于字面量提取依赖已分类的元变量、保留占位符和忽略字段，`internal/rule/compile`
只在构造完 `CompiledRuleDefinition` 后调用 `compile_rule_prefilter`。已经持有单个
`CompiledExprPattern` 的调用方可直接调用 `compile_expr_pattern_prefilter`，无需
构造虚拟规则。

## 表示与求值

`RulePrefilter.alternatives` 采用析取范式（外层 OR、内层 AND）：

```text
[
  ["wrapper", "first_target"],
  ["wrapper", "second_target"],
  ["container", "first_target"],
  ["container", "second_target"],
]
```

`prefilter_matches_with_literal_matcher` 按短路方式求值：

- **外层数组为 OR**，**内层数组为 AND**（不要求字面量顺序或源码位置）。
- **空外层数组返回 `true`**，**任意空内层数组也返回 `true`**（无可用必需字面量
  时的保守回退）。
- `prefilter_matches_source` 使用区分大小写、无锚点的普通子串匹配
  `String::contains`（`+`、`(`、`.` 等正则字符无特殊含义）。
- 回调式接口将布尔逻辑与文本搜索解耦，`internal/rule/apply` 得以注入
  `StringView::contains` 与单次调用级 `Map[String, Bool]` 缓存，使多条规则共享的
  字面量只搜索一次。

## 备选项构造规则

| 规则 / 模式类型 | 备选项构造方式 | 排除项（不收集字面量） |
| --- | --- | --- |
| 独立 `CompiledExprPattern` | 单个备选项：`required_literals(pattern)`（全元变量时为空）。 | 所有占位符 |
| 结构规则 | 每条根到叶的正向路径生成一个备选项（路径内 AND，路径间 OR，保序去重）。存在 `inside-toplevel` 时与正向路径取笛卡尔积。仅含负向模式的 `then` 不增加子层要求。 | `patterns-not`、`guard`、占位符、忽略字段 |
| 污点规则 | `sources` 与 `sinks` 的笛卡尔积：`required_literals(source) + required_literals(sink)`。 | `sanitizers`、`__SOURCE__`、占位符 |

结构执行补充：`ScanPlan` 会为每个 group 递归建立正负 CST 分桶（合并保持原 YAML
下标）；只有 `shape`/`guard`/`then` 完整成功才剪枝正向子树；无负向约束的存在性
扫描在首个成功处停止，含负向约束时须检查所有未覆盖区域后才成功；报告使用根条目
下标和位置。

## 必需字面量提取

`required_literals_from_compiled_pattern` 遍历编译后的 `@untyped_cst.CstNode`
（而非原始 YAML），与 `matching` 保持一致：

- **名称**（`@cst.normalized_name` — 变量、binder、标签、accessor、构造器、类型
  名）：
  - 非限定名贡献其保存拼写。
  - 限定名将包/类型前缀与最终标识符**分别**作为字面量（绝不合成 `@pkg.name`，
    因为 MoonBit 允许点号前出现空白，如 `@pkg .name`）。各分量独立检查占位符，
    因此 `@pkg.$(callee:id)` 仍会要求固定分量 `pkg`。
- **常量与文本**：
  - `bigint`、`byte`、`bytes`、`char`、`double`、`float`、`int64`、`regex`、
    `string`、`uint`、`uint64` payload（忽略空字符串）。
  - 保存拼写长度 `>= 2` 的整数 payload（单字符整数锚点过弱，有意忽略）。
  - 布尔常量（`true` / `false`）。
  - 字符串插值的字面片段与多行字符串文本片段。
- **递归**：未单独处理的非叶节点递归遍历子节点（包括 parser 提供的插值 `expr`
  子树，保留元变量周围的固定字面量）。裸叶 token 与 CST 节点名不会成为字面量。

### 占位符、忽略字段与文档注释

- `is_filter_placeholder` 排除 `MetavarRegistry` 中所有单节点、省略号、通配符及
  特殊表达式占位符。仅精确 `$_` 具有拼写通配语义；`__` 等普通全下划线标识符仍是
  必需字面量。
- `CompiledExprPattern.ignored_fields` 仅在父节点 `NodeKind` 与子字段名同时匹配
  时跳过，与 `partial` `inside-toplevel` 函数匹配一致，避免省略的默认函数头字段
  进入 prefilter。
- `@cst.semantic_children` 在收集前移除 docstring，因此任何模式下都不会要求
  docstring 文本。

## 运行时调用方

| 调用方 | 过滤粒度 | 缓存与说明 |
| --- | --- | --- |
| `internal/rule/apply` | 对 `StringView` 执行 `ScanPlan::filter_source` | 单次调用内结构与污点条目共用一个 `Map[String, Bool]` 缓存；对已过滤计划继续针对更小切片过滤是安全的，不修改原计划。 |
| `internal/cli` | 先整文件，再逐个 `///|` 源码块 | 在解析前跳过无关文件或源码块（无关的语法错误块不会产生解析诊断）。 |
| `query` | 先完整源码，再逐个顶层项切片 | 缓存独立模式 prefilter；`captures_from_cst` 无源码文本，直接绕过预过滤。 |

## 维护清单

原则：移除锚点或保留空备选项始终是保守安全的（仅可能影响性能）；新增或加强锚点
必须验证其对所有语法拼写均满足逐字文本不变量。

- **新增占位符或元变量类别**：更新 `is_filter_placeholder`；添加编译到预过滤的测试
  验证替换源码仍保持相关；同步检查 `internal/matching/INTERNAL.md` 与
  `internal/rule/compile/INTERNAL.md`。
- **新增或修改 CST 形式**：仅在满足逐字文本不变量时添加专用收集分支，否则依赖子
  节点递归；分别测试字面量与元变量形式。
- **修改规则组合方式**：保留正确笛卡尔积；保持负向模式、guard 与 sanitizer 不参与
  必需字面量；覆盖空字面量分支与备选项数量；同时测试 `prefilter_matches_source`
  与 `ScanPlan::filter_source`。

改动后运行 `moon test internal/rule/prefilter`；涉及编译或扫描时一并运行
`compile`、`apply`、`query` 及端到端测试。
