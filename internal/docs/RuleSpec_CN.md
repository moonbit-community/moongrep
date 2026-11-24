# 规则规范

`moongrep` 规则使用 YAML 编写，并以 MoonBit 表面语法片段作为匹配模式。关于命令行
规则选择、扫描、输出格式和退出码，请参阅 [CLISpec_CN.md](CLISpec_CN.md)。

## 匹配模型概览

每个 `shape` 都是 MoonBit 表面语法，解析为无类型具体语法树（CST）后按结构比较：

- **忽略项**：空白排版、源码位置、注释（包括文档注释）。
- **参与匹配项**：表达式形式、操作符、标签、被调用名称、参数结构（参数种类、
  标签、顺序、数量），以及出现的类型标注与类型名。
- **常量**：按解析器 CST 常量种类和保留的源码拼写比较，而非规范化后的语义值。
  因此 `1000` 和 `1_000` 不一定匹配。
- **不做类型检查或语义名称解析**：两个指向同一定义的导入名称，只在源码拼写一致
  或被元变量捕获时才视为匹配。

通配符与元变量按下文规则放宽上述精确结构约束。

## 规则文件与规则 ID

### 发现规则与文件格式

规则根目录是存放 YAML 规则文件的目录：

- 递归发现路径以精确小写 `.yaml` 或 `.yml` 结尾的文件（全平台区分大小写），忽略
  其他文件。
- 发现的规则文件按排序顺序处理。
- 规则目录的符号链接会被跟随。
- 未发现任何规则文件的规则根目录无效。
- 每个规则文件必须恰好包含一个顶层为映射的 YAML 文档，定义且只定义一条规则。
- 通过 `--rule` 选择单个文件时，其后缀同样必须是精确小写 `.yaml` 或 `.yml`；与
  目录发现不同，不支持的后缀会被直接拒绝而非忽略。

平台路径处理差异：

- **Linux 和 macOS**：保留用户提供的规则根目录拼写，使用 `/` 拼接路径；相对目录
  采用区分大小写的字符串前缀算法，`..` 保持字面含义。
- **Windows**：在访问文件系统前对规则根目录及单文件路径做词法规范化（不解析符号
  链接），递归发现使用 `\` 拼接。相对目录按 Windows 路径语义计算（前缀比较不区分
  大小写；跨盘符、跨 UNC server/share 或通过 `..` 逃出根目录的路径会被拒绝），
  并在拼接 YAML `id` 前将 `\` 转为 `/`。

### 规则 ID 派生

最终规则 ID 为 `<相对目录>/<id>`；当文件直接位于规则根目录下（包括单文件
`--rule`，其所在目录即为规则根目录）时，最终 ID 就是 `<id>`：

- 文件名不参与规则 ID 构成。
- YAML `id` 不能为空且不能包含 `/`。
- 规则 ID 与 YAML `id` 在所有平台（含 Windows）上均区分大小写，且在加载后的规则
  集中必须唯一。

```text
rules/example.yaml                  (id: target-call) -> target-call
rules/security/raw.yaml             (id: unsafe-html) -> security/unsafe-html
rules/security/nested/raw.yml       (id: unsafe-html) -> security/nested/unsafe-html
```

## YAML Schema

### 顶层字段

| 字段 | 必填 | 规则类型 | 说明 |
| --- | --- | --- | --- |
| `id` | 是 | 全部 | 当前目录内的局部规则名（不含 `/` 的非空字符串）。 |
| `description` | 是 | 全部 | 说明文本字符串，按 YAML 原样保留（含块标量末尾换行）。 |
| `patterns` | 条件必填 | 结构规则 | 非空正向模式数组。除非同时提供 `inside-toplevel` 与 `patterns-not`，否则结构规则必填。 |
| `patterns-not` | 否 | 结构规则 | 非空负向模式数组。 |
| `inside-toplevel` | 否 | 结构规则 | 非空有序顶层上下文数组（可选 `match-mode`）。 |
| `taint` | 条件必填 | 污点规则 | 包含 `sources`、`sinks` 及可选 `sanitizers` 的映射，与所有结构字段互斥。 |

- `then` 只能出现在正向模式对象内，不能出现在规则根层级。
- 根层级、`taint` 内或模式对象内的任何未知字段都会被拒绝。

### 模式对象字段

| 子句类型 | 允许的字段 |
| --- | --- |
| 正向 `patterns`（及嵌套 `then.patterns`） | `shape`（必填）、`guard`（可选）、`then`（可选） |
| 负向 `patterns-not`（及嵌套 `then.patterns-not`） | `shape`（必填）、`guard`（可选） |
| `inside-toplevel` | `shape`（必填）、`guard`（可选）、`match-mode`（可选：`exact` 或 `partial`） |
| 污点 `sources` / `sinks` / `sanitizers` | 仅 `shape`（必填），拒绝 `guard` |

旧版 `metavars` 字段已废弃，出现在任何模式对象中都会被拒绝。

## 匹配模式（`shape`）

- 普通 `patterns`、`patterns-not`、`then` 和污点子句的 `shape` 必须解析为**一个
  MoonBit 表达式**（调用、方法调用、字段访问、操作符、块、条件、循环、match、
  lambda、集合字面量、记录表达式等；不接受整个文件、顶层声明、包片段或 import
  列表）。
- 每个 `inside-toplevel` 的 `shape` 必须解析为**恰好一个 MoonBit 顶层项**（函数、
  顶层 `let`/`const`、`test`、方法 `impl` 或 view；不接受整个文件或 import 列表）。

### 函数体与显式块

函数、方法、测试、lambda 和局部函数外层的花括号充当匹配容器，而不是显式块表达式
候选：

- 函数体内的语句组成一个 sequence 候选，其中每个表达式仍可独立搜索。
- `$_` 和 `$(root:exp)` 会搜索函数体内部表达式，而不会捕获函数体外层花括号。
- 多语句 `shape` 可以匹配 body sequence；其命中范围从第一条命中语句到最后一条命中
  语句，不包含外层花括号。
- 作为表达式写出的嵌套块仍是显式块候选，其范围包含花括号。例如 `{ a; b }` 不匹配
  `fn sample { a; b }` 的函数体，但会匹配 `fn sample { { a; b } }` 中的嵌套块。

普通扫描、`then` 目标、`inside-toplevel` 目标和 `ExprQuery` 共用同一套候选边界
和范围规则（包括嵌套闭包内）。选中的函数体仍保持 sequence 容器角色，不会将其花括号
暴露为显式块；空序列和部分 continuation 保留精确的语句边界。

### 省略 body 的快捷模式（`let` 与 `guard`）

不带显式 continuation 的单语句普通 `let` 或 `guard` 模式称为 **header pattern**：
它匹配头部结构，但不约束候选 sequence suffix 中后续的 continuation。

```yaml
patterns:
  - shape: let $(name:id) = $(value:exp)
  - shape: guard ready() else { fallback() }
