# 编写规则

`rule/*` packages 定义了 `moongrep` 使用的 YAML 规则格式，以及运行时 loader、validator、compiler 和 applicator。

如果你想新增或调整规则，请从这里开始。

另见：

- [RuleSpec_CN.md](RuleSpec_CN.md)：权威 YAML 规则规范，包含可接受的键、匹配器语义和失败情况

## 介绍

YAML 规则文件是扫描器的输入。规则根目录可以是通过 `--rules` 或 `-r` 传给 `moongrep scan` CLI 的任意目录。未指定规则来源选项时，规则根目录默认为 `./.moongrep/rules`。以 `.yaml` 或 `.yml` 结尾的文件会在该根目录下递归发现；其他文件会被忽略。发现的文件会按排序后的顺序加载，以得到确定性的输出。空规则根目录是错误。

规则 id 来自规则文件目录加 YAML `id`。例如，当 `rules` 是规则根目录时，`rules/security/raw.yaml` 中的 `id: raw-html` 会变成 `security/raw-html`。直接位于规则根目录下的文件只使用其 `id`。文件名不参与规则 id。YAML `id` 不能为空，且不能包含 `/`；目录归属由文件位置编码。

每个 YAML 文件必须只包含一个文档，且该文档必须是映射。完整规则文件需要字符串字段 `id` 和 `description`，会拒绝未知顶层键，并且选择以下规则模式之一：

- 结构模式：非空 `patterns`，或 `inside-expr` / `inside-toplevel`
  搭配 `patterns`、`patterns-not`，或两者同时存在
- `taint`：过程内污点建模，编译到 `taint` package

`patterns` 必须是非空数组。未知键会在每个 schema 层级被拒绝：顶层规则键、`taint` 键和规则子句键。

结构规则还可以添加一个可选的外层上下文字段：`inside-expr` 过滤外层表达式，
`inside-toplevel` 过滤 MoonBit 顶层项。每个字段都是由 pattern object
组成的非空有序备选数组。两者都会使用首个匹配的外层条目绑定捕获，然后使用
内部 `patterns` 或 `patterns-not` 搜索其 `__TARGET__` 表达式子树。

## 心智模型

请针对单个 MoonBit 表达式子树的形状编写规则。整个文件不属于表达式子树。

`moongrep` 使用 `moonbitlang/parser` 解析源文件，从顶层函数、方法、let、test、view 和表达式 body 中收集表达式子树，并将结构规则应用到这些表达式子树。

- `shape` 应该是能捕获你想标记内容的最小表达式片段。
- `patterns` 下的多个条目是有序备选项。对于一个表达式和一条规则，第一个匹配的 pattern 获胜，并决定 `pattern_index`。
- `patterns-not` 只会在当前候选表达式根的所有正向 `patterns`
  都失败后检查。正向命中会报告一个结果，并跳过该候选的
  `patterns-not`。负向命中会剪枝该候选子树且不产生命中。
- 同一规则中的所有 pattern 共享相同的规则 id 和 `description`。
- 结构规则的 pattern object 可以使用 `guard`，在 shape 匹配后用正则过滤
  `id` 和 `const` 捕获。
- 如果存在 `inside-expr` 或 `inside-toplevel`，当前候选会按 YAML 顺序尝试可用的外层条目。首个同时通过 shape 和 guard 的条目会选定 `__TARGET__` 与绑定。guard 失败会继续尝试下一项，但一旦选中，即使内部没有命中也不会回退到后续外层条目。存在 `patterns` 时，选中目标子树中的每个候选都会先运行正向 pattern，只有正向失败后才检查 `patterns-not`。如果没有 `patterns`，只有整个目标子树没有负向匹配时才报告外层上下文。
- 当外层上下文规则同时有正向和负向 pattern 时，正向命中会默认覆盖其中嵌套的负向形状用法；任何未被覆盖的负向命中都会拒绝外层上下文。
- 选中的 `inside-expr` 或 `inside-toplevel` 条目所声明的内联捕获对内部
  `patterns` 和 `patterns-not` 保持可见；`__TARGET__` 只选择要遍历的表达式子树，不能被内部 pattern 使用。
