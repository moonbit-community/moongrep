# 规则规范

本文档是 moongrep 接受的 YAML 规则的权威规范。

如果你是第一次编写规则，请先阅读 [WritingRules.md](WritingRules.md)。

## 范围和状态

本文档规定当前 YAML 规则文件格式、校验规则和匹配语义。

关键词 "must"、"must not"、"may" 和 "currently" 描述的是规则作者今天可以依赖的行为。

规则使用 YAML 格式。每个 `shape` 值都是 MoonBit 表面语法。扫描器匹配解析后的 MoonBit 表达式结构，不匹配原始文本。格式和注释不参与匹配。表达式形式、操作符、字面量值、标签、被调用名称和参数结构参与匹配。通配符和已声明元变量按下文规则修改这些匹配要求。

## 规则文件

规则根目录是包含 YAML 规则文件的目录。

- 以 `.yaml` 或 `.yml` 结尾的文件会在规则根目录下递归发现。
- 其他文件会被忽略。
- 发现的规则文件会按排序后的顺序处理。
- 符号链接的规则目录会被跟随。
- 空规则根目录是无效的。
- 每个规则文件必须只包含一个 YAML 文档。
- 顶层 YAML 文档必须是映射。
- 每个规则文件定义且只定义一条规则。

规则 id 由规则文件目录和 YAML `id` 派生：

- 取相对于规则根目录的规则文件目录
- 从 YAML 文档读取顶层 `id` 字符串
- 用 `/` 连接相对目录和 `id`

对于直接位于规则根目录下的规则文件，最终规则 id 就是 `id`。规则文件名不参与规则 id。YAML `id` 不能为空，且不能包含 `/`；目录归属只由文件位置编码。

示例：

```text
rules/example.yaml with id: target-call            -> target-call
rules/security/raw.yaml with id: unsafe-html       -> security/unsafe-html
rules/security/nested/raw.yml with id: unsafe-html -> security/nested/unsafe-html
```

规则 id 必须唯一。

## YAML Schema

### 顶层键

只接受这些顶层键：

- `id`（必需）：非空 YAML 字符串，且不能包含 `/`
- `description`（必需）：YAML 字符串
- `patterns`（结构规则可选）：非空 YAML 数组
- `patterns-not`（结构规则可选）：与 `patterns` 使用相同条目 schema 的非空 YAML 数组
- `inside-expr`（结构规则可选）：YAML 映射，使用与 `patterns` 相同的
  `shape` 和可选 `guard` schema，作为外层上下文
- `inside-toplevel`（结构规则可选）：YAML 映射，使用与 `inside-expr`
  相同的 `shape` 和可选 `guard` schema；它的 shape 解析为一个 MoonBit 顶层项
- `taint`（污点规则必需）：YAML 映射

未知顶层键会被拒绝。

每条规则必须且只能选择一种规则模式：

- 结构模式：`patterns`，可选搭配 `patterns-not`；或 `inside-expr` /
  `inside-toplevel` 搭配 `patterns`、`patterns-not`，或两者同时存在
- 污点模式：`taint`

`patterns` 和 `taint` 互斥。`inside-expr`、`inside-toplevel` 和
`patterns-not` 只对结构规则有效；它们在污点规则中会被拒绝。
`inside-expr` 和 `inside-toplevel` 互斥。`patterns-not` 必须和
`patterns`、`inside-expr` 或 `inside-toplevel` 一起出现；没有
`patterns` 的 `inside-expr` 或 `inside-toplevel` 规则必须包含
`patterns-not`。

`id` 是其文件目录内的本地规则名。`description` 也是必需字段且必须是字符串。它的内容会按 YAML 提供的结果保留，包括 block scalar 产生的尾随换行。

### Pattern Objects

结构规则中的 `patterns`、`patterns-not` 条目以及 `inside-expr`、
`inside-toplevel` 使用以下对象 schema。

只接受这些键：

- `shape`（必需）：包含一个 MoonBit 表达式片段的 YAML 字符串
- `guard`（可选）：从 `$` 前缀捕获名到正则字符串的 YAML 映射

pattern object 中的未知键会被拒绝。

Taint `sources`、`sinks` 和 `sanitizers` 同样使用 `shape` 键。这些字段不接受 `guard`。

## Shapes

普通 `shape` 必须是一个单独的 MoonBit 表达式片段。
`inside-toplevel.shape` 必须且只能是一个 MoonBit 顶层项。