```

它们既能匹配独立语句，也能匹配带任意后续语句的序列：

```moonbit
let item = load()
let item = load(); consume(item)
let item = load(); { trace(item); item }

guard ready() else { fallback() }
guard ready() else { fallback() }; continue_work()
guard ready() else { fallback() }; { prepare(); finish() }
```

如需约束或捕获 continuation，请显式写出：

- **匹配特定后续**：`let $(name:id) = $(value:exp); consume($(name:id))` 或
  `guard ready() else { fallback() }; continue_work()`
- **捕获任意后续**：`let $(name:id) = $(value:exp); $(body:exp)` 或
  `guard ready() else { fallback() }; $(body:exp)`
- **要求显式 unit body**：`let $(name:id) = $(value:exp); ()` 或
  `guard ready() else { fallback() }; ()`（按结构精确匹配，不是通配符）

当前结构 `shape` 无法表达“只匹配语法上省略了 body 的 `let`/`guard`”。

适用范围限制：

- **仅适用于**普通 `let` 和 `guard`。
- `let mut`、局部函数、`letrec`、`defer` 和 `errdefer` 使用普通结构匹配，只写
  header 不会匹配带 continuation 的候选。
- `proof_let` 是独立表达式候选，匹配其 header 只覆盖 `proof_let` 本身，后续表达式
  仍可继续搜索。

## 元变量

`shape` 中的标识符和标签默认按字面匹配，除非使用内联元变量语法或内置忽略占位符
`$_`。

### 语法与裸名称推导

显式带类别写法为 `$(name:kind)`；常见场景下可省略类别写作裸 `$name`：

```yaml
patterns:
  - shape: $(left:exp) == $(left:exp)
  - shape: $value + $value
  - shape: |
      for $(counter:id) = $(start:exp); $(counter:id) < $(limit:exp); $(counter:id) = $(counter:id) + 1 {
        $(body:exp)
      }
