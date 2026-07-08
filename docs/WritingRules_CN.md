# 编写规则

`rule/*` packages 定义了 `moongrep` 使用的 YAML 规则格式，以及运行时 loader、validator、compiler 和 applicator。

如果你想新增或调整规则，请从这里开始。

另见：

- [RuleSpec_CN.md](RuleSpec_CN.md)：权威 YAML 规则规范，包含可接受的键、匹配器语义和失败情况

## 介绍

YAML 规则文件是扫描器的输入。规则根目录可以是通过 `--rules` 或 `-r` 传给 `moongrep scan` CLI 的任意目录。以 `.yaml` 或 `.yml` 结尾的文件会在该根目录下递归发现；其他文件会被忽略。发现的文件会按排序后的顺序加载，以得到确定性的输出。空规则根目录是错误。

规则 id 来自规则文件目录加 YAML `id`。例如，当 `rules` 是规则根目录时，`rules/security/raw.yaml` 中的 `id: raw-html` 会变成 `security/raw-html`。直接位于规则根目录下的文件只使用其 `id`。文件名不参与规则 id。YAML `id` 不能为空，且不能包含 `/`；目录归属由文件位置编码。

每个 YAML 文件必须只包含一个文档，且该文档必须是映射。完整规则文件需要字符串字段 `id` 和 `description`，会拒绝未知顶层键，并且选择以下规则模式之一：

- 结构模式：非空 `patterns`，或 `inside-expr` 搭配 `patterns`、`patterns-not`，或两者同时存在
- `taint`：过程内污点建模，编译到 `taint` package

`patterns` 必须是非空数组。未知键会在每个 schema 层级被拒绝：顶层规则键、`taint` 键和规则子句键。

结构规则还可以添加可选顶层 `inside-expr`。它会过滤外层表达式、绑定外层内联捕获，然后使用内部 `patterns` 或 `patterns-not` 搜索捕获到的 `__TARGET__` 表达式子树。

## 心智模型

请针对单个 MoonBit 表达式子树的形状编写规则，而不是针对整个文件。

`moongrep` 使用 `moonbitlang/parser` 解析源文件，从顶层函数、方法、let、test、view 和表达式 body 中收集表达式子树，并将结构规则应用到这些表达式子树。

- `shape` 应该是能捕获你想标记内容的最小表达式片段。
- `patterns` 下的多个条目是有序备选项。对于一个表达式和一条规则，第一个匹配的 pattern 获胜，并决定 `pattern_index`。
- `patterns-not` 只会在当前候选表达式根的所有正向 `patterns`
  都失败后检查。正向命中会报告一个结果，并跳过该候选的
  `patterns-not`。负向命中会剪枝该候选子树，但不产生命中。
- 同一规则中的所有 pattern 共享相同的规则 id 和 `description`。
- 结构规则的 pattern object 可以使用 `guard`，在 shape 匹配后用正则过滤
  `id` 和 `const` 捕获。
- 如果存在 `inside-expr`，它会先在当前表达式上运行。如果它将
  `__TARGET__` 捕获为表达式且存在 `patterns`，目标子树中的每个候选都会先运行正向 pattern，只有正向失败后才检查 `patterns-not`。如果没有 `patterns`，只有整个目标子树没有负向匹配时才报告外层表达式。
- 当 `inside-expr` 规则同时有正向和负向 pattern 时，正向命中会默认覆盖其中嵌套的负向形状用法；任何未被覆盖的负向命中都会拒绝外层上下文。
- `inside-expr` 声明的内联捕获对内部 `patterns` 和 `patterns-not`
  保持可见；`__TARGET__` 只选择要遍历的表达式子树，不能被内部 pattern 使用。
- 继承来的 `id` 捕获遵守词法遮蔽；如果内部 pattern 引用了外层 `id` 捕获，而通向候选表达式的路径上有同名（规范化后）的局部绑定，则跳过该候选。
- 内部正向和负向 pattern 通过重复相同的内联元变量形式复用来自
  `inside-expr` 的名称；同名但 kind 不同会被拒绝。
- `inside-expr` 规则的命中会记录上下文表达式的 `outer_loc`，以及内部匹配的 `loc`；只有 `patterns-not` 的 `inside-expr` 规则中，`loc` 是外层表达式位置。

对于污点规则：

