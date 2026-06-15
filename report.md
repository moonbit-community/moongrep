# Metavar 运行时自动归一化方案分析

## 背景

当前规则系统把 `metavar` 显式分成两类：

- `subtree`: 绑定匹配到的 parser AST 节点。
- `identifier`: 绑定归一化后的名字字符串。

这个模型体现在 `matching/context.mbt` 的 `CompiledExprPattern` 和
`BoundValue` 上。`subtree_metavars` 和 `identifier_metavars` 是两组独立
数组，`BoundValue` 同时支持 `Expr`、`Var`、`Binder`、`Pattern`、`Label`
和 `Identifier(String)`。

运行时匹配时，`subtree` 和 `identifier` 的分支目前是分开的：

- `Expr::Ident` 占位符如果在 `subtree_metavars` 中，就绑定
  `Expr(candidate)`。
- 同一位置如果在 `identifier_metavars` 中，则要求 candidate 可以通过
  `normalize_identifier_name_from_expr` 归一化，否则匹配失败。
- `Var`、`Binder`、`Pattern::Var`、`Label` 位置也有类似分支。

因此当前 `subtree` 的重复绑定语义是“同一种 AST kind 再做相等比较”，
而 `identifier` 的重复绑定语义是“归一化名字字符串相同”。

用户提出的新思路是：仍然在运行时判断。如果一个 metavar 匹配成功的候选
内容是 `Var`、`Binder`、`Expr::Ident`、`Pattern::Var`、`Label`，就自动
归一化为 `Identifier(String)`；否则按原 AST 节点绑定。

## 方案语义

准确地说，这个方案不能完全等到“整次匹配成功之后”再做归一化，因为重复
metavar 的后续出现依赖第一次绑定结果。如果第一次绑定仍保存为 `Binder`
或 `Expr`，第二次出现仍会在 `bound_value_equal` 里因为 variant 不同而失败。

实际可实现的语义应是：

1. 每次准备绑定一个 metavar 时，先看候选节点是否是 name-like 节点。
2. 如果是可归一化的 name-like 节点，绑定为 `BoundValue::Identifier(name)`。
3. 如果不可归一化，或者候选不是 name-like 节点，则继续绑定原 AST 节点。
4. 重复绑定仍通过 `bind_value` 和 `bound_value_equal` 判定一致性。

这里的 name-like 节点建议严格限定为当前 `ident/normalize.mbt` 已经支持的范围：

- `Expr::Ident`，且内部 `Var` 是简单 `LongIdent::Ident`。
- `Var`，且是简单 `LongIdent::Ident`。
- `Binder`。
- `Pattern::Var`。
- `Label`。

这意味着 `@pkg.name` 这样的 package-qualified `Var` 不会被自动归一化，仍保留
为 AST 节点绑定。这和当前 `identifier` 语义一致。

## 能解决的问题

这个方案主要解决“同一个逻辑名字跨 AST kind 出现”的重复绑定问题。

典型例子是：

```moonbit
for counter = 0; counter < limit; counter = counter + 1 { body }
```

当前如果 `counter` 声明成 `subtree`，第一次可能绑定为 `Binder`，后续使用
可能绑定为 `Expr` 或 `Var`，重复比较会失败。规则作者必须知道这里应该写：

```yaml
metavars:
  subtree: [limit, body]
  identifier: [counter]
```

自动归一化后，如果 `counter` 作为普通 `subtree` 或新语义 metavar 出现，
运行时会把 binder 和 later use 都归一化成同一个 `Identifier("i")`，从而
自然匹配。

同类收益还包括：

- 字段名和标签名重复出现时可以按名字比较。
- 方法名、labelled argument、field accessor 等 label-like 位置可以和同名
  identifier 建立一致性。
- 规则作者不必频繁判断一个名字在 parser AST 中到底是 `Binder`、`Var`、
  `Expr::Ident` 还是 `Label`。