- 继承来的 `id` 捕获遵守词法遮蔽；如果内部 pattern 引用了外层 `id` 捕获，并且通向候选表达式的路径上有同名（规范化后）的局部绑定，则跳过该候选。
- 内部正向和负向 pattern 通过重复相同的内联元变量形式复用来自外层上下文的名称。每个外层备选项都必须以相同 kind 声明被复用的名称，包括命名 ellipsis 捕获。内部未引用的额外外层捕获可以因备选项而异。
- 每个成功匹配的 `inside-expr` 外层表达式最多报告一个命中，`loc` 是外层表达式位置；当内部正向 pattern 命中时，遍历顺序中的第一个命中决定 `pattern_index`。
- `inside-toplevel` 会在内部正向匹配位置分别报告命中；只有 `patterns-not` 时，报告匹配到的顶层项位置。

### 源码级结构规则抑制

把裸 `#moongrep.skip` 属性附加到函数定义、impl 方法、顶层 `let` 定义、test
或 view 声明上，可以抑制该顶层项内的全部结构规则：

```moonbit
#moongrep.skip
fn generated_adapter {
  legacy_call()
}
```

该标记只影响结构规则。对于带标记的函数定义和 impl 方法，污点分析始终继续运行。

该属性不支持 payload。`#moongrep.skip()`、布尔 payload、其他 payload 和畸形
payload 都不会抑制结构规则。对于进入解析流程的源码，每个无效 payload 都会在
标准错误输出以下 warning：

```text
warning: <location>: #moongrep.skip does not accept a payload; use bare #moongrep.skip
```

源码文本 prefilter 在解析前运行；如果已启用规则都不可能命中某个文件或 `///|`
源码块，它可以直接丢弃该部分。被丢弃源码中的无效 payload 不会被检查，也不会产生
warning。无论是否产生 warning，扫描都会继续，退出码不变。

`#skip`、`#other.skip` 等无关属性会被忽略。如果同一顶层项同时带有裸标记和
无效 payload，并且该顶层项进入了解析流程，无效形式仍会产生 warning，裸标记仍会
抑制结构规则。

对于污点规则：

- `taint` 必须是映射，且包含非空 `sources` 和 `sinks` 数组。`sanitizers` 是可选的，默认值为空；如果出现，它必须是数组。
- `taint.sources` 将匹配的调用结果标记为 tainted values。
- 当由 `__SOURCE__` 标记的 receiver 或参数为 tainted 时，`taint.sinks` 会报告命中。
- `taint.sanitizers` 不贡献返回污点，只在 `__SOURCE__` 解析到 storage path（例如标识符、字段或数组访问）时清除已存储的污点。如果同一调用也匹配 source 子句，source 返回污点会产生。
- taint 子句 shape 使用与结构 pattern 相同的内联 `$(name:kind)` 语法。
- taint 子句不支持 `guard`。
- `__SOURCE__` 在 taint 规则中是保留名称，不能用作内联元变量名。它只在 sink 和 sanitizer shape 中有效；source shape 不能包含它。
- source、sink 和 sanitizer shape 必须是调用表达式。Sink 和 sanitizer shape 必须将 `__SOURCE__` 放在整个 receiver 或整个参数值的位置。
- YAML taint shape 只使用直接调用或方法调用语法。pipe 和 reverse-pipe 调用目前不能用 YAML taint 规则表达。
- 未匹配的调用没有效果。匹配 source、sink 或 sanitizer 子句的 wrapper 和 helper 调用使用相应模型，其他这类调用不传播污点。
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

### 1.1. 判断 `let` body 是否重要

没有显式 body 的普通 `let` shape 只匹配 let header。当你只关心绑定本身时，这很有用：

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp)
```

因为 body 会被忽略，这个 shape 可以匹配下面所有候选形式：

```moonbit
let item = load()
```

```moonbit
let item = load(); use(item)
```

```moonbit
let item = load(); { trace(item); item }
```

如果 body 重要，请把它写进 shape：

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp); use($(name:id))
```