- `taint` 必须是映射，且包含非空 `sources` 和 `sinks` 数组。`sanitizers` 是可选的，默认值为空；如果出现，它必须是数组。
- `taint.sources` 将匹配的调用结果标记为 tainted values。
- 当由 `__SOURCE__` 标记的 receiver 或参数为 tainted 时，`taint.sinks` 会报告命中。
- `taint.sanitizers` 不贡献返回污点，只在 `__SOURCE__` 解析到 storage path（例如标识符、字段或数组访问）时清除已存储的污点。如果同一调用也匹配 source 子句，source 返回污点仍会产生。
- taint 子句 shape 使用与结构 pattern 相同的内联 `$(name:kind)` 语法。
- taint 子句不支持 `guard`。
- `__SOURCE__` 在 taint 规则中是保留名称，不能用作内联元变量名。它只在 sink 和 sanitizer shape 中有效；source shape 不能包含它。
- source、sink 和 sanitizer shape 必须是调用表达式。Sink 和 sanitizer shape 必须将 `__SOURCE__` 放在整个 receiver 或整个参数值的位置。
- YAML taint shape 只使用直接调用或方法调用语法。pipe 和 reverse-pipe 调用目前不能用 YAML taint 规则表达。
- 未匹配的调用没有效果，因此污点不会通过任意 wrapper 或 helper 调用传播，除非这些调用匹配 source、sink 或 sanitizer 子句。
- 如果一个调用同时匹配 sink 和 sanitizer，sink 会根据调用前的污点报告；sanitizer 效果只影响后续 storage 读取。
- 污点分析只运行在函数定义和带 body 的 impl method 上。

如果你需要精确的匹配器语义，请阅读 [RuleSpec_CN.md](RuleSpec_CN.md)。

## 工作流

### 1. 选择最小的有效 `shape`

从一个已经长得像目标代码的具体源码片段开始，然后缩小它，直到只剩必要结构。

好的起始 shape：

```yaml
patterns:
  - shape: $conn.read_request()
```

```yaml
patterns:
  - shape: |
      for $counter = $start; $counter < $limit; $counter = $counter + 1 {
        $body
      }
```

`shape` 会作为单个 MoonBit 表达式片段解析。如果你粘贴整个文件，或只在模块作用域才有意义的片段，规则编译会失败。

### 2. 在 `shape` 中内联标记元变量

`shape` 中的名称默认都是字面量，即使它们看起来像占位符。

这个规则：

```yaml
patterns:
  - shape: _expr == _expr
```

**不会**创建元变量。它匹配两侧字面标识符名称 `_expr`。

如果要捕获一个表达式，请直接在 shape 中写裸 `$name`：

```yaml
patterns:
  - shape: $expr == $expr
```

只出现在表达式位置的裸名称会推导为 `exp`。当同一个裸名称出现在 binder、标签、构造器、类型名或限定标识符位置时，它会推导为 `id`，适合让同一个源码层面的名称在定义和使用位置保持一致：

```yaml
patterns:
  - shape: |
      for $counter = $start; $counter < $limit; $counter = $counter + 1 {
        $body
      }
```

当推导有歧义，或需要 `const`、`arg` 或 `pat` 时，请使用显式 `$(name:kind)`。当同一个字面常量必须保持一致，并且变量不应该匹配时，请使用 `$(name:const)`：

```yaml
patterns:
  - shape: $(value:const) + $(value:const)
```

使用 `$(name:pat)` 捕获完整 pattern AST：

```yaml
patterns:
  - shape: match input { $(item:pat) => body }
```

使用 `$(name:arg)` 捕获完整调用参数槽：

```yaml
patterns:
  - shape: sink($(arg:arg))
```

这个 pattern 可以在单个参数槽中匹配 positional、labelled、labelled pun、optional labelled 和 optional pun 参数。裸 `$arg` 不会推导为 `arg`；请在每个参数槽显式写出 kind。

像 `match input { $item => body }` 这样的裸简单 pattern variable 在 `id`、`const` 和 `pat` 之间有歧义，因此规则编译会要求你显式选择。`exp` kind 只能出现在表达式位置。`const` kind 只在常量表达式或常量 pattern 位置有效。`arg` kind 只在调用 pattern 的整个裸参数位置有效。`pat` kind 只在简单 pattern variable 位置有效。如果需要非表达式源码名称，请使用 `id`，或者让该名称保持字面量。任何其他 kind 都是编译错误。

旧的 YAML `metavars` 键无效。

内置例外是只由两个或更多下划线组成的名称，例如 `__`、`___` 和 `____`。它们是 `shape` 内的特殊忽略占位符，因此不能用作内联元变量名。

```yaml
patterns:
  - shape: foo(__)
```

当这些名称之一出现在支持的元变量位置时，它会匹配该位置上的任何内容，不绑定值，也不参与重复名称相等性检查。重复的忽略占位符是彼此独立的通配符。

### 3. 选择 `exp`、`id`、`const`、`arg` 或 `pat`

当你想匹配并比较完整表达式时，使用 `exp`。重复使用同一个 `exp` 元变量意味着这些捕获必须根据运行时 matcher 的结构相等规则相等；源码位置会被忽略。