有效的表达式 shape 包括调用、方法调用、字段访问、操作符、块、条件表达式、循环、match、lambda、集合字面量、记录表达式，以及其他表达式大小的 MoonBit 语法。普通 `patterns`、`patterns-not` 和 `inside-expr` shape 不表示整个文件、顶层声明、包片段或 import 列表。`inside-toplevel.shape` 可以是一个函数、顶层 `let`、`test`、方法 `impl`、view 或顶层表达式。它只能表示一个顶层项，不能表示整个文件或 import 列表。

shape 是结构性的：

- 未声明的标识符和标签按字面匹配
- 常量按值匹配
- 操作符按字面匹配
- 调用和方法调用的参数种类、标签、顺序和数量必须匹配
- 匹配语法中出现的类型注解和类型名必须匹配
- 源码位置、格式和注释不参与匹配

扫描器不会对 shape 做类型检查，也不会按语义解析名称。例如，两个指向同一定义的导入名称只在解析后的源码拼写一致或被元变量捕获时视为相同。

### 省略 body 的 let shape

没有显式 body 的普通 `let` shape 是 let-header pattern。例如，下面的 shape
会匹配绑定 pattern 和右侧表达式。它不约束候选表达式的 body：

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp)
```

它可以匹配下面这些候选形式：

```moonbit
let item = load()
```

```moonbit
let item = load(); use(item)
```

```moonbit
let item = load(); { trace(item); item }
```

MoonBit parser 会把 `let item = load()` 表示为 `Expr::Let`，其 body 是一个合成的 unit 表达式。当 pattern shape 中出现这个合成 unit 时，matcher 会把它解释为“pattern 省略了 body”。候选 body 无需匹配同一个 unit node。

如果 body 重要，请显式写出 body：

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp); use($(name:id))
```

如需捕获任意形式的候选 body，请显式写 body 元变量：

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp); $(body:exp)
```

如果期望 body 是 unit，请显式写 `()` body：

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp); ()
```

这会匹配显式 unit body。它不同于上面的省略 body shape；省略 body 的形式会有意忽略候选 body。当前结构 shape
无法表达“只匹配语法上省略 body 的 let”。

这个快捷匹配只适用于普通 `let` 表达式。`let mut`、局部函数定义和
`letrec` shape 使用普通结构匹配。

## 元变量

shape 中的标识符和标签默认都是字面量。只有在 `shape` 内使用内联元变量语法时，一个名称才会成为元变量；下面描述的内置通配符除外。

### 语法

使用 `$(name:exp)` 捕获表达式结构：

```yaml
patterns:
  - shape: $(left:exp) == $(left:exp)
```

使用 `$(name:id)` 捕获归一化后的标识符名称：

```yaml
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

常见情况下可以省略 kind，使用裸 `$name` 语法：

```yaml
patterns:
  - shape: $value + $value
```

moongrep会为同名的所有出现位置推导出单一 kind。只出现在表达式占位位置的裸名称会推导为 `exp`；出现在 binder、标签、构造器、类型名或限定标识符位置的裸名称会推导为 `id`；出现在完整类型节点位置的裸名称会推导为 `type`。例如 `for $counter = 0; $counter < $limit; ...` 中，`$counter` 会从 binder 位置推导为 `id`，`$limit` 会推导为 `exp`；在 `let values : Array[$T] = input` 中，`$T` 会推导为 `type`。

只支持 `exp`、`id`、`const`、`arg`、`pat` 和 `type`。同一个 payload 可以在同一种 kind 中重复使用；同一个 shape 中不能跨 `$(name:exp)`、`$(name:id)`、`$(name:const)`、`$(name:arg)`、`$(name:pat)` 和 `$(name:type)` 等多个 kind 使用同一个 payload。

裸 `$name` 的推导是保守的。它不会默认推导为 `const`、`arg` 或 `pat`。像 `match input { $item => body }` 这样的简单 pattern variable 在 `id`、`const` 和 `pat` 之间有歧义；请写成 `$(item:id)`、`$(item:const)` 或 `$(item:pat)` 来明确选择。裸 `$name` 不会推导为 `arg`；完整调用参数请显式写 `$(name:arg)`。类型标注中的裸 `$name` 可以推导为 `type`；当类型位置不明显时可显式写 `$(name:type)`。同名的显式出现也可以在位置兼容时为后续裸出现确定 kind。

旧的 YAML `metavars` 键不再支持。包含该键的 pattern object 会因使用不支持的键被拒绝。

### Ellipsis 元变量

`$$$name` 捕获 untyped AST 有序列表中零个或多个连续 sibling；
`$$$(name:kind)` 使用 `exp`、`id`、`const`、`arg`、`pat` 或 `type`
约束捕获到的每一项。裸命名 ellipsis 的 kind 是 `AnyItem`；如果同名位置中还存在
typed occurrence，则由 typed occurrence 决定所有裸 occurrence 的 kind。

```yaml
patterns:
  - shape: inspect($$$args)
  - shape: pair([$$$(items:exp)], [$$$items])