如需捕获任意形式的 body，请显式添加 body 元变量：

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp); $(body:exp)
```

如果你期望 body 是 unit，请显式写 unit body：

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp); ()
```

当你的意思是“body 为空”或“body 是 `()`”时，不要写
`let $(name:id) = $(value:exp)`；省略 body 的形式会有意忽略候选表达式的任意 body。当前结构 shape
无法表达“只匹配语法上省略 body 的 let”。

### 1.2. 判断 `guard` body 是否重要

没有显式 body 的 `guard` shape 会匹配 condition 和 `else` 表达式，同时忽略
候选表达式的 continuation：

```yaml
patterns:
  - shape: guard ready() else { fallback() }
```

这个 shape 既能匹配单独的 guard，也能匹配后面带任意 body 的 guard：

```moonbit
guard ready() else { fallback() }; continue_work()
```

```moonbit
guard ready() else { fallback() }; { prepare(); finish() }
```

如果 continuation 重要，请显式写出：

```yaml
patterns:
  - shape: guard ready() else { fallback() }; continue_work()
```

如需捕获任意形式的 body，请显式添加 body 元变量：

```yaml
patterns:
  - shape: guard ready() else { fallback() }; $(body:exp)
```

显式 unit body 也仍然精确匹配：

```yaml
patterns:
  - shape: guard ready() else { fallback() }; ()
```

最后一种形式不是通配符。只有 pattern 省略 body 时由 parser 合成的 unit
才会让候选 body 不受约束。

### 2. 在 `shape` 中内联标记元变量

`shape` 中看起来像占位符的名称默认也是字面量。

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

只出现在表达式位置的裸名称会推导为 `exp`。当同一个裸名称出现在 binder、标签、构造器、类型名或限定标识符位置时，它会推导为 `id`，适合让同一个源码层面的名称在定义和使用位置保持一致。出现在完整类型位置的裸名称会推导为 `type`：

```yaml
patterns:
  - shape: |
      for $counter = $start; $counter < $limit; $counter = $counter + 1 {
        $body
      }
```

当推导有歧义，或需要 `const`、`arg`、`pat` 或 `type` 时，请使用显式 `$(name:kind)`。当同一个字面常量必须保持一致，并且变量不应该匹配时，请使用 `$(name:const)`：

```yaml
patterns:
  - shape: $(value:const) + $(value:const)
```

使用 `$(name:pat)` 捕获完整 pattern CST：

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

使用 `$(name:type)` 捕获完整类型 CST 节点：

```yaml
patterns:
  - shape: |
      let value : $(T:type) = input
  - shape: |
      let values : Array[$T] = input
```

重复的 `type` 捕获会比较完整解析类型节点并忽略源码位置。`type` 捕获必须占据完整类型节点；它不捕获表达式参数、构造器、标签或方法类型限定符。

使用 `$$$name` 捕获有序 CST 列表中零个或多个连续项；使用
`$$$(name:kind)` 约束捕获序列中的每一项：

```yaml
patterns:
  - shape: inspect($$$args)
  - shape: f(prefix, $$$(values:exp), suffix)
```

ellipsis 必须占据完整列表项。只要对应语法会解析为无字段名的有序 CST
列表项，它就可以用于调用实参、数组或 tuple 元素、parameter、pattern 或类型列表。
它不能作为整个 pattern 根、表达式的一部分，也不能展开块的最后表达式等具名标量字段。
匹配从左到右采用惰性策略：每个 ellipsis 依次尝试长度 0、1、2……，并回滚直到
完整 shape 成功。同一列表可以出现多个 ellipsis。

裸 ellipsis 默认为 `AnyItem`。显式 `exp`、`id`、`const`、`arg`、`pat`
和 `type` 会对每个元素复用对应的单节点元变量约束。在调用实参列表中，`arg`
接受所有 argument kind。`exp`、`id` 和 `const` 只接受兼容的 positional
argument value。同名 ellipsis 重复出现时，捕获的节点序列必须在忽略源码位置后
结构相等。`$$$_` 和 `$$$(_:kind)` 是彼此独立且不绑定的序列通配符。