```yaml
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

它适合完整表达式比较，例如：

- `x == x`
- `user.profile.name == user.profile.name`
- `make(value) == make(value)`

当你想跨越不同位置比较源码层面名称时，使用 `id`；尤其适合 binder 位置和标识符使用位置之间的比较。

```yaml
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

这里 `counter` 既作为 binder 出现，也作为后续标识符表达式出现。它们应该按相同拼写匹配，但原始 AST node 不同，因此 `id` 是合适工具。

`id` 也适用于 parser AST 中表示为 `Var` 的简单赋值目标，因此像 `x = x + 1` 这样的规则可以按归一化名称绑定左侧目标，而不是把它当作字面字符串。

`id` 也可以比较限定函数名和构造器 identity。像 `@int.abs` 这样的限定函数名会归一化为 `@int.abs`；限定构造器会包含 extra info，例如 `@pkg.Ctor` 或 `@pkg.Type::Ctor`。

当候选必须是解析后的 MoonBit 常量时，使用 `const`。重复的 `const` 捕获会比较常量 kind 和值，因此 `1 + 1` 可以匹配，而 `1 + 2` 和 `x + x` 不会匹配。

当候选必须是整个 pattern AST 时，使用 `pat`：

```yaml
patterns:
  - shape: match input { $(item:pat) => body }
```

当候选必须是完整调用参数槽时，使用 `arg`；它会包含参数 kind、标签和值。重复的 `arg` 捕获会比较完整参数节点，并忽略源码位置。

```yaml
patterns:
  - shape: sink($(arg:arg), $(arg:arg))
```

这可以匹配 `sink(value, value)` 和 `sink(label=value, label=value)`，但不会匹配 `sink(value, other)` 或 `sink(label=value, other=value)`。

### 3.5 当关注节点必须出现在更大上下文内时，使用 `inside-expr`

当你想标记的内容只有在特定外层表达式内才有意义，并且你希望内部匹配继承外层捕获时，可以使用 `inside-expr`。

```yaml
id: wrapped-target
description: |
  Match a call only when it appears inside a specific wrapper.
inside-expr:
  shape: |
    wrapper($(prefix:exp), __TARGET__)
patterns:
  - shape: |
      target.call($(prefix:exp))
```

`inside-expr` 的规则：

- 它使用与一个结构 pattern 相同的 `shape` 和可选 `guard` schema
- 它必须放置且只放置一个支持的 `__TARGET__`；请将其放在期望完整表达式的位置，使运行时遍历可以搜索该子树
- `__TARGET__` 是保留名称，不能用作内联元变量名
- 内部 `patterns` 和 `patterns-not` 不能包含 `__TARGET__`；target placeholder 选择要搜索的子树，但不是内部 shape 可用的绑定
- 继承来的 `id` 捕获在被搜索的 target 子树内遵守词法遮蔽
- 内部 `patterns` 和 `patterns-not` 通过重复相同的内联元变量形式引用外层捕获，例如 `$(prefix:exp)`；同名但 kind 不同会被拒绝

### 3.6 使用 `patterns-not` 剪枝禁止的子树

当某个结构形状应当在当前候选未命中任何正向 pattern 后剪枝时，使用
`patterns-not`。

```yaml
id: unblocked-target
description: |
  Target call outside blocked wrappers.
patterns:
  - shape: target()
patterns-not:
  - shape: blocked($(value:exp))
```

正向 pattern 会先于负向 pattern 在每个候选根上运行。只有所有正向备选都失败后，才会检查负向 pattern。负向 pattern 检查的是当前根，而不是根下面的每个子表达式。在示例中，`blocked(target())` 会剪枝 `blocked(...)` 分支，因此内部的 `target()` 不会被报告。`patterns-not` 内的 `value` 由负向 pattern 自己捕获，不复用任何正向 pattern 捕获。

如果只有 `inside-expr` 和 `patterns-not`，可以描述“某个上下文内不包含禁止形状”：

```yaml
id: wrapper-without-danger
description: |
  Wrapper payload contains no danger call.
inside-expr:
  shape: wrapper(__TARGET__)
patterns-not:
  - shape: danger()
```

当捕获到的 `__TARGET__` 子树中没有 `danger()` 时，这会报告
`wrapper(...)`。

当 `inside-expr` 同时使用 `patterns` 和 `patterns-not` 时，正向命中的整个子树会覆盖负向匹配；任何出现在这些正向覆盖子树之外的负向命中都会拒绝外层上下文。

```yaml
inside-expr:
  shape: wrapper($(counter:id), __TARGET__)
patterns:
  - shape: arr[$(counter:id)]
patterns-not:
  - shape: $(counter:id)
```

这只会在 target 子树中继承来的计数器 `i` 的每个未被遮蔽用法都位于某个 `arr[i]` 匹配内部时报告这些被覆盖的命中。像 `println(i)` 这样的未覆盖 `i` 会拒绝该 wrapper 匹配。