```

标记必须占据 untyped AST 中没有字段名的完整 child。调用实参列表、表达式列表、
parameter 列表、pattern 列表和类型列表都可以支持它。它不能作为根、普通具名字段、
标签或另一个节点的一部分；尤其不会展开 `Expr_Sequence.last_expr` 这样的具名字段。

匹配器从左到右处理 pattern item。遇到 ellipsis 时从空序列开始尝试最短捕获，
失败时恢复 bindings 并逐步增加长度，直到剩余 pattern 成功。一个列表包含多个
ellipsis 时也按这一规则确定结果。空捕获满足任何 kind 约束。

在表达式列表中，`exp`、`id` 和 `const` 接受与对应单节点元变量相同的候选。
在调用实参列表中，`arg` 接受 positional、labelled、pun、optional-labelled 和
optional-pun argument；`exp`、`id` 和 `const` 只接受 value 满足相应 kind 的
positional argument。`pat` 用于 pattern 列表项，`type` 用于类型列表项，`id`
可以捕获带 binder 的 parameter 项。捕获数组始终保存原始完整 sibling 节点，
例如 `Argument`、`Parameter` 或表达式节点。

同名 ellipsis 重复出现时，捕获数组长度必须相同，且节点在忽略源码位置后结构相等。
普通元变量与 ellipsis 不能共用名称，冲突的显式 kind 会被拒绝。`$$$_` 和
`$$$(_:kind)` 不绑定，且每个 occurrence 都是独立通配符。guard 不能引用
ellipsis 捕获。inside context 会像其他 binding 一样继承 `Multiple`；内部重复的
ellipsis 必须使用相同 kind。taint sink 和 sanitizer 可以在唯一的完整 argument
或 receiver `__SOURCE__` target 前后放置 ellipsis。

公开 matcher 和 query API 使用 `BoundValue` 表示捕获：普通捕获是
`Single(Node)`，ellipsis 捕获是 `Multiple(Array[Node])`。
`ExprMatch.bindings`、`ExprQuery::captures` 和 `ExprQuery::captures_from_ast`
都返回这种表示。

### 保留名称

这些名称不能用作内联元变量名：

- `$_`
- `__TARGET__`
- `__SOURCE__`

`$_` 是下文描述的忽略占位符。`__TARGET__` 和 `__SOURCE__` 保留已有内置含义。
`__TARGET__` 只在 `inside-expr` 和 `inside-toplevel` 中有效；`__SOURCE__`
只在 taint sink 和 sanitizer shape 中有效。

### 元变量可以绑定的位置

`$(name:exp)` 只在整个裸标识符表达式位置有效。它捕获该位置上的候选表达式。下面是有效写法：

```yaml
patterns:
  - shape: sink($(value:exp))
```

下面是无效写法，因为 pattern binder 不是表达式位置：

```yaml
patterns:
  - shape: match input { $(item:exp) => item }
```

如果需要匹配源码层面的名称，请使用 `$(name:id)`。它可以绑定简单变量目标、binder、裸标识符表达式、限定函数名、构造器 identity、简单变量模式，以及方法名、字段名、带标签参数名和记录字段标签等标签。

如果需要匹配字面常量，请使用 `$(name:const)`。它只在整个裸标识符表达式位置或简单 pattern variable 位置有效，并且只匹配解析后的 MoonBit 常量。重复使用同一个 `const` kind 名称时，常量 kind 和存储值都必须相等。它不会匹配变量、构造器、标签、操作符、限定标识符或普通 binder。

如果需要捕获完整函数调用参数槽，请使用 `$(name:arg)`。它只在调用 pattern 的整个裸位置参数中有效：

```yaml
patterns:
  - shape: sink($(arg:arg))
```

该占位符可以匹配候选中的 positional、labelled、labelled pun、optional labelled 和 optional pun 参数。捕获值是完整 `Argument` AST 节点，包括参数 kind、标签和值。

如果需要捕获完整 MoonBit 类型 AST 节点，请使用 `$(name:type)`。它必须占据一个完整类型节点，例如标注、类型参数、option 类型、tuple 成员或函数类型组成部分：

```yaml
patterns:
  - shape: |
      let value : $(T:type) = input
  - shape: |
      let values : Array[$T] = input
