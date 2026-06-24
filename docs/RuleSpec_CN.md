# 规则规范

本文档是 moongrep 接受的 YAML 规则的权威规范。

如果你是第一次编写规则，请先阅读 [WritingRules.md](WritingRules.md)。

## 范围和状态

本文档规定当前 YAML 规则文件格式、校验规则和匹配语义。

关键词 "must"、"must not"、"may" 和 "currently" 描述的是规则作者今天可以依赖的行为。本规范有意避免描述源码布局、语法处理内部细节、具体数据类型或实现中的函数名。

规则使用 YAML 编写，但每个 `shape` 值都是 MoonBit 表面语法。扫描器匹配的是解析后的 MoonBit 表达式结构，而不是原始文本。因此，格式和注释不重要；表达式形式、操作符、字面量值、标签、被调用名称和参数结构是重要的，除非通配符或声明的元变量另有规定。

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

规则 id 由规则文件路径派生：

- 取相对于规则根目录的文件路径
- 移除末尾的 `.yaml` 或 `.yml` 后缀
- 保留剩余路径中的目录分隔符

示例：

```text
rules/security/raw-html.yaml -> security/raw-html
rules/style.yml              -> style
```

规则 id 必须唯一。此外，将 `/` 和 `-` 替换为 `_` 后，两个 id 也不能变成相同字符串。

## YAML Schema

### 顶层键

只接受这些顶层键：

- `package`（必需）：YAML 字符串
- `description`（必需）：YAML 字符串
- `patterns`（结构规则必需）：非空 YAML 数组
- `inside-expr`（结构规则可选）：一个作为外层上下文的 pattern object
- `taint`（污点规则必需）：YAML 映射

未知顶层键会被拒绝。

每条规则必须且只能选择一种规则模式：

- 结构模式：`patterns`
- 污点模式：`taint`

`patterns` 和 `taint` 互斥。`inside-expr` 只在与 `patterns` 一起使用时有效；它在污点规则中会被拒绝。

`package` 是元数据。它是必需字段且必须是字符串，但不会过滤候选源文件。`description` 也是必需字段且必须是字符串。它的内容会按 YAML 提供的结果保留，包括 block scalar 产生的尾随换行。

### Pattern Objects

`patterns` 中的条目、`inside-expr` 以及 taint `sources`、`sinks` 和 `sanitizers` 中的条目使用相同的对象 schema。

只接受这些键：

- `shape`（必需）：包含一个 MoonBit 表达式片段的 YAML 字符串
- `metavars`（可选）：YAML 映射或数组简写
- `guard`（保留）：目前在所有位置都会被拒绝

pattern object 中的未知键会被拒绝。

`guard` 目前不受支持。任何 pattern object 中包含 `guard` 的规则都是无效规则。

## Shapes

`shape` 必须是一个单独的 MoonBit 表达式片段。

有效 shape 包括调用、方法调用、字段访问、操作符、块、条件表达式、循环、match、lambda、集合字面量、记录表达式，以及其他表达式大小的 MoonBit 语法。shape 不是整个文件、顶层声明、包片段或 import 列表。

shape 是结构性的：

- 未声明的标识符和标签按字面匹配
- 常量按值匹配
- 操作符按字面匹配
- 调用和方法调用的参数种类、标签、顺序和数量必须匹配
- 匹配语法中出现的类型注解和类型名必须匹配
- 源码位置、格式和注释不参与匹配

扫描器不会对 shape 做类型检查，也不会按语义解析名称。例如，两个不同的导入名称即使指向同一定义，仍然是不同的；除非它们解析后的源码拼写一致，或被元变量捕获。

## 元变量

shape 中的标识符默认都是字面量。只有在 `metavars` 下声明后，一个名称才会成为元变量；下面描述的内置通配符除外。

### 语法

`metavars` 可以是映射：

```yaml
metavars:
  subtree: [expr, body]
  identifier: [name]
```

映射形式只接受这些键：

- `subtree`：可选的字符串数组
- `identifier`：可选的字符串数组

省略的 bucket 默认为空数组。bucket 值必须是数组，且每个条目都必须是字符串。同一个 bucket 内的重复名称会被拒绝。同一个名称不能同时出现在 `subtree` 和 `identifier` 中。