### 4. 使用 `guard` 过滤 id 和 const

当 shape 正确，但某个 `id` 或 `const` 捕获还需要正则过滤时，使用 `guard`：

```yaml
patterns:
  - shape: $(callee:id)($(value:const))
    guard:
      $callee: "^@html\\.render$"
      $value: "danger|raw"
```

Guard 键是带 `$` 前缀的捕获名。值是正则字符串，使用包含匹配语义；如果需要整串
匹配，请写 `^...$`。`id` guard 看到的是归一化名称，例如 `name` 或
`@pkg.name`。`const` guard 看到的是 parser 常量值，例如 `"raw"` 对应 `raw`，
`42` 对应 `42`，`true` 对应 `true`。

Guard 不能过滤 `exp`、`arg` 或 `pat` 捕获，taint 子句也不支持 `guard`。

### 5. 当消息共享时添加更多 `patterns`

如果多个表面形式应该使用同一个规则 id 和 description，请把它们放在同一个规则文件中。

```yaml
id: request-lifecycle
description: |
  These HTTP parser entrypoints accept messages where `Content-Length` and
  `Transfer-Encoding` may coexist.
patterns:
  - shape: |
      $(conn:exp).read_request()
  - shape: |
      $(client:exp).end_request()
```

只有当规则 id、消息或归属应该不同时，才使用不同的规则文件。

### 6. 运行扫描器

在模块根目录下使用规则目录运行 `moongrep`：

```bash
moon run . -- scan [--verbose] --rules <rules-root> [scan-root]
```

`--rules=<rules-root>` 和 `-r <rules-root>` 是等价形式。如果省略 `scan-root`，扫描器使用 `.`。`--verbose` 会在 warning 和匹配结果之前打印已加载的 rule id 和目录遍历进度。

扫描器默认使用 untyped AST matcher。重复的 `exp` 和 `pat` 捕获会按忽略源码位置的 untyped AST 结构相等性进行比较。

## 完整示例

### 重复 `exp` 相等性

```yaml
id: repeated-equality
description: |
  Repeated expression equality.
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

为什么它能工作：

- `expr` 被声明为 `exp` 元变量
- 两次出现必须绑定到忽略源码位置后相等的 untyped AST 节点
- 该规则可以匹配比简单名称更复杂的内容

### Binder 和使用处必须共享同一个源码层面名称

```yaml
id: counter-loop
description: |
  C-style `for` loop.
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

为什么它能工作：

- `counter` 按归一化后的标识符名称比较，而不是按原始 AST 相等性比较
- `start`、`limit` 和 `body` 是以 untyped AST 节点保存的表达式捕获

### 同一规则，多个 shape

```yaml
id: collect-output
description: |
  These helpers collect full child-process output into memory before returning.
patterns:
  - shape: $(command:exp).output_collect($(args:exp))
  - shape: $(command:exp).stderr_collect($(args:exp))
```

为什么它能工作：

- 每个 pattern 都是有序备选项
- 任一形式都发出相同的规则元数据
- 命中通过 `pattern_index` 记录匹配的是哪个备选项

## 调试清单

### 规则编译提示 `shape` 无效

你的片段没有被 MoonBit 表达式 parser 接受。先将它缩减到一个有效的表达式大小 shape，然后小心地逐步补回结构。

### 规则编译提示元变量语法无效

按顺序检查：

- `$(name:exp)` 只出现在完整的裸表达式位置
- `$(name:const)` 只出现在可匹配常量表达式或常量 pattern 的位置
- `$(name:arg)` 只出现在完整的裸调用参数位置
- `$(name:pat)` 只出现在完整的裸 pattern 位置
- 非表达式源码名称使用 `$(name:id)`，或者保持字面量
- 没有使用不支持的 kind
- 没有跨多个元变量 kind 使用同一个名称

### 一个 `id` 规则看起来正确但从不命中

重复捕获可能归一化为不同的源码层面名称。例如，`abs` 和 `@int.abs` 是不同的归一化标识符。请查看 [RuleSpec_CN.md](RuleSpec_CN.md) 中精确支持的归一化情况。

### 带 `guard` 的规则加载失败

请检查 `guard` 是否位于结构规则的 `patterns`、`patterns-not` 或 `inside-expr`
pattern object 下，是否是映射，并且每个键都引用了该 pattern 可见的 `id` 或
`const` 捕获。taint 子句中仍然会拒绝 `guard`。

## 测试工作流

修改规则或规则行为后：

1. 在聚焦 fixture 上运行扫描器：
   `moon run . -- scan --rules <rules-root> <fixture-root>`
2. 在 `rule/` 下新增或更新聚焦测试
3. 覆盖一个正例，以及至少一个容易回归的相近反例

保持测试范围窄。好的规则测试会证明预期匹配，以及至少一个容易回归的非匹配场景。