```

捕获值是完整 `Type` AST 节点。重复使用同一个 `type` 名称时，捕获到的类型节点必须结构相等；源码位置会被忽略。`type` 不捕获方法类型限定符或构造器 extra-info 等类型名 identity 位置；这些名称请使用 `id`。

如果需要捕获整个 pattern AST，请使用 `$(name:pat)`。它只在简单 pattern variable 位置有效：

```yaml
patterns:
  - shape: match input { $(item:pat) => item }
```

### 内置通配符

精确拼写 `$_` 在出现在可绑定位置时是忽略占位符：

```yaml
patterns:
  - shape: foo($_)
```

忽略占位符会匹配该位置上的任何内容。它不绑定值，重复出现的忽略占位符彼此独立：

```yaml
patterns:
  - shape: pair($_, $_)
```

上面的例子可以匹配 `pair(left, right)`。

只有精确的 `$_` 具有这种内置行为。`__`、`___` 和 `__x` 等名称默认是字面量。`$__` 或 `$(__x:exp)` 等内联语法会把它们标记为元变量。

### `exp`

`exp` 元变量捕获其所在位置的解析后表达式。重复使用同一个 `exp` 名称时，后续捕获必须具有相等的表达式结构；源码位置会被忽略。

示例：

```yaml
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

它可以匹配下面这样的例子：

```moonbit
x == x
record.field == record.field
make(value) == make(value)
```

它不会匹配：

```moonbit
x == y
make(value) == make(other)
```

当同一个源码层面的名称出现在不同语法角色中时，例如一次作为 binder，之后作为标识符表达式出现，`exp` 通常不是合适选择。此时应使用 `id`。

重复 `exp` 相等性由 untyped AST 节点比较保证：比较节点 kind 和子值，并忽略源码位置。它不再限定为一组固定表达式形状。AST 结构不同的语义等价代码不会匹配。占位符可以吸收结构差异。

### `id`

`id` 元变量捕获归一化后的源码层面名称。重复使用同一个 `id` 名称时，每次出现都必须归一化为同一个字符串。限定函数名会归一化为 `@pkg.name`。限定构造器 identity 会包含 extra info，例如 `@pkg.Ctor`、`Type::Ctor`、`@pkg.Type::Ctor` 或 `@pkg.Type::@other.Ctor`。

当规则需要比较 binder 和后续使用时，这很有用：

```yaml
patterns:
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

它可以匹配：

```moonbit
for i = 0; i < n; i = i + 1 {
  println(i)
}
```

当重复的源码层面名称不同时，它不会匹配：

```moonbit
for i = 0; j < n; i = i + 1 {
  println(i)
}
```

归一化目前适用于简单和限定变量名、binder、裸标识符表达式、构造器 identity、简单变量模式和标签。限定函数名会保留包限定符，例如 `@pkg.name`；限定构造器 identity 会保留 extra info。

### `const`

`const` 元变量捕获解析后的 MoonBit 常量。在表达式位置，它匹配 `Expr::Constant`；在 pattern 位置，它匹配 `Pattern::Constant`。

示例：

```yaml
patterns:
  - shape: $(value:const) + $(value:const)
```

它可以匹配：

```moonbit
1 + 1
"same" + "same"
```

它不会匹配：

```moonbit
1 + 2
x + x
```

也支持 pattern 常量：

```yaml
patterns:
  - shape: match input { $(lit:const) => lit }
```

内部 body 通过普通 payload 名称 `lit` 引用外层常量捕获。

### `arg`

`arg` 元变量捕获完整调用参数节点。当规则需要在一个参数槽中接受任意参数写法，同时又希望重复出现时比较整个参数槽，使用它很合适。

示例：

```yaml
patterns:
  - shape: sink($(arg:arg))
```

它可以匹配这些单参数调用：

```moonbit
sink(value)
sink(label=value)
sink(label~)
sink(label?=value)
sink(label?)
```

重复使用同一个 `arg` 名称时，完整参数节点必须结构相等；源码位置会被忽略。参数 kind、标签和值都必须相同。`sink($(arg:arg), $(arg:arg))` 可以匹配 `sink(value, value)` 和 `sink(label=value, label=value)`。它不会匹配 `sink(value, other)` 或 `sink(label=value, other=value)`。

`arg` 只能显式使用。`sink($arg)` 中的裸 `$arg` 按普通裸元变量推导处理。该名称在别处的显式 kind 声明决定其 kind，没有这类声明时它是 `exp` 捕获。`$(arg:arg)` 必须占据整个参数槽；`sink(label=$(arg:arg))`、`sink($(arg:arg) + 1)` 和根 shape `$(arg:arg)` 都无效。

### `type`

`type` 元变量捕获完整 MoonBit `Type` AST 节点。它可以匹配 `Int` 或 `T` 这样的简单类型名和类型变量，也可以匹配 `Array[Int]`、`T?`、tuple 和函数类型等复合类型。

示例：

```yaml
patterns:
  - shape: |
      let left : $(T:type) = input; let right : $(T:type) = input