## 关键影响

### 1. `subtree` 的语义会变宽

如果直接修改现有 `subtree` 行为，现有含义会从：

> 捕获 AST 节点，并要求重复出现时 AST kind 和结构相等。

变成：

> 捕获 name-like 节点时按名字比较；捕获非 name-like 节点时按 AST 比较。

这会让一些过去失败的规则开始成功。例如 `Binder("x")` 和
`Expr::Ident("x")` 过去不是同一种 `BoundValue`，现在都会变成
`Identifier("x")`。

这是易用性提升，但也是行为变更。它可能引入新的命中，特别是在 label 名、
method 名、field 名、局部变量名同名但语义不属于同一个命名空间时。

### 2. `identifier` 仍然不能完全删除

自动归一化不是 `identifier` 的严格替代品。

当前 `identifier` 有一个额外约束：候选必须能归一化成名字，否则匹配失败。
这能表达“这里必须是一个名字”的规则。

如果只做自动归一化并保留 fallback 到 AST 节点，下面这种规则仍会匹配复杂
表达式：

```yaml
patterns:
  - shape: f(x)
    metavars:
      subtree: [x]
```

它依然应该匹配 `f(a + b)`，只不过 `x` 绑定为 `Expr(a + b)`。而如果规则作者
想表达 `f(x)` 只能匹配简单 identifier 参数，就仍需要 `identifier: [x]`，或
需要一个新的严格 name-only 语义。

所以该方案最多减少“什么时候该用 identifier 做重复名字比较”的心智负担，
不能彻底取消手动声明或取消 `identifier`。

### 3. `__TARGET__` 必须排除

`inside-expr` 依赖 `__TARGET__` 绑定为 `BoundValue::Expr`。`rules/apply.mbt`
中后续代码明确检查：

```moonbit
Some(@matching.BoundValue::Expr(target)) => ...
```

如果 `__TARGET__` 放在一个简单 identifier 表达式位置并被自动归一化成
`Identifier`，`inside-expr` 会不再进入 target traversal，导致规则失效。

因此特殊占位符必须保留现有行为：

- `target_metavar == Some("__TARGET__")` 时始终绑定 `Expr(candidate)`。
- `source_metavar == Some("__SOURCE__")` 也建议保持 `Expr(candidate)`，即使当前
  taint lowering 主要通过已编译的 `TaintTarget` 读取目标。

### 4. `__SOURCE__` 建议也排除

taint 规则中 `__SOURCE__` 是 sink/sanitizer 目标，占位符必须是整个 receiver
或整个 argument value。虽然当前 `rules/taint_lowering.mbt` 不依赖 bindings
读取 `__SOURCE__`，而是根据 `TaintTarget` 从 `CallInfo` 取值，但让它保持
`Expr` 绑定能避免未来复用 bindings 时出现不一致。

### 5. 行为变化不一定体现在 public API diff

如果只改现有 `subtree` 的运行时绑定逻辑，不改 `CompiledExprPattern` 和
`RulePatternSpec` 字段，`pkg.generated.mbti` 很可能没有变化。但外部可观察
行为会变化：同一套 YAML 规则可能命中更多位置。

这类变化比 API diff 更隐蔽，需要靠行为测试和文档说明控制风险。

## 修改代价

### 方案 A：直接改变现有 `subtree` 行为

这是代码改动最小，但兼容性风险最高的方案。

需要修改的主要位置：

- `matching/matching.mbt`
  - 增加一个私有 helper，例如 `auto_normalize_bound_value`。
  - 在 `subtree_metavars` 分支里调用该 helper。
  - 覆盖 `Expr`、`Var`、`Binder`、`Pattern`、`Label` 五类绑定入口。
  - 对 `is_special_expr_metavar` 命中的 `__TARGET__` / `__SOURCE__` 跳过自动归一化。