```

单个 `shape` 内名称类别的解析规则：

- 同一名称在一个 `shape` 中必须保持单一类别（例如混用 `$(name:exp)` 和
  `$(name:id)` 无效）。
- 若某处显式写出了 `$(name:kind)` 且位置兼容，它将决定同一名称其他裸 `$name` 的
  类别。
- 否则，裸 `$name` 采用保守推导：
  - 出现在绑定、标签、构造器、类型名或限定标识符位置时推导为 `id`。
  - 占据完整类型节点（如 `Array[$T]`）时推导为 `type`。
  - 仅出现在表达式占位位置且未被前两条规则决定时，推导为 `exp`。
  - `const`、`arg`、`pat` **绝不**从裸 `$name` 自动推导。例如
    `match input { $item => body }` 因在 `id`/`const`/`pat` 间有歧义会被拒绝，
    须显式写为 `$(item:id)`、`$(item:const)` 或 `$(item:pat)`；完整调用参数须写
    `$(name:arg)`。

### 支持的元变量类别

| 类别 | 有效位置 | 捕获节点 | 重复捕获比较规则 | 支持 guard？ |
| --- | --- | --- | --- | --- |
| `exp` | 完整裸标识符表达式位置 | 候选表达式 CST | 忽略源码位置的结构 CST 相等 | 否 |
| `id` | 变量目标、binder、裸标识符表达式、限定函数名、构造器 identity、简单变量 pattern，或标签（方法名/字段名/标签参数名/记录字段标签） | 候选语义名称 CST | 规范化名称字符串（如 `name`、`@pkg.name`、`Type::Ctor`、`@pkg.Type::@other.Ctor`） | 是 |
| `const` | 完整裸标识符表达式（`Expr_Constant`）或简单 pattern 变量（`Pattern_Constant`） | 候选常量 CST | 解析器 CST 常量种类与保留源码拼写（如 `1000` != `1_000`） | 是 |
| `arg` | 调用中的完整裸位置参数槽（仅显式） | 完整 `Argument` CST（种类、标签、值） | 忽略源码位置的结构 CST 相等 | 否 |
| `pat` | 简单 pattern 变量位置（仅显式） | 完整 `Pattern` CST | 忽略源码位置的结构 CST 相等 | 否 |
| `type` | 完整类型节点（类型标注、类型参数、option、tuple 成员、函数类型）；名称必须以大写字母开头 | 完整 `Type` CST | 忽略源码位置的结构 CST 相等 | 否 |

各类别补充说明：

- **`exp`**：比较任意表达式结构（例如 `$(expr:exp) == $(expr:exp)` 匹配
  `x == x`、`record.field == record.field`、`make(value) == make(value)`，不匹配
  `x == y`）。同一源码名称跨角色（如声明与引用）使用时请改用 `id`。`$(item:exp)`
  不能放在 pattern binder 位置。
- **`id`**：跨语法角色比较规范化后的名称（如 `for` 循环的 binder、条件和更新）。
  限定函数名规范化为 `@pkg.name`；限定构造器保留 extra info（如 `@pkg.Ctor`、
  `Type::Ctor`、`@pkg.Type::Ctor`、`@pkg.Type::@other.Ctor`）。
- **`const`**：只匹配解析后的字面常量（如 `1 + 1`、`"same" + "same"`、
  `match input { $(lit:const) => $(lit:const) }`）。每次复用捕获都必须重复元变量
  语法，普通 `lit` 仍是字面标识符。
- **`arg`**：匹配位置参数（`sink(value)`）、标签参数（`sink(label=value)`）、
  pun（`sink(label~)`）、可选标签参数（`sink(label?=value)`）与可选 pun
  （`sink(label?)`）。必须占据整个参数槽，`sink(label=$(arg:arg))`、
  `sink($(arg:arg) + 1)` 和根 shape `$(arg:arg)` 均无效。
- **`type`**：匹配简单类型（`Int`、`T`）及复合类型（`Array[Int]`、`T?`、tuple、
  函数类型）。不用于方法类型限定符或构造器 extra-info 等类型名 identity 位置（那些
  位置请用 `id`）；也不能用于 `sink($(T:type))` 或 `$(T:type)(value)` 等表达式/
  调用位置。
- **`pat`**：在简单 pattern 变量位置捕获完整 `Pattern` CST（如
  `match input { $(item:pat) => body }`）。

### 省略号元变量（`$$$`）

`$$$name` 捕获无类型 CST 有序列表中的零个或多个连续 sibling；`$$$(name:kind)` 用
`exp`、`id`、`const`、`arg`、`pat` 或 `type` 约束捕获到的每一项：

```yaml
patterns:
  - shape: inspect($$$args)
  - shape: pair([$$$(items:exp)], [$$$items])