```

它可以匹配：

```moonbit
let left : Int = input; let right : Int = input
let left : Array[String] = input; let right : Array[String] = input
```

它不会匹配：

```moonbit
let left : Int = input; let right : String = input
```

`type` 捕获必须占据完整类型节点。下面写法无效：

```yaml
patterns:
  - shape: sink($(T:type))
  - shape: $(T:type)(value)
```

### `pat`

`pat` 元变量捕获整个候选 `Pattern` AST。它只在简单 pattern variable 位置有效。

示例：

```yaml
patterns:
  - shape: match input { $(item:pat) => body }
```

重复使用同一个 `pat` 名称时，捕获到的 pattern 必须结构相等。

## Guard

结构规则的 pattern object（包括 `patterns`、`patterns-not`、
`inside-expr` 和 `inside-toplevel`）可以包含可选的 `guard` 映射。guard 的键是带
`$` 前缀的捕获名，值是正则字符串：

```yaml
patterns:
  - shape: $(callee:id)($(value:const))
    guard:
      $callee: "^@html\\.render$"
      $value: "danger|raw"
```

只有 `id` 和 `const` 捕获可以被 guard 过滤。guard 键如果引用 `exp` 捕获、
`arg` 捕获、`pat` 捕获、`type` 捕获或未知名称，会在规则编译时报错。内部 `patterns` 可以
guard 由 `inside-expr` 或 `inside-toplevel` 建立的 `id` 和 `const` 捕获。

Guard 会在结构 AST 匹配成功后检查。单个 pattern object 中的所有 guard 都必须
匹配，即 AND 语义。正则使用包含匹配语义；如果需要整串匹配，请使用 `^...$`
这样的锚点。

对于 `id` 捕获，正则看到的是归一化后的标识符字符串，例如 `name` 或
`@pkg.name`。对于 `const` 捕获，正则看到的是 parser 常量值：字符串常量不含引号，
数字常量保留源码文本，布尔值为 `true` 或 `false`。

## 结构规则

结构规则具有非空 `patterns` 数组，或者具有 `inside-expr` 或
`inside-toplevel` 并搭配非空 `patterns`、非空 `patterns-not`，或两者同时存在。

```yaml
id: repeated-equality
description: |
  Repeated equality.
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

结构规则会应用到从源文件收集到的表达式子树。目前，结构匹配会搜索顶层表达式、函数、方法、顶层 `let` 定义、测试和 view 中的表达式主体。

每个被访问的表达式都会被每条结构规则检查。对于一个被访问表达式和一条规则：

- `patterns` 条目是有序备选项
- 第一个匹配的正向 pattern 会产生一个命中，并且该候选表达式子树会对这条规则剪枝
- 如果所有正向 pattern 都失败，才会针对当前候选表达式根检查
  `patterns-not`
- 如果此时负向 pattern 匹配，该候选表达式子树会对这条规则剪枝，且不会产生命中
- 兄弟表达式子树以及其他规则会继续扫描

报告的 pattern index 从零开始，指向 `patterns` 中匹配的条目。

同一条规则中的所有 pattern 共享同一个规则 id 和 `description`。

### `patterns-not`

`patterns-not` 是结构规则的负向约束。它的条目使用与 `patterns` 相同的
`shape` 和可选 `guard` schema。

```yaml
id: unblocked-target
description: |
  Match target calls outside blocked wrappers.
patterns:
  - shape: target()
patterns-not:
  - shape: blocked($(value:exp))
```

对于带 `patterns` 的普通结构规则，每个候选表达式根都会先运行有序的正向 pattern。只要正向 pattern 匹配，就报告命中，并且不会再为该候选检查 `patterns-not`。只有所有正向 pattern 都失败后，才会检查 `patterns-not`。负向匹配没有初始绑定。只在 `patterns-not` 中声明的内联元变量独立绑定，不复用 `patterns` 中的捕获。

如果正向 pattern 全部失败后负向 pattern 匹配，该候选不会产生命中，并且它的子表达式不会再为这条规则搜索。如果正向和负向 pattern 都不匹配，则继续进入该候选的子表达式。

负向 pattern 只匹配当前候选根。在上面的例子中，`blocked` 根先未命中所有正向 pattern，随后命中 `patterns-not`。该分支被剪枝，`blocked(target())` 不会搜索内部的 `target()`。如果某个 `blocked(...)` 节点本身也能命中正向 pattern，它会被报告，并且不会检查 `patterns-not`。需要排除同根形状时，应把正向 pattern 写得更窄。

