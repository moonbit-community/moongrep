# rule/prefilter 内部说明

本文记录修改 `rule/prefilter` 包时容易遗漏的实现细节。

## 包职责

`rule/prefilter` 为编译后的规则和独立编译的表达式 pattern 构造并执行保守的源码
文本筛选。

筛选发生在解析和 CST 匹配之前。它只判断源码文本是否包含某个规则分支每次成功匹配时
都必需出现的字面量。返回 false 时，调用方可以跳过该规则；返回 true 只表示该规则仍是
候选项。

因此，这个包可以接受假阳性，例如字面量只出现在注释、字符串或无关表达式中；但它不能
引入假阴性。它不解析源码、不比较 CST 结构、不执行 guard，也不分析 taint 数据流。

`rule/compile` 只会在构造好 `CompiledRuleDefinition` 后调用
`compile_rule_prefilter`。这个顺序很重要：只有编译后的 pattern 才包含安全提取
字面量所需的规范化 CST、metavar 集合、保留的 target/source 占位符和 matcher
忽略字段。

已经持有单个 `CompiledExprPattern` 的调用方使用
`compile_expr_pattern_prefilter`。它复用同一套字面量提取逻辑，只构造一个备选项，
不需要合成虚拟规则。

## 表示与求值

`RulePrefilter.alternatives` 表示“析取的合取”：

```text
[
  ["wrapper", "first_target"],
  ["wrapper", "second_target"],
  ["container", "first_target"],
  ["container", "second_target"],
]
```

只要任意一个内层数组里的所有字面量都出现在待搜索源码中，这个例子就仍然相关。
字面量顺序及其在源码中的位置没有影响。

`prefilter_matches_with_literal_matcher` 实现这套逻辑，并在找到首个成功备选项或
某个失败字面量时短路：

- 外层数组是 OR
- 每个内层数组是 AND
- 空外层数组返回 `true`
- 任何空内层数组也会让结果返回 `true`

两种空值行为都是有意保留的保守回退。它们表示没有可用的必需文本，因此不能安全排除
该规则。

`prefilter_matches_source` 提供基于 `String::contains` 的 matcher；
`rule_is_relevant_to_source` 是该入口面向编译后规则的包装。
匹配区分大小写、不要求边界，并按普通文本处理。`+`、`(`、`.` 等正则元字符没有
特殊含义。

基于回调的入口把布尔求值和文本搜索分开。`rule/apply` 会用
`StringView::contains` 及一次筛选调用内的字面量缓存来调用它，因此多个规则共享的
同一字面量在该次调用中只搜索一次。

## 独立表达式 Pattern 编译

`compile_expr_pattern_prefilter` 从一个 `CompiledExprPattern` 提取必需字面量，并把
它们保存为唯一备选项：

```text
alternative(pattern) = required_literals(pattern)
```

只含 metavar 的 pattern 会生成空内层备选项，因此对任何源码都保持相关。这与编译后
structural rule 中不可筛选 pattern 的保守行为相同。

## Structural Rule 编译

`compile_structural_prefilter` 只从正向要求推导备选项。

没有 inside context 时，每个正向 `patterns` 条目生成一个备选项：

```text
alternative(pattern) = required_literals(pattern)
```

存在 `inside-expr` 或 `inside-toplevel` 时，每个 inside 备选项会和每个正向
pattern 组合：

```text
alternative(inside, pattern) =
  required_literals(inside) + required_literals(pattern)
```

这是笛卡尔积。不能把所有 inside 和内部 pattern 的字面量压成一个合取，否则会错误地
同时要求来自互斥分支的字面量。

当含 inside context 的规则没有正向 pattern 时，每个 inside pattern 仍会独立生成
一个备选项。这样可以支持由 inside context 加 `patterns-not` 组成的规则。既没有
inside context 也没有正向 pattern 的规则会生成空外层数组，并在任何源码中保持相关。

`patterns-not` 永远不会贡献必需字面量。负向 pattern 描述的是“出现后可能拒绝一次
structural 匹配”的文本，它并不是产生 finding 的必要条件。Guard 和
`patterns-not-mode` 同样不会添加源码锚点。

规则编译器会拒绝同时含 `inside-expr` 和 `inside-toplevel` 的 definition；
prefilter 假定这个不变量成立。对于合法的编译结果，它使用非空的 inside context
集合，并按上述方式与正向 pattern 组合。

每个备选项内部会去除重复字面量，同时保持首次出现顺序。不同备选项之间的重复项会保留，
因为这些备选项仍是互相独立的分支。

## Taint Rule 编译

`compile_taint_prefilter` 会构造 taint source 和 sink 的笛卡尔积：

```text
alternative(source, sink) =
  required_literals(source.pattern) + required_literals(sink.pattern)
```

一次 taint finding 需要某个 source 和某个 sink，因此所选 source/sink 对要求的
字面量可以作为安全的粗粒度前置条件。这个检查不会判断求值顺序、作用域、数据流，也不会
判断 sink 是否真的接收了 source 的值。

Sanitizer 会被有意排除。Taint finding 不要求 sanitizer 出现；若强制要求其文本，
反而会丢弃规则本来需要报告的未净化路径。

如果 source 或 sink pattern 没有产生字面量，对应的空备选项或部分备选项会保持保守
行为。编译后的 `__SOURCE__` 占位符会在收集字面量时排除。

## 必需字面量提取

`required_literals_from_compiled_pattern` 遍历编译后的
`@untyped_cst.CstNode`，而不是原始 YAML shape。这样字面量提取才能与
`matching` 实际使用的 CST 保持一致。