```

位置与命名规则：

- 必须占据无类型 CST 中无字段名的完整子项（参数列表、表达式列表、形参列表、
  pattern 列表、类型列表）。不能作为根、具名字段、标签、节点一部分或块的最终值
  （最终值后无 `Syntax_Token(TK_SEMI)`）。
- 裸命名省略号的类别为 `AnyItem`；若同名位置存在带类别写法，则由其决定所有裸位置
  的类别。
- `type` 元变量（单个或省略号）名称必须以大写字母开头（如 `$(T:type)`、
  `$$$(Types:type)`）；类型列表拒绝小写名称及匿名通配符（`$$$_`、`$$$(_:type)`）。
- 普通元变量与省略号不能共用名称，冲突的显式类别会被拒绝。
- 类型位置之外，`$$$_` 和 `$$$(_:kind)` 是不绑定的独立通配符。
- `guard` 不能引用省略号捕获。

各类列表支持的项类别：

| 列表类型 | 支持的项类别 |
| --- | --- |
| 表达式列表 | `exp`、`id`、`const`（同对应单节点元变量） |
| 调用实参列表 | `arg` 接受全部参数写法（位置、标签、pun、可选标签、可选 pun）；`exp`、`id`、`const` 只接受值满足对应类别的位置参数 |
| Pattern 列表 | `pat` |
| 类型列表 | `type`（仅大写命名形式） |
| 形参列表 | `id`（带 binder 的 parameter 项） |

匹配与绑定语义：

- 从左到右匹配。遇到省略号时从空序列开始尝试最短捕获，失败时恢复绑定并逐步增长，
  直到剩余列表匹配成功。空捕获满足任何类别约束。
- 捕获数组始终保存原始完整 sibling CST 节点（如 `Argument`、`Parameter` 或表达式
  节点）。
- 同名省略号重复出现时，要求捕获数组等长且逐元素忽略源码位置后结构相等。
- 上下文（`then` / `inside-toplevel`）继承 `Multiple` 值的方式与其他绑定一致，
  内部重复省略号须使用相同类别。继承的 `id` 省略号还会按顺序逐元素检查原始词法
  绑定（空列表满足检查）。
- 污点 sink 和 sanitizer 模式可在唯一的完整参数或 receiver `__SOURCE__` 前后使用
  省略号。

公开 API 中的 `BoundValue` 表示（定义于 `model`，由 `query` 重导出）：

- 普通捕获为 `Single(CstNode)`；省略号捕获为 `Multiple(Array[CstNode])`。
- 捕获展开 continuation 的末尾具名表达式元变量或特殊 target，在 suffix 仅含一条
  语句时为 `Single`，为空或含多条语句时为 `Multiple`。
- 末尾的 `$_` continuation 通配符不绑定，不产生 `BoundValue`。

### 内置通配符与保留名称

以下保留名称不可用作内联元变量名：

- `$_` — 内置忽略占位符。
- `__TARGET__` — 仅用于 `then` 和 `inside-toplevel`。
- `__SOURCE__` — 仅用于污点 sink 和 sanitizer 模式。

`$_` 的行为：

- 在除下述末尾 continuation 外的任意可绑定位置，精确无限定拼写 `$_` 匹配单个节点
  且不绑定，多个 `$_` 相互独立（如 `pair($_, $_)` 可匹配 `pair(left, right)`）。
- 当表达式序列**恰好**由一个 continuation owner（普通 `let`、`let mut`、局部函数、
  `letrec`、`guard`、`defer`、`errdefer`）加末尾 `$_` 组成时，`$_` 匹配整个剩余
  suffix（零条、一条或多条表达式），且不产生 `$_` 或 `_` 绑定。该规则同样适用于
  嵌套块，但不适用于非末尾 `$_`、含其他 sibling 的 owner 或 `proof_let`。
- 仅精确拼写 `$_` 具备内置通配语义；`__`、`___`、`__x` 等默认是字面量，需用 `$`
  语法（如 `$__`、`$(__x:exp)`）才成为元变量。

## Guard

任意结构模式对象（`patterns`、`patterns-not`、`then`、`inside-toplevel`）均可
附加可选 `guard` 映射，键为带 `$` 前缀的捕获名，值为正则字符串：

```yaml
patterns:
  - shape: $(callee:id)($(value:const))
    guard:
      $callee: "^@html\\.render$"
      $value: "danger|raw"