与 `inside-expr` 或 `inside-toplevel` 一起使用时，负向匹配会带着外层匹配建立的绑定开始。如果规则同时有 `patterns`，捕获到的 `__TARGET__` 子树中的每个表达式都使用相同的步进顺序：先运行正向 pattern；只有正向 pattern 全部失败后，才检查 `patterns-not`。当外层上下文、`patterns` 和 `patterns-not` 同时存在时，正向命中的整个子树会覆盖负向匹配；任何出现在这些正向覆盖子树之外的负向命中都会拒绝整个外层匹配。`patterns-not` 也可以与只有 `inside-expr` 或 `inside-toplevel`、没有 `patterns` 的规则一起使用；这种形式见下文。

### `inside-expr`

`inside-expr` 将结构规则限制在更大的表达式上下文内部匹配。它可以搭配
`patterns`、`patterns-not`，或两者同时使用。

```yaml
id: wrapped-target
description: |
  Match a target call only inside wrapper(...).
inside-expr:
  shape: wrapper($(prefix:exp), __TARGET__)
patterns:
  - shape: target.call($(prefix:exp))
```

`inside-expr` 是 YAML 映射。它的 `shape` 会作为一个 MoonBit 表达式片段解析；
可选 `guard` 会过滤这个外层 shape 声明的 `id` 和 `const` 捕获。

额外规则：

- `inside-expr` 必须在可绑定位置包含且只包含一个 `__TARGET__`。
- `__TARGET__` 必须占据一个完整表达式位置，例如完整调用参数、receiver 或块表达式。如果它只作为标签或其他非表达式值出现，就没有目标子树可供搜索。
- `__TARGET__` 是保留名称，不能用作内联元变量名。
- `patterns` 和 `patterns-not` 条目不能在可绑定位置包含 `__TARGET__`。
- `inside-expr` 声明的内联元变量在匹配内部 `patterns` 和
  `patterns-not` 时可见；内部 shape 通过重复相同的内联元变量形式引用它们。
- 内部 `patterns` 和 `patterns-not` 不能用不同 kind 使用已经从
  `inside-expr` 可见的元变量名。

运行时行为：

- 当前表达式首先与 `inside-expr` 匹配
- 如果匹配成功，会搜索由 `__TARGET__` 捕获的子树
- 当存在 `patterns` 时，捕获子树中的每个表达式会先用
  `inside-expr` 建立的绑定运行有序正向 pattern；正向命中会被报告，其命中子树会覆盖嵌套的负向匹配
- 当同时存在 `patterns` 和 `patterns-not` 时，只有正向 pattern 全部失败的候选才会用 `inside-expr` 绑定检查 `patterns-not`；正向命中子树之外的负向命中会拒绝整个外层匹配
- 当不存在 `patterns` 时，捕获子树中的每个表达式都会用 `inside-expr` 绑定检查 `patterns-not`；如果没有任何负向 pattern 匹配，外层表达式产生一个命中
- 如果内部 pattern 通过相同的 `$(name:id)` inline 形式引用了继承来的 `id` 捕获，并且从 `__TARGET__` 到候选表达式的路径上出现了同名（按规范化后的 identifier 名称计算）的词法绑定，则跳过该候选

带 `patterns` 的 `inside-expr` 命中报告位置是内部正向匹配位置。只有
`patterns-not` 的 `inside-expr` 规则报告外层表达式位置。暴露上下文位置的消费者也可以通过 `outer_loc` 暴露外层表达式位置。

### `inside-toplevel`

`inside-toplevel` 将结构规则限制在某个 MoonBit 顶层项内部匹配。它使用与
`inside-expr` 相同的对象 schema 和 target 子树语义。它的 `shape`
解析为且只能解析为一个顶层项，不解析为表达式。

```yaml
id: safe-function-target
description: |
  Match calls only in selected top-level functions.
inside-toplevel:
  shape: |
    fn $(name:id)($(param:id) : Int) -> Int { __TARGET__ }
  guard:
    $name: "^safe_"
patterns:
  - shape: call($(param:id))
```

额外规则：

- `inside-toplevel` 和 `inside-expr` 互斥。
- `inside-toplevel` 必须在顶层项内的可绑定表达式位置包含且只包含一个
  `__TARGET__`。
- 顶层项本身可以声明 `id` 和 `const` 捕获，可选 `guard` 可以过滤这些捕获。
- `inside-toplevel` 声明的内联元变量在内部 `patterns` 和 `patterns-not`
  中保持可见，并使用与 `inside-expr` 相同的继承绑定和 kind 一致性规则。