不存在 `auto` 映射 bucket。下面是无效写法：

```yaml
metavars:
  auto: [x]
```

请使用数组简写声明 auto 元变量：

```yaml
metavars: [x, y]
```

每个简写条目都必须是字符串，重复名称会被拒绝。

### 保留名称

这些名称在任何规则子句中都不能声明为元变量：

- 只由两个或更多下划线组成的名称，例如 `__`、`___` 或 `____`
- `__TARGET__`

在 taint 子句中，`__SOURCE__` 也是保留名称，不能被声明。

`__SOURCE__` 在结构规则中没有内置含义。如果它没有被声明，也没有作为 taint sink 或 sanitizer 使用，它就只是一个字面名称。

### 元变量可以绑定的位置

声明的元变量必须至少出现在一个可以绑定值的位置。当前可以绑定的位置包括：

- 裸标识符表达式，例如 `value`
- 简单变量目标，例如 `x = y` 左侧，或表达式语法中表示为变量的操作符 token
- binder，例如函数参数、循环变量、`let mut` binder 或 lambda 参数
- 简单变量模式，例如 `match value { item => ... }` 中的 `item`
- 标签，例如方法名、字段名、带标签参数名或记录字段标签

校验还会查看许多普通表达式容器，包括调用、字段访问、操作符、块、数组、元组、记录、循环、match、try/catch、lambda、插值和推导式。

模式校验有意比完整模式匹配更窄。直接变量模式以及 alias、tuple、`or` 和 range 模式内的名称会计入校验。只出现在 constructor、array、record、map、constraint 或 special-constructor 模式内部的名称，运行时仍可能参与匹配，但目前不能单独满足“声明的元变量已使用”校验。

如果声明的名称只出现在不能绑定的位置，该规则会因未使用的元变量而无效。

### 内置通配符

只由两个或更多下划线组成的名称在出现在可绑定位置时是忽略占位符：

```yaml
patterns:
  - shape: foo(__)
```

忽略占位符会匹配该位置上的任何内容。它不绑定值，重复出现的忽略占位符彼此独立：

```yaml
patterns:
  - shape: pair(__, __)
```

上面的例子可以匹配 `pair(left, right)`。

只有全下划线名称具有这种内置行为。像 `__x` 这样的名称是字面量，除非它被声明为普通元变量。

MoonBit 表达式 hole，例如在被解析为表达式 hole 的位置出现的 `_`，也会匹配该位置上的任意表达式。

### `subtree`

`subtree` 元变量捕获其所在位置的解析后语法。重复使用同一个 `subtree` 名称时，后续捕获必须具有相同的语法位置种类，并且解析后的结构相等；源码位置会被忽略。

示例：

```yaml
patterns:
  - shape: _expr == _expr
    metavars:
      subtree: [_expr]
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

当同一个源码层面的名称出现在不同语法角色中时，例如一次作为 binder，之后作为标识符表达式出现，`subtree` 通常不是合适选择。此时应使用 `identifier`。

重复 `subtree` 相等性目前保证支持常见表达式形式，包括标识符、hole、常量、unit、中缀表达式、调用、方法调用、字段访问、方法引用、构造器表达式、分组表达式、块、数组字面量、元组字面量和 `for` 表达式。某些表达式和模式形式可以单次匹配，但尚不支持重复 `subtree` 相等性。如果重复 `subtree` 捕获使用了不支持的相等形式，该次匹配会失败，而不会产生命中。

### `identifier`

`identifier` 元变量捕获归一化后的源码层面名称。重复使用同一个 `identifier` 名称时，每次出现都必须归一化为同一个字符串。

当规则需要比较 binder 和后续使用时，这很有用：

```yaml
patterns:
  - shape: |
      for counter = _start; counter < upper_limit; counter = counter + 1 {
        body
      }
    metavars:
      subtree: [_start, upper_limit, body]
      identifier: [counter]
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

归一化目前适用于简单非限定变量名、binder、裸标识符表达式、简单变量模式和标签。限定名称不会为了此用途归一化为简单标识符。

### Auto Metavars

数组简写声明 auto 元变量：