像 `match input { $item => body }` 这样的裸简单 pattern variable 在 `id`、`const` 和 `pat` 之间有歧义，因此规则编译会要求你显式选择。`exp` kind 只能出现在表达式位置。`const` kind 只在常量表达式或常量 pattern 位置有效。`arg` kind 只在调用 pattern 的整个裸参数位置有效。`pat` kind 只在简单 pattern variable 位置有效。`type` kind 只在完整类型节点位置有效。如果需要非表达式源码名称，请使用 `id`，或者让该名称保持字面量。任何其他 kind 都是编译错误。

旧的 YAML `metavars` 键无效。

内置例外是精确拼写 `$_`。它是 `shape` 内的特殊忽略占位符，因此不能用作内联元变量名。

```yaml
patterns:
  - shape: foo($_)
```

当 `$_` 出现在支持的元变量位置时，它会匹配该位置上的任何内容，不绑定值，也不参与重复名称相等性检查。重复的忽略占位符是彼此独立的通配符。`__`、`___` 和 `$__` 不是忽略占位符。

### 3. 选择 `exp`、`id`、`const`、`arg`、`pat` 或 `type`

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

这里 `counter` 既作为 binder 出现，也作为后续标识符表达式出现。它们应该按相同拼写匹配。原始 CST node 不同。`id` 会比较它们规范化后的名称。

`id` 也适用于 parser CST 中表示为 `Var` 的简单赋值目标，因此像 `x = x + 1` 这样的规则可以按归一化名称绑定左侧目标，不把它当作字面字符串。

`id` 也可以比较限定函数名和构造器 identity。像 `@int.abs` 这样的限定函数名会归一化为 `@int.abs`；限定构造器会包含 extra info，例如 `@pkg.Ctor` 或 `@pkg.Type::Ctor`。

当候选必须是解析后的 MoonBit 常量时，使用 `const`。重复的 `const` 捕获会比较常量 kind 和值。`1 + 1` 可以匹配。`1 + 2` 和 `x + x` 不会匹配。

当候选必须是整个 pattern CST 时，使用 `pat`：

```yaml
patterns:
  - shape: match input { $(item:pat) => body }
```

当候选必须是完整调用参数槽时，使用 `arg`；它会包含参数 kind、标签和值。重复的 `arg` 捕获会比较完整参数节点，并忽略源码位置。

```yaml
patterns:
  - shape: sink($(arg:arg), $(arg:arg))
```

这可以匹配 `sink(value, value)` 和 `sink(label=value, label=value)`。它不会匹配 `sink(value, other)` 或 `sink(label=value, other=value)`。

当候选必须是完整类型标注或类型组成部分时，使用 `type`。重复的 `type` 捕获会比较完整类型 CST 节点，因此可以要求两个标注使用同一种类型：

```yaml
patterns:
  - shape: |
      let left : $(T:type) = input; let right : $(T:type) = input
```

### 3.5 当关注节点必须出现在更大上下文内时，使用 `inside-expr`

当你想标记的内容只有在特定外层表达式内才有意义，并且你希望内部匹配继承外层捕获时，可以使用 `inside-expr`。

```yaml
id: wrapped-target
description: |
  Match a call only when it appears inside a supported context.
inside-expr:
  - shape: |
      wrapper($(prefix:exp), __TARGET__)
  - shape: |
      container($(prefix:exp), __TARGET__)
patterns:
  - shape: |
      target.call($(prefix:exp))
```

`inside-expr` 的规则：

- 它是非空数组，使用与 `patterns` 相同的 `shape` 和可选 `guard`
  对象 schema