- taint 规则不支持 `inside-toplevel`。

运行时行为与 `inside-expr` 一致：候选顶层项先与 `inside-toplevel` 匹配；
如果匹配成功，会在 `__TARGET__` 捕获到的表达式子树中用继承绑定继续搜索。
带 `patterns` 时，报告的 `loc` 是内部正向匹配位置；只有 `patterns-not`
时，报告的 `loc` 是匹配到的顶层项位置。两种形式的 `outer_loc` 都是匹配到的顶层项位置。

## 污点规则

污点规则具有顶层 `taint` 映射。

`taint` 内只接受这些键：

- `sources`（必需）：非空数组
- `sinks`（必需）：非空数组
- `sanitizers`（可选）：数组，默认为空

`taint` 内的未知键会被拒绝。

每个数组条目都是包含 `shape` 的 pattern object；taint 子句中会拒绝
`guard`。

示例：

```yaml
id: raw-html
description: |
  Raw user input reaches an HTML sink.
taint:
  sources:
    - shape: get_user_input()
  sinks:
    - shape: render_html(__SOURCE__)
  sanitizers:
    - shape: sanitize_html(__SOURCE__)
```

### Taint Shape 限制

每个 taint `shape` 都必须是直接调用或方法调用。

有效形式包括：

```moonbit
source()
receiver.method(arg)
sink(label=arg)
```

pipe 和 reverse-pipe 语法目前不是有效的 taint 规则 shape。源程序在解析后可能包含这类调用。

`__SOURCE__` 在 taint 子句中是保留名称：

- source shape 不能包含 `__SOURCE__`
- sink shape 必须且只能包含一个 `__SOURCE__`
- sanitizer shape 必须且只能包含一个 `__SOURCE__`
- 在 sink 和 sanitizer 中，`__SOURCE__` 必须是整个 receiver 或整个参数值

有效的 sink 和 sanitizer 目标：

```yaml
taint:
  sources:
    - shape: source()
  sinks:
    - shape: sink(__SOURCE__)
    - shape: sink(label=__SOURCE__)
    - shape: __SOURCE__.dangerous()
```

无效的目标放置：

```yaml
taint:
  sources:
    - shape: source()
  sinks:
    - shape: sink(wrap(__SOURCE__))
```

无效示例将 `__SOURCE__` 嵌套在另一个表达式内部。有效 shape 会把它作为整个参数值使用。

### 污点语义

污点分析是过程内分析。它目前分析函数体和方法体。顶层 let、测试、view、顶层表达式以及没有 body 的声明不会进行污点分析。

对于一条污点规则：

- 匹配 source 调用会将调用结果标记为 tainted
- 匹配 sink 调用会在选中的 `__SOURCE__` receiver 或参数为 tainted 时报告
- 匹配 sanitizer 调用不会产生 tainted 返回数据
- 匹配 sanitizer 只会在选中的 `__SOURCE__` 值是 storage path 时清除该值的已存储污点，例如变量、字段访问、元组字段访问或数组访问
- 未匹配的调用对污点没有影响

YAML 污点规则目前没有过程间传播。如果 tainted 数据传入的 helper 调用没有匹配同一规则中的 source、sink 或 sanitizer 子句，这个调用不会把污点传播到它的返回值。

当一个调用匹配多种 taint 子句类型时，效果顺序如下：

- 如果一个调用同时匹配 source 和 sanitizer，source 返回污点会产生
- 如果一个调用同时匹配 sink 和 sanitizer，sink 会使用 sanitizer 效果影响后续读取之前的污点状态进行报告

taint 命中报告的 pattern index 是匹配 sink 条目的零基索引。

## 错误条件

当出现以下任一条件时，规则集或规则文件会被拒绝：

- 规则根目录不包含 `.yaml` 或 `.yml` 文件
- 规则文件包含零个 YAML 文档或多个 YAML 文档
- 顶层 YAML 文档不是映射
- 顶层、`taint` 内或 pattern object 内出现不支持的键
- 缺少必需键
- `id`、`description` 或 `shape` 不是 YAML 字符串
- `id` 为空或包含 `/`
- 规则没有选择结构模式或污点模式
- taint 规则中出现 `inside-expr`
- taint 规则中出现 `inside-toplevel`
- 同时出现 `inside-expr` 和 `inside-toplevel`
- `inside-expr` 的值不是映射
- `inside-toplevel` 的值不是映射
- `inside-expr` 出现时没有 `patterns` 或 `patterns-not`
- `inside-toplevel` 出现时没有 `patterns` 或 `patterns-not`
- `patterns` 不是数组或为空
- `patterns` 条目不是映射
- `patterns-not` 不是数组或为空
- `patterns-not` 没有和 `patterns`、`inside-expr` 或 `inside-toplevel`
  一起出现