- `matching/context.mbt`
  - 文档注释需要更新，因为 `subtree` 不再纯粹是“绑定 whole AST nodes”。
- `docs/RuleSpec.md`、`docs/rule_spec.mbt`、`docs/WritingRules.md`、
  `docs/writing_rules.mbt`
  - 需要说明 `subtree` 的 mixed binding 行为。
  - 需要强调 `identifier` 仍是 strict name-only。
- 测试
  - 更新或新增 `matching/matching_test.mbt` 覆盖跨 kind 名字比较。
  - 添加 `__TARGET__` 保持 `Expr` 绑定的 inside-expr 回归测试。
  - 添加 `__SOURCE__` 的 sink/sanitizer 回归测试。

预估代价：

- 实现量：小。
- 文档量：中等。
- 测试量：中等。
- 兼容性风险：中到高。

优点：

- 不改 YAML schema。
- 不改 public struct 字段。
- 规则作者继续只看到 `subtree` / `identifier` 两类。

缺点：

- `subtree` 名字变得不准确。
- 现有规则可能静默多报。
- 想要严格 AST-kind 比较的规则不再有稳定语义，除非再引入新的 strict 模式。

### 方案 B：新增第三类 `auto`

新增一种显式 bucket：

```yaml
metavars:
  auto: [counter]
```

语义：

- `subtree`: 保持当前严格 AST 捕获。
- `identifier`: 保持当前 strict name-only 捕获。
- `auto`: name-like 候选归一化，否则按 AST 捕获。

需要修改的主要位置：

- `rules/spec.mbt`
  - `RulePatternSpec` 增加 `auto_metavars` 字段。
- `matching/context.mbt`
  - `CompiledExprPattern` 增加 `auto_metavars` 字段。
- `rules/load.mbt`
  - `metavars` allowed keys 增加 `auto`。
  - 解析第三个 bucket。
  - 校验三组 bucket 两两 disjoint。
- `rules/compile.mbt`
  - validate declared/used metavars 时包含 `auto_metavars`。
  - inside-expr 可见 metavars 也要包含 `auto_metavars`。
  - inner pattern 不允许重声明来自 inside-expr 的 auto 名字。
  - `compile_pattern_with_effective_metavars` 传递第三组数组。
- `matching/matching.mbt`
  - 在各匹配入口增加 `auto_metavars` 分支。
  - 对 `auto` 执行自动归一化 fallback 逻辑。
  - `subtree` 和 `identifier` 分支保持不变。
- `pkg.generated.mbti`
  - `rules` 和 `matching` 的 public interface 会变化，需要 `moon info` 更新。
- 文档和测试
  - RuleSpec/WritingRules 都要增加 `auto` 的 schema 和语义。
  - load/validate/matching/apply 测试都要覆盖。

预估代价：

- 实现量：中等。
- 文档量：中等。
- 测试量：中到高。
- 兼容性风险：低。

优点：

- 不破坏已有 `subtree` 和 `identifier` 语义。
- 规则作者可以逐步迁移。
- 行为变化显式，便于审查。

缺点：

- YAML schema 多一个概念。
- public API 会变，需要同步所有构造 `CompiledExprPattern` 和 `RulePatternSpec`
  的测试或外部调用方。
- 不能实现“完全不用想 bucket”的目标，只是提供更符合直觉的默认选择。

### 方案 C：规则格式 v2 默认 auto

可以引入v2顶层版本，例如：

```yaml
metavars: [counter, value]
```

并让这些未分类 metavars 默认走 `auto`。v1 保持当前 `subtree` / `identifier`
语义。

预估代价：

- 实现量：高。
- 文档量：高。
- 测试量：高。
- 兼容性风险：低到中，取决于 v1/v2 共存策略。

优点：

- 最接近“减少手动声明”的长期目标。
- 旧规则可保持 v1 行为。
- 可以把 schema 设计得更简洁。

缺点：