```yaml
metavars: [value]
```

auto 元变量会根据它捕获的第一个候选项选择模式：

- 如果候选项可以归一化为标识符，它表现得像 `identifier`
- 否则它表现得像 `subtree`

后续出现必须匹配第一次选择的模式和值。

示例：

```yaml
patterns:
  - shape: value + value
    metavars: [value]
```

它可以同时匹配：

```moonbit
item + item
make() + make()
```

它不会匹配混合或不相等的捕获：

```moonbit
item + make()
make() + other()
```

## 结构规则

结构规则具有非空 `patterns` 数组。

```yaml
package: moonbitlang/core
description: |
  Repeated equality.
patterns:
  - shape: _expr == _expr
    metavars:
      subtree: [_expr]
```

结构规则会应用到从源文件收集到的表达式子树。目前，结构匹配会搜索顶层表达式、函数、方法、顶层 `let` 定义、测试和 view 中的表达式主体。

每个被访问的表达式都会被每条结构规则检查。对于一个被访问表达式和一条规则：

- `patterns` 条目是有序备选项
- 第一个匹配的 pattern 会产生一个命中
- 同一规则中后续 pattern 不会再为该表达式检查
- 扫描仍会继续进入其他表达式子树

报告的 pattern index 从零开始，指向 `patterns` 中匹配的条目。

同一条规则中的所有 pattern 共享同一个规则 id、`package` 和 `description`。

### `inside-expr`

`inside-expr` 将结构规则限制在更大的表达式上下文内部匹配。

```yaml
package: moonbit-community/example
description: |
  Match a target call only inside wrapper(...).
inside-expr:
  shape: wrapper(prefix, __TARGET__)
  metavars:
    subtree: [prefix]
patterns:
  - shape: target.call(prefix)
```

`inside-expr` 使用与 `patterns` 条目相同的 pattern-object schema。

额外规则：

- `inside-expr.shape` 必须在可绑定位置包含且只包含一个 `__TARGET__`。
- `__TARGET__` 必须占据一个完整表达式位置，例如完整调用参数、receiver 或块表达式。如果它只作为标签或其他非表达式值出现，就没有目标子树可供搜索。
- `__TARGET__` 不能在 `metavars` 下声明。
- `patterns` 条目不能在可绑定位置包含 `__TARGET__`。
- `inside-expr` 声明的元变量在匹配内部 `patterns` 时仍然可见。
- 内部 `patterns` 不能重新声明已经从 `inside-expr` 可见的元变量名。

运行时行为：

- 当前表达式首先与 `inside-expr` 匹配
- 如果匹配成功，会搜索由 `__TARGET__` 捕获的子树
- 捕获子树中的每个表达式都会被 `patterns` 检查
- 内部 pattern 匹配会带着 `inside-expr` 已建立的绑定开始

`inside-expr` 命中的报告位置是内部匹配位置。暴露上下文位置的消费者也可以暴露外层表达式位置。

## 污点规则

污点规则具有顶层 `taint` 映射。

`taint` 内只接受这些键：

- `sources`（必需）：非空数组
- `sinks`（必需）：非空数组
- `sanitizers`（可选）：数组，默认为空

`taint` 内的未知键会被拒绝。

每个数组条目都是 pattern object，包含 `shape`、可选 `metavars`，且不支持 `guard`。

示例：