- taint 规则中出现 `patterns-not`
- 出现不支持的顶层键
- `patterns-not` 条目不是映射
- `taint` 不是映射
- `taint.sources` 或 `taint.sinks` 缺失、不是数组或为空
- `taint.sanitizers` 的值不是数组
- taint 子句条目不是映射
- 结构规则的 `guard` 值不是映射，或 guard 值不是字符串
- taint 子句中出现 `guard`
- 任何 pattern object 中出现 `metavars`
- `shape` 不是一个有效的 MoonBit 表达式
- `inside-toplevel.shape` 不是且只有一个有效的 MoonBit 顶层项
- shape 使用不支持的内联元变量 kind
- shape 跨多个元变量 kind 使用同一个内联元变量名
- 裸 `$name` 无法推导为一个兼容的 kind
- 裸 `$name` 只出现在有歧义的简单 pattern variable 位置
- 内联元变量使用保留名称
- `$(name:exp)` 出现在裸表达式位置之外
- `$(name:const)` 出现在常量表达式或常量 pattern 位置之外
- `$(name:arg)` 出现在裸参数位置之外
- `$(name:pat)` 出现在裸 pattern 位置之外
- `$(name:type)` 出现在完整类型位置之外
- guard 键没有 `$` 前缀，或引用未知捕获、`exp` 捕获、`arg` 捕获、`pat` 捕获、`type` 捕获或 ellipsis 捕获
- ellipsis 没有占据完整的无字段名有序列表项
- ellipsis kind 与列表位置不兼容、与另一个 typed occurrence 冲突，或和普通元变量共用名称
- guard 正则无效
- `inside-expr` 没有且只有一个可绑定的 `__TARGET__`
- `inside-toplevel` 没有且只有一个可绑定的 `__TARGET__`
- 结构规则的 `patterns` 或 `patterns-not` 条目包含可绑定的 `__TARGET__`
- 结构规则的 `patterns` 或 `patterns-not` 条目用不同 kind 使用了继承自
  `inside-expr` 或 `inside-toplevel` 的元变量名
- taint source 包含可绑定的 `__SOURCE__`
- taint sink 或 sanitizer 没有且只有一个可绑定的 `__SOURCE__`
- taint sink 或 sanitizer 没有将 `__SOURCE__` 放在整个 receiver 或整个参数值的位置
- taint source、sink 或 sanitizer shape 不是直接调用或方法调用

## 示例

### 有序结构备选项

```yaml
id: collect-output
description: |
  These helpers collect full child-process output before returning.
patterns:
  - shape: $(command:exp).output_collect($(args:exp))
  - shape: $(command:exp).stderr_collect($(args:exp))
```

两个备选项会产生相同的规则 id 和 description。报告的 pattern index 用于区分匹配的是哪个 shape。

### Binder 和使用处名称比较

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

`counter` 会在 binder、条件和更新位置之间按源码层面的名称比较。`start`、`limit` 和 `body` 是表达式捕获。

### 限制上下文的结构匹配

```yaml
id: unsafe-wrapper
description: |
  Match a sink only under an unsafe wrapper.
inside-expr:
  shape: unsafe(__TARGET__)
patterns:
  - shape: sink($_)
```

该规则首先寻找 `unsafe(...)`，然后只在 `__TARGET__` 捕获的表达式内搜索 `sink(...)`。

### 带 Guard 的结构匹配

```yaml
id: guarded-render
description: |
  Raw-looking constants rendered through html.
patterns:
  - shape: $(callee:id)($(value:const))
    guard:
      $callee: "^@html\\.render$"
      $value: "danger|raw"
```

shape 会捕获任意单参数且参数为常量的调用。guard 随后只保留归一化 callee 为
`@html.render`，且常量值包含 `danger` 或 `raw` 的调用。

### Taint Source、Sink 和 Sanitizer

```yaml
id: raw-html
description: |
  Raw user input reaches an HTML sink.
taint:
  sources:
    - shape: get_user_input()
  sinks:
    - shape: render_html(__SOURCE__)
  sanitizers:
    - shape: sanitize_html(__SOURCE__)
```

`get_user_input()` 会污染其结果。`render_html(__SOURCE__)` 会在其实参被污染时报告。`sanitize_html(__SOURCE__)` 会在选中的值可以作为 storage 追踪时，阻止该值向后续读取贡献污点。