- 需要版本化规则文件。
- loader、docs、错误信息、示例都要同时支持两套语义。
- 对当前项目阶段来说可能过度。

## 行为示例

### 例 1：跨 kind 名字一致性

规则形状：

```yaml
patterns:
  - shape: |
      for counter = 0; counter < limit; counter = counter + 1 { body }
    metavars:
      auto: [counter]
      subtree: [limit, body]
```

候选：

```moonbit
for i = 0; i < n; i = i + 1 { println(i) }
```

`counter` 在 binder 和 expression use 中都归一化为 `Identifier("i")`，匹配成功。

候选：

```moonbit
for i = 0; j < n; i = i + 1 { println(i) }
```

第二个 `counter` 归一化为 `Identifier("j")`，和第一次绑定的
`Identifier("i")` 不相等，匹配失败。

### 例 2：复杂表达式仍按 AST 捕获

规则：

```yaml
patterns:
  - shape: f(x)
    metavars:
      auto: [x]
```

候选：

```moonbit
f(a + b)
```

`x` 的候选不是 `Expr::Ident`，所以绑定为 `Expr(a + b)`，匹配成功。

这说明 `auto` 不是 strict identifier。如果需要只接受 `f(name)`，仍应使用
`identifier: [x]`。

### 例 3：命名空间混合风险

规则：

```yaml
patterns:
  - shape: object.field + field
    metavars:
      auto: [field]
```

候选：

```moonbit
object.name + name
```

如果 field label 和 identifier use 都归一化成 `Identifier("name")`，规则会
匹配。这个结果可能正是想要的，也可能把字段名和局部变量名两个不同命名空间
混为一谈。

这是自动归一化的核心语义风险。

## 测试影响

无论选择方案 A 还是 B，都建议新增以下测试：

1. `matching` 层测试
   - `Binder` 和 `Expr::Ident` 同名时匹配。
   - `Binder` 和 `Expr::Ident` 不同名时失败。
   - `Label` 和 `Expr::Ident` 同名时的行为按设计固定。
   - `Expr::Ident` 的 package-qualified 候选不自动归一化。
   - 复杂表达式 fallback 为 `Expr`，重复复杂表达式仍走结构相等。

2. `rules` 编译层测试
   - 新 bucket 或新语义的 schema 校验。
   - declared-but-unused 仍被拒绝。
   - 与 inside-expr 外层 metavars 的重声明规则一致。

3. structural apply 测试
   - `inside-expr` 中 `__TARGET__` 匹配简单 identifier 时仍能绑定为 `Expr`
     并继续遍历 target。

4. taint 测试
   - `__SOURCE__` sink 和 sanitizer 仍按 whole receiver / argument value 工作。
   - auto metavar 不影响 source/sink/sanitizer 的 target 定位。

5. 文档快照或示例测试
   - 更新 RuleSpec 和 WritingRules 后，确保 docs package 仍可通过 `moon test`
     和 `moon check`。

## 性能影响

性能影响预计很小。

当前匹配已经在每个候选 AST 节点上进行递归结构比较。自动归一化只是在
metavar 绑定分支中多做一次局部模式匹配和字符串提取。相比 AST 遍历和结构
匹配，这个成本基本是常数级的小开销。

需要注意的是，如果行为变宽导致更多模式进入成功路径，后续规则应用层可能
产生更多 hit，间接增加输出和后处理成本。但这不是归一化 helper 本身的性能
问题，而是语义变更带来的命中数变化。

## 兼容性评估

### 直接改 `subtree`

兼容性风险主要是“静默多匹配”。

旧规则如果本来依赖 `subtree` 的 AST-kind 严格性，例如希望 binder 和
identifier use 不应被视作同一个捕获，改动后可能会命中更多代码。因为规则
文件和 public API 没变，这种变化不容易从 diff 中看出来。

### 新增 `auto`

兼容性风险较低。旧规则行为不变，新规则显式选择 `auto`。代价是 public API
和 schema 都会扩展。