```yaml
package: example/html
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

pipe 和 reverse-pipe 语法目前不是有效的 taint 规则 shape，即使源程序在解析后可能包含这类调用。

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

无效示例将 `__SOURCE__` 嵌套在另一个表达式内部，而不是把它作为整个参数值使用。

### 污点语义

污点分析是过程内分析。它目前分析函数体和方法体。顶层 let、测试、view、顶层表达式以及没有 body 的声明不会进行污点分析。

对于一条污点规则：

- 匹配 source 调用会将调用结果标记为 tainted
- 匹配 sink 调用会在选中的 `__SOURCE__` receiver 或参数为 tainted 时报告
- 匹配 sanitizer 调用不会产生 tainted 返回数据
- 匹配 sanitizer 只会在选中的 `__SOURCE__` 值是 storage path 时清除该值的已存储污点，例如变量、字段访问、元组字段访问或数组访问
- 未匹配的调用对污点没有影响

YAML 污点规则目前没有过程间传播。如果 tainted 数据传入一个 helper 调用，而该调用没有匹配同一规则中的 source、sink 或 sanitizer 子句，那么这个 helper 调用不会把污点传播到它的返回值。

当一个调用匹配多种 taint 子句类型时，效果顺序如下：

- 如果一个调用同时匹配 source 和 sanitizer，source 返回污点仍会产生
- 如果一个调用同时匹配 sink 和 sanitizer，sink 会使用 sanitizer 效果影响后续读取之前的污点状态进行报告

taint 命中报告的 pattern index 是匹配 sink 条目的零基索引。

## 错误条件

当出现以下任一条件时，规则集或规则文件会被拒绝：

- 规则根目录不包含 `.yaml` 或 `.yml` 文件
- 规则文件包含零个 YAML 文档或多个 YAML 文档
- 顶层 YAML 文档不是映射
- 顶层、`taint` 内、pattern object 内或 `metavars` 映射内出现不支持的键
- 缺少必需键
- `package`、`description` 或 `shape` 不是 YAML 字符串
- 规则没有且只有一个 `patterns` 或 `taint`
- taint 规则中出现 `inside-expr`
- `inside-expr` 存在但不是映射
- `patterns` 不是数组或为空
- `patterns` 条目不是映射
- `taint` 不是映射
- `taint.sources` 或 `taint.sinks` 缺失、不是数组或为空
- `taint.sanitizers` 存在但不是数组
- taint 子句条目不是映射
- 任何 pattern object 中出现 `guard`
- `metavars` 既不是映射也不是数组
- `metavars` 映射 bucket 不是数组
- `metavars` 映射 bucket 包含非字符串条目
- `metavars` 简写包含非字符串条目
- 元变量名在 bucket 或简写数组内重复
- 元变量名同时出现在 `subtree` 和 `identifier` 中
- 元变量声明使用保留名称
- 声明的元变量从未出现在可绑定位置
- `shape` 不是一个有效的 MoonBit 表达式
- `inside-expr.shape` 没有且只有一个可绑定的 `__TARGET__`
- 结构规则的 `patterns` 条目包含可绑定的 `__TARGET__`
- 结构规则的 `patterns` 条目重新声明了已经由 `inside-expr` 声明的名称
- taint source 包含可绑定的 `__SOURCE__`
- taint sink 或 sanitizer 没有且只有一个可绑定的 `__SOURCE__`
- taint sink 或 sanitizer 没有将 `__SOURCE__` 放在整个 receiver 或整个参数值的位置
- taint source、sink 或 sanitizer shape 不是直接调用或方法调用
- 两个规则 id 在将 `/` 和 `-` 替换为 `_` 后冲突

## 示例

### 有序结构备选项

```yaml
package: moonbitlang/async/process
description: |
  These helpers collect full child-process output before returning.
patterns:
  - shape: _command.output_collect(_args)
    metavars:
      subtree: [_command, _args]
  - shape: _command.stderr_collect(_args)
    metavars:
      subtree: [_command, _args]
```

两个备选项会产生相同的规则 id、package 和 description。报告的 pattern index 用于区分匹配的是哪个 shape。

### Binder 和使用处名称比较

```yaml
package: moonbitlang/core
description: |
  Counter-style `for` loop.
patterns:
  - shape: |
      for counter = _start; counter < upper_limit; counter = counter + 1 {
        body
      }
    metavars:
      subtree: [_start, upper_limit, body]
      identifier: [counter]
```

`counter` 会在 binder、条件和更新位置之间按源码层面的名称比较。`_start`、`upper_limit` 和 `body` 是结构捕获。

### 限制上下文的结构匹配

```yaml
package: moonbit-community/example
description: |
  Match a sink only under an unsafe wrapper.
inside-expr:
  shape: unsafe(__TARGET__)
patterns:
  - shape: sink(__)
```

该规则首先寻找 `unsafe(...)`，然后只在 `__TARGET__` 捕获的表达式内搜索 `sink(...)`。

### Taint Source、Sink 和 Sanitizer

```yaml
package: example/html
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