- 条目是有序备选项，首个同时匹配 shape 和 guard 的条目会被选中
- 每个条目都必须放置且只放置一个支持的 `__TARGET__`；请将其放在期望完整表达式的位置，使运行时遍历可以搜索该子树
- `__TARGET__` 是保留名称，不能用作内联元变量名
- 内部 `patterns` 和 `patterns-not` 不能包含 `__TARGET__`；target placeholder 选择要搜索的子树，不为内部 shape 创建绑定
- 继承来的 `id` 捕获在被搜索的 target 子树内遵守词法遮蔽
- 内部 `patterns` 和 `patterns-not` 通过重复相同的内联元变量形式引用外层捕获，例如 `$(prefix:exp)`；每个外层备选项都必须以相同 kind 声明被复用的捕获
- 内部条目未引用的分支局部外层捕获允许不同
- 外层 guard 失败时会尝试下一项；条目一旦选中，即使 target 子树没有产生 finding，也不会替换成后续项
- 每个匹配成功的外层表达式最多在该外层表达式位置报告一个命中；如果有多个内部正向 pattern 命中，遍历顺序中的第一个命中决定 `pattern_index`

当上下文是顶层项时，使用 `inside-toplevel`：

```yaml
id: safe-function-target
description: |
  Match a call only in selected top-level functions.
inside-toplevel:
  - shape: |
      fn $(name:id)($(param:id) : Int) -> Int { __TARGET__ }
    guard:
      $name: "^safe_"
patterns:
  - shape: call($(param:id))
```

`inside-toplevel` 和 `inside-expr` 互斥。`inside-toplevel` 同样是非空
有序数组。每个条目的 `shape` 必须且只能是一个 MoonBit 顶层项，并且必须在
该顶层项内部的表达式位置放置且只放置一个支持的 `__TARGET__`。它使用与
`inside-expr` 相同的选择和共享捕获规则。带正向 `patterns` 的命中报告内部
匹配位置；只有 `patterns-not` 时，`loc` 是顶层项位置。

函数 shape 默认使用 partial；其他顶层项默认使用 exact：

| `match-mode` | 函数 shape | 其他顶层 shape |
| --- | --- | --- |
| 省略 | partial | exact |
| `exact` | exact | exact |
| `partial` | partial | 非法 |

文档注释在所有模式中都会被忽略。Shape 中的 docstring 不要求候选项具有相同
docstring，也不要求候选项存在 docstring。

在 partial 模式中，函数头里省略的类型限定、`async`、参数、类型参数、
返回类型、错误类型、可见性、attribute 和 `where` 都不约束候选项。
shape 中一旦写出某个语义字段，该字段仍然精确匹配。函数名、函数体和
`__TARGET__` 永远不会自动放宽。

完整函数头确实重要时，显式使用 exact：

```yaml
inside-toplevel:
  - shape: |
      fn $(name:id) { __TARGET__ }
    match-mode: exact
```

迁移旧规则时，如果规则依赖“省略的函数字段必须不存在”，请添加
`match-mode: exact`。宽泛的函数上下文保持不标注即可。

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

正向 pattern 会先于负向 pattern 在每个候选根上运行。只有所有正向备选都失败后，才会检查负向 pattern。负向 pattern 只检查当前根，不检查根下面的每个子表达式。在示例中，`blocked(target())` 会剪枝 `blocked(...)` 分支，因此内部的 `target()` 不会被报告。`patterns-not` 内的 `value` 由负向 pattern 自己捕获，不复用任何正向 pattern 捕获。

如果只有 `inside-expr` 或 `inside-toplevel` 和 `patterns-not`，可以描述“某个上下文内不包含禁止形状”：

```yaml
id: wrapper-without-danger
description: |
  Wrapper payload contains no danger call.
inside-expr:
  - shape: wrapper(__TARGET__)
patterns-not:
  - shape: danger()
```

当捕获到的 `__TARGET__` 子树中没有 `danger()` 时，这会报告
`wrapper(...)`。

当外层上下文同时使用 `patterns` 和 `patterns-not` 时，正向命中的整个子树会覆盖负向匹配；任何出现在这些正向覆盖子树之外的负向命中都会拒绝外层上下文。

```yaml
inside-expr:
  - shape: wrapper($(counter:id), __TARGET__)
patterns:
  - shape: arr[$(counter:id)]
patterns-not:
  - shape: $(counter:id)
```