### 版本化 v2

兼容性最可控，但实现和维护成本最高。适合在规则语言继续演化时统一设计，
不适合作为这一个 matcher 改动的第一步。

## 推荐结论

推荐优先采用方案 B：新增 `auto` bucket。

理由：

1. 它准确表达了用户提出的运行时自动归一化语义。
2. 它保留 `subtree` 的严格 AST 捕获能力。
3. 它保留 `identifier` 的 strict name-only 能力。
4. 它避免对现有规则造成静默行为变化。
5. 它为未来规则格式 v2 提供迁移基础。

如果项目更看重短期简化、且可以接受现有规则行为变化，方案 A 的实现更快。
但它会让 `subtree` 名字和语义不再完全匹配，并且会消除一部分 strict AST
equality 的表达能力。除非当前规则生态很小、能够完整审查所有规则命中变化，
否则不建议直接改 `subtree`。

## 推荐的实现切分

若按方案 B 实现，建议分四步：

1. **模型和 loader**
   - 给 `RulePatternSpec` 和 `CompiledExprPattern` 增加 `auto_metavars`。
   - loader 接受 `metavars.auto`。
   - 三个 bucket 做重复和互斥校验。

2. **matcher 语义**
   - 增加 `bind_auto_value` 或 `normalize_auto_bound_value` helper。
   - 在 `Expr`、`Var`、`Binder`、`Pattern::Var`、`Label` 的 auto 分支调用。
   - 保持 `subtree` 和 `identifier` 原语义不变。
   - 明确排除 `__TARGET__` / `__SOURCE__` 的自动归一化。

3. **规则编译和 inside-expr**
   - validate declared/used 包含 auto。
   - inside-expr visible metavars 包含 auto。
   - inner patterns 不可重声明外层 auto 名字。
   - effective metavars 向内层 patterns 传递 auto。

4. **测试和文档**
   - 添加 matcher 语义测试。
   - 添加 rules load/compile/apply 测试。
   - 更新 RuleSpec/WritingRules 及对应 `.mbt` 文档源。
   - 运行 `moon info && moon fmt`，检查 `.mbti` 的 public API 变化是否符合预期。
   - 运行 `moon test` 和 `moon check`。

## 最小实现草图

自动归一化 helper 可以按这个方向设计：

```moonbit
fn auto_value_from_expr(candidate : @syntax.Expr) -> BoundValue {
  match @ident.normalize_identifier_name_from_expr(candidate) {
    Some(name) => Identifier(name)
    None => Expr(candidate)
  }
}

fn auto_value_from_var(candidate : @syntax.Var) -> BoundValue {
  match @ident.normalize_identifier_name_from_var(candidate) {
    Some(name) => Identifier(name)
    None => Var(candidate)
  }
}

fn auto_value_from_pattern(candidate : @syntax.Pattern) -> BoundValue {
  match @ident.normalize_identifier_name_from_pattern(candidate) {
    Some(name) => Identifier(name)
    None => Pattern(candidate)
  }
}
```

`Binder` 和 `Label` 当前总是可以直接得到 name，可以直接生成
`Identifier(candidate.name)`。

注意：如果采用方案 A，helper 会被放进现有 `subtree_metavars` 分支。如果采用
方案 B，helper 只用于 `auto_metavars` 分支。

## 最终判断

运行时自动归一化是可行的，而且能明显改善 metavar 的可用性。关键不是技术
难度，而是语义边界。

最稳妥的设计是把它作为第三种显式语义加入，而不是改变现有 `subtree`。这样
可以同时保留三种能力：

- `subtree`: 精确捕获 AST。
- `identifier`: 强制匹配名字。
- `auto`: 名字型节点按名字比较，其他节点按 AST 捕获。

这三者组合起来，比把所有逻辑合并进 `subtree` 更清晰，也更容易向规则作者
解释和测试。