```

- **支持的捕获**：仅 `id` 和 `const` 捕获（包括从 `then` 或 `inside-toplevel`
  继承的 `id`/`const`）。引用 `exp`、`arg`、`pat`、`type`、省略号或未知名称会在
  编译期报错。
- **求值规则**：在结构 CST 匹配通过后执行；同一 `guard` 映射内所有条件为逻辑
  AND。正则默认按子串匹配，需整串匹配请加 `^...$`。
- **正则输入文本**：
  - `id`：规范化后的标识符字符串（如 `name`、`@pkg.name`）。
  - `const`：解析器常量值——字符串不含引号、数字保留源码文本、布尔值为 `true` 或
    `false`。

## 结构规则

结构规则包含非空 `patterns` 数组，或由 `inside-toplevel` 搭配非空 `patterns`、
非空 `patterns-not` 或两者共同组成。

```yaml
id: repeated-equality
description: |
  Repeated equality.
patterns:
  - shape: $(expr:exp) == $(expr:exp)
```

### 求值顺序与去重

结构规则搜索顶层函数、方法、顶层 `let`/`const`、测试和 view 中的表达式主体。

对每个访问到的候选表达式和每条规则：

1. 按 YAML 顺序尝试 `patterns`。首个同时通过 `shape`、`guard` 和可选 `then` 的
   正向条目报告一次命中，并对该规则剪枝整个候选子树。
2. 仅当**所有**正向条目均失败时，才针对当前候选根检查 `patterns-not`。
3. 若负向模式命中，则对该规则剪枝该候选子树且不报告命中。
4. 否则继续深入候选的子表达式。兄弟子树与其他规则不受影响。

同一规则内所有模式共享规则 ID 和 `description`。在同一个已解析源码块内，结构
finding 按 `(file, rule_id, 完整起止源码范围)` 去重，保留首次命中的
`pattern_index`、描述和发布顺序；不同规则、不同范围及独立解析的源码块各自保留
结果。

### `patterns-not`

`patterns-not` 表示结构负向约束，使用与 `patterns` 相同的 `shape` 和可选
`guard` 格式：

```yaml
id: unblocked-target
description: |
  Match target calls outside blocked wrappers.
patterns:
  - shape: target()
patterns-not:
  - shape: blocked($(value:exp))
```

- 在根层级（不带 `then` / `inside-toplevel`），负向匹配从空绑定开始（与
  `patterns` 独立），仅在所有正向模式都未命中时检查当前候选根。上例中
  `blocked(target())` 先未命中 `target()`，随后命中 `blocked(...)` 并剪枝子树，
  因此内部的 `target()` 不会报告。如果某节点自身能直接命中正向模式，则不会检查
  `patterns-not`；需要排除同根形态时应收窄正向模式。
- 在 `then` 或 `inside-toplevel` 内，负向匹配继承外层绑定。同时存在 `patterns` 与
  `patterns-not` 时，正向命中会覆盖其整个匹配子树；任何出现在这些正向覆盖子树之外
  的负向命中都会否决整个外层匹配。

### 嵌套约束（`then`）

每个正向 `patterns` 条目均可附带一个 `then` 对象，仅接受 `patterns` 和
`patterns-not`（至少出现其一，且出现的数组必须非空）。正向子条目可继续嵌套任意
有限层 `then`。诊断包含完整 YAML 路径（例如 `patterns[0].then.patterns[1].then`）。

```yaml
id: nested-target
description: Match a target inside selected wrappers.
patterns:
  - shape: wrapper($(name:id), __TARGET__)
    then:
      patterns:
        - shape: container(__TARGET__)
          then:
            patterns:
              - shape: target()
                guard:
                  $name: '^safe_'
            patterns-not:
              - shape: danger()