只有 target 子树中继承来的计数器 `i` 的每个未被遮蔽用法都位于某个
`arr[i]` 匹配内部时，才会报告一次该 wrapper；第一个被覆盖的 `arr[i]`
命中决定 `pattern_index`。像 `println(i)` 这样的未覆盖 `i` 会拒绝该
wrapper 匹配。

### 4. 使用 `guard` 过滤 id 和 const

当 shape 匹配后还需要对某个 `id` 或 `const` 捕获进行正则过滤时，使用 `guard`：

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

Guard 不能过滤 `exp`、`arg`、`pat`、`type` 或 ellipsis 捕获，taint 子句也不支持 `guard`。

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

在要扫描的 MoonBit 模块根目录下运行扫描器。如果已安装 `moongrep`，请使用：

```bash
moongrep scan [--verbose] [--rules <rules-root>] [scan-root]
```

如果不安装 `moongrep`，而是通过 Mooncakes 运行已发布的 WebAssembly CLI，请使用：

```bash
moonx moonbit-community/moongrep -- scan [--verbose] [--rules <rules-root>] [scan-root]
```

`--rules=<rules-root>` 和 `-r <rules-root>` 是等价形式。未指定规则来源选项时，
`--rules` 使用 `./.moongrep/rules`；显式指定 `--rule`、`--pattern` 或
`--enable-builtin-rules` 会停用该默认值。如果省略 `scan-root`，扫描器使用 `.`。
匹配结果会流式写入标准输出；`--verbose` 会在扫描过程中把已加载的 rule id 和
目录遍历进度写入标准错误，扫描 warning 也写入标准错误。

扫描器默认使用 untyped CST matcher。重复的 `exp`、`arg`、`pat` 和 `type` 捕获会按忽略源码位置的 untyped CST 结构相等性进行比较。

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
- 两次出现必须绑定到忽略源码位置后相等的 untyped CST 节点
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

- `counter` 按归一化后的标识符名称比较，不使用原始 CST 相等性
- `start`、`limit` 和 `body` 是以 untyped CST 节点保存的表达式捕获

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

你的片段没有被对应规则子句的 MoonBit parser 接受。对普通 `patterns`、
`patterns-not` 和 `inside-expr`，先缩减到一个有效的表达式大小 shape，然后小心地逐步补回结构。对
`inside-toplevel`，先缩减到且仅有一个合法顶层项。

如果函数上下文现在命中了更多声明，请检查旧规则是否依赖完整函数头匹配。
可以添加 `match-mode: exact`，或只写出确实需要精确匹配的函数头字段。
Docstring 不能用于区分其他结构相同的 shape。

### 规则编译提示元变量语法无效

按顺序检查：

- `$(name:exp)` 只出现在完整的裸表达式位置
- `$(name:const)` 只出现在可匹配常量表达式或常量 pattern 的位置
- `$(name:arg)` 只出现在完整的裸调用参数位置
- `$(name:pat)` 只出现在完整的裸 pattern 位置
- `$(name:type)` 只出现在完整类型节点位置
- 非表达式源码名称使用 `$(name:id)`，或者保持字面量
- 没有使用不支持的 kind
- 没有跨多个元变量 kind 使用同一个名称
- ellipsis 使用 `$$$name` 或 `$$$(name:kind)`，并占据完整有序列表项
- 普通元变量和 ellipsis 没有共用名称

### 一个看起来正确且从不命中的 `id` 规则

重复捕获可能归一化为不同的源码层面名称。例如，`abs` 和 `@int.abs` 是不同的归一化标识符。请查看 [RuleSpec_CN.md](RuleSpec_CN.md) 中精确支持的归一化情况。

### 带 `guard` 的规则加载失败

请检查 `guard` 是否位于结构规则的 `patterns`、`patterns-not`、`inside-expr`
或 `inside-toplevel` pattern object 下，是否是映射，并且每个键都引用了该 pattern 可见的
`id` 或 `const` 捕获。`exp`、`arg`、`pat`、`type` 和 ellipsis 捕获不能被 guard 过滤。taint 子句会拒绝 `guard`。