收集器识别 `@cst.normalized_name` 暴露的所有名称节点，包括 variable、binder、
label、accessor、constructor 和 type name。非限定名贡献保存的源码拼写；限定名把
package/type 前缀和最终 identifier 分别作为字面量。

限定名不会贡献拼接出来的 `@pkg.name` 字面量。MoonBit 允许点号前出现空白，因此同一
CST 名称在匹配源码中可能写成 `@pkg .name`。分别要求源码包含保存的 `pkg` 和 `name`
分量，对两种拼写都保持保守。每个分量还会独立检查 matcher placeholder，所以
`@pkg.$(callee:id)` 只要求固定的 `pkg` 分量。

收集器还会识别：

- bigint、byte、bytes、char、double、float、int64、regex、string、uint 和
  uint64 常量 payload
- 保存形式长度至少为两个字符的整数 payload
- 转成 `true` 或 `false` 的布尔常量
- 字符串插值中的字面片段
- 多行字符串的文本片段

单字符整数形式会有意忽略，因为它们是很弱的锚点。这里检查的是保存形式的长度，不是数值
大小。空字符串也会忽略。

未单独识别的非 leaf 节点会递归遍历。裸 leaf 节点本身不会成为字面量，因此 CST kind
名称和结构标点不会变成源码要求。字符串插值表达式（包括包含 metavar 的表达式）会
通过 parser 提供的 `expr` 子树正常递归访问，因此不需要单独解析也能保留 metavar
周围的固定字面量。

## 占位符与忽略字段

当 matcher 可以用任意源码替换某个名称时，就不能收集这个名称。
`is_filter_placeholder` 会排除：

- 编译后 pattern 的 `MetavarRegistry` 能解析出的所有单节点、ellipsis、wildcard
  和特殊表达式占位符

只有精确的 `$_` 具有由拼写决定的下划线占位语义。`__` 这类普通全下划线标识符仍是
必需字面量。

`CompiledExprPattern.ignored_fields` 也是安全性约定的一部分。遍历子节点时，只有
parent `NodeKind` 和 child name 都与 ignored-field 条目一致才会跳过该字段。
这与结构匹配保持一致，尤其适用于 partial `inside-toplevel` 函数 shape：其中省略的
visibility、attribute、parameter、return type 等默认字段不能成为 prefilter 要求。
显式写出的语义字段仍可贡献字面量。

Docstring 则由 `@cst.semantic_children` 在字面量收集前统一移除，所以它的文本在
default、exact 或 partial 模式中都不会成为必需字面量。候选源码注释仍可能满足某个
无关的必需文本搜索；这是保守假阳性，最终 CST matcher 会将其排除。

修改 `matching` 或 `rule/compile` 的占位符、忽略字段行为时，必须在同一个改动中
同步 prefilter。

## 运行时调用方

主要调用方会在不同粒度上执行同一个编译后的布尔表达式：

- `rule/apply` 用 `StringView` 筛选 `ScanPlan` 条目。每次
  `ScanPlan::filter_source` 调用都会创建一个由 structural 和 taint 条目共享的
  `Map[String, Bool]` 缓存。
- CLI 先筛选整个文件，再在解析前筛选每个 `///|` 源码块。因此，不相关且格式错误的
  文件或源码块可以在 parser 产生诊断前被跳过。
- `query` 会编译并缓存独立 pattern prefilter，先筛选完整源码，再筛选每个顶层项的
  源码切片，然后才遍历 CST。`captures_from_cst` 没有源码文本，因此会绕过
  prefilter。

继续筛选一个已经过滤过的 `ScanPlan` 是安全的：它只会针对更小的源码切片移除更多条目，
不会修改原始 plan。

## 安全性不变量

返回 `false` 可能阻止解析及后续全部规则求值。因此，每个被收集的字面量都必须满足：

> 如果对应规则分支能在待搜索源码切片中产生 finding，这个字面量就一定逐字出现在同一
> 切片中。

添加锚点前必须检查这个蕴含关系的两端，尤其要注意：

- 不要要求负向 pattern、guard 或 sanitizer 中的字面量
- 不要要求任何 matcher 占位符的拼写
- 不要使用结构匹配已经忽略的字段
- 不要从 CST 推导可能与原始源码拼写不同的文本
- 组合备选项时保留原有分支结构

移除锚点或把备选项变为空是保守操作：可能损失性能，但不会隐藏 finding。新增锚点或加强
合取条件时，需要为它覆盖的每种语法形式添加聚焦测试。

## 维护清单

新增 matcher 占位符或 metavar kind 时：

1. 更新 `is_filter_placeholder`
2. 添加从规则编译到 prefilter 的测试，证明替换后的源码仍然相关
3. 检查 `matching/INTERNAL.md` 和 `rule/compile/INTERNAL.md` 中的同一占位符约定

新增或修改 untyped CST 形式时：

1. 判断它是否携带一次成功匹配必需的源码拼写
2. 只有满足逐字文本不变量时才添加专门的 collector 分支
3. 否则依赖递归子节点遍历
4. 分别测试固定字面量形式和 metavar 形式

修改 structural 或 taint 规则组合方式时：

1. 保留正确的笛卡尔积备选项
2. 继续把负向 pattern 和 sanitizer 排除在必需字面量之外
3. 覆盖空字面量分支和备选项数量
4. 同时测试直接的 `rule_is_relevant_to_source` 行为和
   `ScanPlan::filter_source` 集成

对于 package-local 修改，`moon test rule/prefilter` 是最短反馈循环。若修改影响规则
编译或扫描行为，还应运行相关的 `rule/compile`、`rule/apply`、`query` 和端到端测试。