```

位置与求值规则：

- 带 `then` 的 `shape` 必须在可绑定完整表达式位置**恰好包含一个** `__TARGET__`。
  叶子正向条目和负向条目禁止出现 `__TARGET__`。`patterns-not`、污点子句和
  `inside-toplevel` 条目本身不接受 `then`（但 `inside-toplevel` 内的正向条目可以
  使用 `then`）。
- 正向条目必须同时通过 `shape`、`guard` 和 `then` 才算命中；`then` 失败时会尝试
  同级后续条目（**不会**回溯重试同一 `shape` 的其他省略号划分）。
- 某层嵌套组失败只令所属正向条目失败，不会否决祖先或兄弟备选。

| 嵌套组组成 | 成功条件 |
| --- | --- |
| 仅 `patterns` | 至少一个完整正向条目命中。 |
| 仅 `patterns-not` | 无负向命中（空目标也算成功）。 |
| 同时包含 `patterns` 与 `patterns-not` | 至少一个正向命中，且不存在未覆盖的负向命中。 |

- 成功的正向条目覆盖其整个匹配子树（包括自带 `then` 的条目）。所有适用的负向检查
  全部通过后才发布 finding。
- 每次 finding 使用**根级** `patterns` 条目的源码位置，内部多次命中只报告一次。
- continuation owner（`let`、`let mut`、`guard`）之后的 `__TARGET__` 选中完整
  剩余表达式序列（允许为空）。函数体保持 sequence 匹配，显式块保持块匹配。目标
  允许等于当前候选本身（递归沿有限规则树下降）。

继承捕获与词法绑定检查：

- 捕获对整条后代链可见，即使中间层的 `shape` 未引用它们；本层新增捕获不会泄漏给
  父层或兄弟条目。
- 复用继承名称时要求类别（含省略号类别）和值一致。`guard` 可直接引用祖先 `id` 或
  `const` 捕获，无需在当前 `shape` 中重复写出。
- 标识符捕获跨层（含 `inside-toplevel`）保留**首次捕获来源**：变量 binder 记录其
  声明产生的绑定，变量引用记录该出现位置可见的绑定，自由变量保持未绑定（后续同名
  局部声明会遮蔽它）。选中 target 绝不会重新按名称解析捕获。
- 继承的 `id` **仅在**来源与当前出现位置都是词法变量（引用或 binder）时比较词法
  绑定；任一侧为非词法名称（字段、标签、构造器、类型名等）时退回规范化名称比较，
  因此允许同名变量与字段跨角色复用。
- 每次出现均按其真实源码位置检查（后续声明不会使先前引用失效）。对
  `$$$(names:id)` 而言，除数组等长与结构相等外，还会按顺序逐元素校验词法绑定，
  捕获值仍保持原始完整列表项。
- 同一 `shape` 内新捕获的重复出现沿用普通名称/结构相等规则，并保留首次捕获来源。
- `guard` 读取继承的词法 `id` 时，要求原始绑定在候选入口可见（非词法名称无此
  要求）。
- 继承绑定不一致属于原子匹配失败，省略号回溯会连同捕获值与来源信息一起回滚并尝试
  其他划分。

旧字段 `inside-expr` 迁移说明：

- 旧 `inside-expr` 键已移除，使用时会报迁移错误。将每个旧外层备选移至根
  `patterns`，并将原内部 `patterns` / `patterns-not` 放入对应条目的 `then` 中，
  保持顺序与 `guard`。注意这会改变备选回退和成功后的子树剪枝行为，并非等价改名。

### 顶层上下文（`inside-toplevel`）

`inside-toplevel` 将结构规则限定在选定的 MoonBit 顶层项内，是非空有序的
`{ shape, guard?, match-mode? }` 数组，每个 `shape` 解析为恰好一个顶层项：

```yaml
id: safe-function-target
description: |
  Match calls only in selected top-level functions.
inside-toplevel:
  - shape: |
      fn $(name:id)($(param:id) : Int) -> Int { __TARGET__ }
    guard:
      $name: "^safe_"
patterns:
  - shape: call($(param:id))
```

`match-mode` 解析规则（各备选项独立解析）：

| `match-mode` | `shape` 顶层项类型 | 实际匹配模式 |
| --- | --- | --- |
| 省略 | 函数定义 | `partial` |
| 省略 | 其他顶层项 | `exact` |
| `exact` | 任意顶层项 | `exact` |
| `partial` | 函数定义 | `partial` |
| `partial` | 其他顶层项 | 编译错误 |

- **`exact`**：精确比较解析后的顶层语义 CST 的每个字段（docstring 属于注释，在
  任何模式下均不约束匹配）。
- **`partial`**（仅限函数定义）：函数名、函数体和 `__TARGET__` 始终精确匹配；
  仅当 `shape` 将以下函数头字段保留为缺省形态时才忽略它们：类型限定、`async`、
  参数列表、类型参数、返回类型、错误类型、可见性、attribute 以及顶层 `where`
  子句。一旦显式写出（如 `fn f()`、`pub fn`、`async fn`、返回类型、`noraise`、
  类型参数、attribute 或 `where`），该字段即按精确模式匹配。
- **迁移提示**：旧规则若依赖“省略的函数头字段必须不存在”，需显式添加
  `match-mode: exact`。

选择与报告语义：

- 每个 `inside-toplevel` 条目必须在可绑定表达式位置恰好包含一个 `__TARGET__`，
  可声明 `id` / `const` 捕获并用可选 `guard` 过滤。
- 后代 `shape` 或 `guard` 引用的任何继承捕获，必须在**每一个** `inside-toplevel`
  备选项中均有声明且类别一致（含省略号类别）。
- 按 YAML 顺序尝试备选项；首个同时通过 `shape` 和 `guard` 的条目选定目标与绑定
  （选定后不再尝试后续条目）。
- `__TARGET__` 子树沿用 `then` 的继承绑定与负向覆盖语义。
- **报告位置**：带 `patterns` 时，每个内部正向命中在内部匹配位置报告 finding；
  仅带 `patterns-not`（且无负向命中）时，在匹配到的顶层项位置报告一条 finding。
- 污点规则不支持 `inside-toplevel`。

## 污点规则

污点规则使用顶层 `taint` 映射（与所有结构字段互斥）：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `sources` | 是 | 非空 `{ shape }` 数组，标记污点来源。 |
| `sinks` | 是 | 非空 `{ shape }` 数组，检查 `__SOURCE__` 处的污点。 |
| `sanitizers` | 否 | `{ shape }` 数组，清除 `__SOURCE__` 处的污点（默认为空）。 |

`taint` 及其子句中拒绝 `guard` 和任何未知字段。

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

### 污点模式限制

- 每个污点 `shape` 必须是直接调用或方法调用（`source()`、`receiver.method(arg)`、
  `sink(label=arg)`）。pipe 和 reverse-pipe 语法目前不能作为污点规则 `shape`
  （源程序中仍可使用管道调用，分析器会对其进行规范化）。
- `__SOURCE__` 约束：
  - `sources` **不能**包含 `__SOURCE__`。
  - `sinks` 和 `sanitizers` 必须**恰好包含一个** `__SOURCE__`，且必须位于整个
    receiver（`__SOURCE__.dangerous()`）或整个参数值位置（`sink(__SOURCE__)`、
    `sink(label=__SOURCE__)`）。
  - 嵌套写法（如 `sink(wrap(__SOURCE__))`）无效。

### 污点语义

污点分析为**过程内分析**，作用于函数体和方法体（顶层 `let`/`const`、测试、view
以及无 body 声明不参与污点分析）。

针对单条污点规则：

- 命中 **source** 的调用会污染其返回值。
- 命中 **sink** 的调用在所选 `__SOURCE__`（receiver 或参数）被污染时报告 finding。
- 命中 **sanitizer** 的调用不产生受污染的返回值，且仅在 `__SOURCE__` 为存储路径
  （变量、字段访问、元组字段访问或数组访问）时清除该路径上已存储的污点。
- 未命中的调用不传播污点（YAML 规则当前不支持过程间传播）。
- **同一调用命中多类子句时的优先级**：
  - 同时命中 source 和 sanitizer：仍产生 source 返回污点。
  - 同时命中 sink 和 sanitizer：sink 使用 sanitizer 影响后续读取**之前**的污点
    状态进行报告。

### 控制流与分析不完整

- 分析器保留短路路径、同时循环更新与 `continue` 参数、退出时执行的 `defer` 以及
  仅异常退出时执行的 `errdefer`。
- 整体污点会流入字段和数组元素。已知字段和常量数组索引支持精确覆盖和净化，同时
  保留兄弟路径。动态索引写入采用保守语义，动态索引净化不会清除无法唯一确定的元素。
- 不做隐式控制流污点传播或通用堆别名分析；未知调用不隐式抛异常，当前 YAML 规则
  不支持声明异常调用模型。
- 遇到不支持的可执行语法时跳过受影响函数并输出 `taint_incomplete` 警告；某个
  SCC 在 `64` 轮内未收敛时跳过该函数对应规则的全部结果。两者均不发布部分
  finding，其他函数与规则继续扫描。
- 启用 `--strict-taint` 时，扫描结束后若存在任何污点分析不完整（含妨碍污点分析的
  解析失败），命令以状态码 `8` 退出。

## 错误条件

出现以下任意情况时，规则集或规则文件会被拒绝：

### 规则发现与 YAML 结构

- 规则根目录不含任何 `.yaml` 或 `.yml` 文件。
- `--rule` 指定的单文件后缀不是精确小写 `.yaml` 或 `.yml`。
- 规则文件包含零个或多个 YAML 文档，或顶层文档不是映射。
- 已加载规则集中存在重复的规则 ID。

### 顶层 Schema 与字段

- 顶层、`taint` 内或任意模式对象内出现不支持的键（包括已移除的 `metavars` 与
  `inside-expr`）。
- 缺少必填键，或 `id`、`description`、`shape` 不是字符串。
- `id` 为空或包含 `/`。
- 规则既未指定结构模式也未指定污点模式，或混用 `taint` 与结构字段（`patterns`、
  `patterns-not`、`inside-toplevel`）。
- `patterns` 或 `patterns-not` 不是非空数组，或其中条目不是映射。
- 提供了 `inside-toplevel` 却既无 `patterns` 也无 `patterns-not`。
- `match-mode` 出现在 `inside-toplevel` 之外，取值不是 `exact` / `partial`，或在
  非函数顶层项上使用 `partial`。
- `taint` 不是映射；`taint.sources` 或 `taint.sinks` 缺失、非数组或为空；
  `taint.sanitizers` 非数组；或任一污点子句条目不是映射。

### 模式与元变量

- 普通 `shape` 不是单个有效 MoonBit 表达式，或 `inside-toplevel` 的 `shape` 不是
  恰好一个有效顶层项。
- 使用不支持的元变量类别、保留名称（`$_`、`__TARGET__`、`__SOURCE__`），或同一
  名称跨多个类别使用。
- 裸 `$name` 无法推导为单一兼容类别，或仅出现在有歧义的简单 pattern 变量位置。
- `$(name:exp)` 位于裸表达式之外；`$(name:const)` 位于常量表达式或常量 pattern
  之外；`$(name:arg)` 位于裸调用参数槽之外；`$(name:pat)` 位于裸 pattern 位置
  之外；或 `$(name:type)` 位于完整类型位置之外。
- 省略号未占据完整的无字段名有序列表项；类别与列表位置不兼容或与其他显式类别
  冲突；或与普通元变量共用名称。

### Guard

- 结构规则的 `guard` 不是映射，或其中任意值不是字符串。
- 任意污点子句中出现 `guard`。
- guard 键缺少 `$` 前缀，或引用未知捕获、`exp`、`arg`、`pat`、`type` 或省略号
  捕获。
- guard 正则表达式语法无效。

### 上下文（`then` 与 `inside-toplevel`）

- `inside-toplevel` 条目或带 `then` 的正向条目未恰好包含一个可绑定 `__TARGET__`。
- 结构规则叶子或 `patterns-not` 条目包含可绑定 `__TARGET__`。
- `then` 对象含未知键、非法/空数组，或同时缺少 `patterns` 与 `patterns-not`。
- 后代 `patterns` 或 `patterns-not` 用不同类别复用了继承自 `then` 或
  `inside-toplevel` 的元变量名。
- 后代 `shape` 或 `guard` 引用的继承捕获在某个 `inside-toplevel` 备选项中缺失或
  类别不一致（含省略号类别）。

### 污点子句

- 任意污点 `shape` 不是直接调用或方法调用。
- 污点 `source` 包含可绑定的 `__SOURCE__`。
- 污点 `sink` 或 `sanitizer` 未恰好包含一个可绑定 `__SOURCE__`，或未将其放在整个
  receiver / 整个参数值位置。

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

两个备选项共享同一个规则 ID 和 `description`。

### 比较声明与使用处的名称

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

`counter` 跨 binder、条件和更新位置按规范化名称比较；`start`、`limit` 和 `body`
捕获表达式。

### 限制上下文的结构匹配

```yaml
id: wrapped-sink
description: |
  Match a sink only under a selected wrapper.
patterns:
  - shape: wrapper(__TARGET__)
    then:
      patterns:
        - shape: sink($_)
```

先匹配 `wrapper(...)`，再仅在 `__TARGET__` 捕获的表达式内搜索 `sink(...)`。

### 负向结构约束

```yaml
id: unblocked-target
description: |
  Match target calls outside blocked wrappers.
patterns:
  - shape: target()
patterns-not:
  - shape: blocked($(value:exp))
```

每个候选根先尝试 `patterns` 再尝试 `patterns-not`。对于 `blocked(target())`，外层
未命中 `target()`、随后命中 `blocked(...)` 并剪枝子树，因此内部的 `target()` 不会
报告。负向模式中的捕获与正向模式相互独立。

### 无正向内层模式的上下文

```yaml
id: wrapper-without-danger
description: |
  Match wrappers whose payload contains no danger call.
patterns:
  - shape: wrapper(__TARGET__)
    then:
      patterns-not:
        - shape: danger()
```

当 `wrapper(...)` 的 `__TARGET__` 子树中不包含任何 `danger()` 调用时，在
`wrapper(...)` 处报告命中。

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

先匹配任意带常量参数的单参调用，再由 `guard` 筛选规范化被调用名为 `@html.render`
且常量值包含 `danger` 或 `raw` 的调用。

### 污点来源、汇点与净化器

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

`get_user_input()` 污染其返回值，`render_html(__SOURCE__)` 在实参受污染时报告，
`sanitize_html(__SOURCE__)` 在实参可解析为存储路径时清除已存储的污点。
