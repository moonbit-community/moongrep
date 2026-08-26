# 命令行接口规范

本文档规定当前 moongrep 命令行接口，包括命令选择、规则来源选择、扫描、输出、
诊断和进程退出行为。

[RuleSpec_CN.md](RuleSpec_CN.md) 规定 YAML 规则格式、规则校验和匹配器语义。
除非某一节另有说明，否则路径和规则 id 都按区分大小写的字符串比较。

## 调用与命令选择

### 调用形式

直接运行已安装的可执行文件：

```text
moongrep <command> [arguments]
```

通过 Moon 运行已发布的 WebAssembly 可执行文件：

```text
moonx moonbit-community/moongrep -- <command> [arguments]
```

通过 `moonrun` 运行本地 WebAssembly 产物：

```text
moonrun path/to/moongrep.wasm -- <command> [arguments]
```

在 WebAssembly 调用形式中，`--` 分隔 runner 参数和 moongrep 参数。分隔符后的
参数按直接运行可执行文件的方式处理。

### 顶层命令

moongrep 提供四个命令：

- `scan` 使用显式选择或默认规则扫描 MoonBit 源码。
- `lint` 默认启用内嵌 builtin 规则扫描 MoonBit 源码。
- `docs` 列出或打印内嵌文档。
- `dump` 解析一个 MoonBit 实现项或表达式，并打印 CST 调试输出。

不带命令运行 moongrep 时，程序会打印缺少子命令的诊断和顶层帮助，然后以状态码
2 退出。

### 帮助和无参数行为

`-h` 和 `--help` 打印当前命令的帮助。`help` 命令打印顶层帮助，
`help <command>` 打印指定命令的帮助。这些形式都以状态码 0 退出。

选定命令但不提供其他参数时，各命令按以下方式运行：

- `scan` 使用扫描根 `.` 和默认规则目录 `./.moongrep/rules` 开始正常扫描。
- `lint` 使用扫描根 `.` 并启用 builtin 规则开始正常扫描。
- `docs` 打印 `docs` 帮助并以状态码 0 退出。
- `dump` 打印 `dump` 帮助并以状态码 0 退出。

帮助文本写入标准输出。

## `scan` 和 `lint`

### 语法

```text
moongrep scan [options] [scan-root]
moongrep lint [options] [scan-root]
```

最多接受一个 `scan-root` 位置参数。它可以出现在选项之前、之间或之后。省略时
其值为 `.`。

### 选项

两个命令都接受：

- `-r <dir>` 或 `--rules <dir>`：选择包含 YAML 规则的目录。
- `--rule <file>`：选择一个 YAML 规则文件。
- `--pattern <source>`：添加一个匿名结构模式。
- `--guard <yaml>`：为前面的匿名模式附加 YAML guard 映射。
- `--exclude <name-or-path>`：跳过匹配的文件或目录条目。
- `--disable <rule-id>`：禁用精确匹配的已加载规则 id。
- `--verbose`：把规则加载和遍历事件写入标准错误。
- `--output-json`：以 JSON Lines 格式输出命中。
- `-h` 或 `--help`：打印命令帮助。

两个命令都不接受 `--enable-builtin-rules`。内嵌 builtin 规则只能通过 `lint`
选择。

带值的长选项同时接受 `--option value` 和 `--option=value`。其中，`--rules` 也有
短形式。`NO_COLOR` 环境变量按下文规则控制颜色。

### 扫描根

`scan-root` 可以指向目录或一个普通文件。目录目标会被递归遍历。普通文件目标的
路径以小写 `.mbt` 结尾时会被扫描。

在 Linux 和 macOS 上，扫描器保留提供的扫描根拼写，并按下文遍历规则使用 `/`
构造子路径。

在 Windows 上，扫描根会在任何文件系统操作前进行词法规范化。`/` 和 `\` 都可
作为分隔符；重复分隔符以及 `.`、`..` 路径分量按 Windows 路径规则规范化。
子路径使用原生分隔符连接。文件系统访问、命中位置、warning、verbose 事件和
JSON 输出都使用同一个规范化原生路径，因此渲染路径使用 `\`。规范化不会调用
`realpath`，也不会把相对扫描根变成绝对路径。

### 规则来源和顺序

`scan` 和 `lint` 可以组合规则来源。无论相关选项出现在什么位置，来源始终按以下
类别顺序加载：

1. `lint` 使用的内嵌 builtin 规则；
2. 存在时的有效 `--rules` 目录；
3. 存在时的有效 `--rule` 文件；
4. 按命令行顺序排列的匿名 `--pattern` 规则。

对 `scan` 而言，命令未包含 `--rules`、`--rule` 或 `--pattern` 时，默认规则目录
为 `./.moongrep/rules`。指定其中任一规则来源会替换默认目录。显式 `--rules`
目录会与选中的其他来源组合。

对 `lint` 而言，builtin 规则始终是第一个来源。显式 `--rules`、`--rule` 和
`--pattern` 会在 builtin 规则之后添加更多来源。

在 Windows 上，有效的 `--rules` 和 `--rule` 路径会在文件系统访问前进行词法
规范化。递归规则发现使用原生路径连接；单个 `--rule` 文件的所在目录按 Windows
路径规则计算。Linux 和 macOS 保留现有的 `/` 路径构造方式。

规则目录发现、规则 id、YAML 校验、一个规则目录内的来源顺序和匹配器编译由
[RuleSpec_CN.md](RuleSpec_CN.md) 规定。

### 重复选项

重复选项具有以下有效值：

- 最后一个 `--rules` 或 `-r` 值生效。
- 最后一个 `--rule` 值生效。
- 每个 `--pattern` 都按顺序保留。
- 每个 `--exclude` 和 `--disable` 都按顺序保留。
- 重复的布尔选项等同于只提供一次。

用法错误包括多个扫描根位置参数、缺少选项值、未知选项和未知命令。

### 匿名模式和 Guard

每个 `--pattern` 都会成为带一个正向 pattern 的结构规则。它的规则 id 就是模式
源码本身，描述为 `Anonymous CLI pattern.`。匿名规则使用默认 match mode。

一个 `--guard` 会附加到最近且尚未设置 guard 的前置 pattern。每个 pattern
最多接受一个 guard。没有可用的前置 pattern 时，提供 guard 属于用法错误。

命令行 guard 值必须只包含一个 YAML 文档。该文档必须是映射；键必须是非空的
`$` 前缀名称，值必须是字符串。格式错误的 YAML、其他顶层 YAML 类型、多个文档、
无效键或非字符串值都属于用法错误。

一个键是否命名了兼容的捕获、正则表达式是否有效以及 guard 如何匹配，属于
规则编译问题，由 [RuleSpec_CN.md](RuleSpec_CN.md) 规定。

### 规则禁用

所有选中来源都会先加载，然后才应用 `--disable`。每个禁用 id 都与组合后的已加载
规则 id 进行精确且区分大小写的比较，此规则在所有平台一致。每个请求的 id 都必须
存在；第一个未知 id 会成为状态码 2 的用法错误。

所有具有被禁用 id 的规则都会在规则编译和扫描计划之前移除。重复的禁用 id 按
一个处理。verbose 的已加载规则事件描述最终保持启用的规则。

## 文件遍历

### 文件和目录目标

对于目录目标，moongrep 会递归检查子条目，解析路径以小写 `.mbt` 结尾的普通
文件，并忽略其他条目。所有平台的后缀判断都区分大小写。

缺失或不可读的目标属于运行期失败。路径使用其他后缀的现有普通文件会成功完成扫描，
且没有命中。

### 遍历顺序和符号链接

目录条目先排序，再进行深度优先遍历。扫描器完整遍历一个目录条目后，再访问下一个
同级条目。命中、warning 和 verbose 事件按这个遍历顺序流式输出，最终顺序也以此
为准。

文件系统类型检查会在扫描根及其下层跟随符号链接。渲染路径会保留符号链接路径。
遍历把每条路径视为独立目标，因此多个路径可以重复扫描同一目标，递归符号链接环
可以让遍历持续运行。

### 默认目录排除

在考虑子条目时，moongrep 会在每一层跳过以下精确名称：

- `.git`
- `_build`
- `.mooncakes`
- `target`

比较使用完整条目名称。在 Linux 和 macOS 上比较区分大小写；仅在 Windows 上，
条目名称按逐字符 Unicode 小写映射进行不区分大小写的比较。这些排除应用于遍历中
的子条目。显式选择的扫描根即使以其中一个名称结尾，也仍会被检查。

### `--exclude`

在 Linux 和 macOS 上，每个 `--exclude` 值都会先删除末尾的 `/` 字符但保留单独
的 `/`，再删除所有开头的 `./`。例如，`./vendor/` 变成 `vendor`，
`./src/generated///` 变成 `src/generated`。包括 `..` 在内的其他分量保持字面
含义。

在 Windows 上，`/` 和 `\` 都可作为分隔符；重复分隔符会被折叠，`.` 和 `..`
分量按 Windows 路径规则规范化。非根路径的尾部分隔符会被删除，`C:\` 和
`\\server\share\` 等根路径则保留尾部分隔符。空排除值保持为空。

访问一个子条目前，每个完整的规范化排除值都会与以下两个值比较：

- 子条目的名称；
- 经过相同规范化的已构造子路径。

任一个完整字符串匹配都会跳过该文件或目录条目。Linux 和 macOS 的比较保留大小写
和文件系统拼写。Windows 使用与 Windows 路径比较相同的逐字符 Unicode 小写映射，
进行不区分大小写的比较。所有平台都把 glob 字符当作普通字符。

因为每一层都进行条目名称匹配，排除 `vendor` 会跳过每个匹配名称的子条目，排除
`generated.mbt` 会跳过每个匹配名称的子文件。`src/generated` 这样的路径只匹配
按平台比较规则与其相等的已构造子路径。绝对排除项只匹配绝对的已构造子路径；
程序不会只为匹配绝对排除项而解析相对扫描根。排除只应用于目录遍历发现的子条目；
显式选择的扫描根仍会被检查。

## 源码处理

### 预过滤

编译后的规则会生成带源码文本预过滤器的扫描计划。moongrep 首先过滤完整文件；
所有已启用规则都被过滤掉时，跳过分块和解析。随后，moongrep 独立过滤每个源码
块，并解析仍有候选规则的块。

只有经过文件和源码块预过滤后保留的源码会产生解析或属性 warning。

### 源码块和解析 Warning

一个在第 1 列以 `///|` 开头的源码行会开始一个源码块。分隔行属于后面的块。
缩进的 `///|` 文本保留在当前块中。没有后续分隔符的文件会作为一个块解析。

每个相关块都按 MoonBit 顶层结构解析。如果解析报告诊断或留下 recovery node，
该块会被跳过，并向标准错误写入一条 warning。同一文件中的其他相关块会继续扫描。

对于多块文件，warning 会指出被跳过块在原文件中的起始行。对于单块文件，它只
指出文件。parser 消息会被压缩到一条 warning 行上。出现解析 warning 后，退出
状态仍为 0。

### `#moongrep.skip`

在已解析的顶层项上，裸 `#moongrep.skip` 会对整个顶层项抑制所有结构规则。
污点规则仍会在该项上运行。

`#moongrep.skip()` 等 payload 形式无效。每个无效属性都会产生一条带源码位置的
warning。除非同一项还带有裸 `#moongrep.skip`，结构规则会继续运行；裸属性会抑制
结构规则，每个无效 payload 仍会产生 warning。只有精确的裸
`#moongrep.skip` 形式会抑制结构规则。

属性检查在预过滤和成功解析后进行，因此 warning 来自预过滤保留并成功解析的块。

## 输出流和顺序

### 标准输出

在 `scan` 和 `lint` 期间，命中会在发现时写入标准输出。文本模式对零命中扫描
写入 `no match hits`，JSON 模式则保持标准输出为空。

帮助、内嵌文档和 dump 输出也写入标准输出。

### 标准错误和 Verbose 事件

所有导致命令以非零状态退出的失败诊断都写入标准错误，包括命令行用法、未知文档、
dump 解析、规则加载、规则编译、文件系统、输出以及未预期的运行期诊断。扫描解析
warning 和无效 `#moongrep.skip` warning 也总会写入标准错误。`--verbose` 会添加
以下标准错误事件：

- 遍历开始前，对每个已启用的编译规则输出
  `moongrep scan: loaded rule <id>`；
- 进入目录时输出 `moongrep scan: entering <path>`；
- 默认或请求的排除跳过子条目时输出 `moongrep scan: skipping <path>`；
- 处理符合条件的 `.mbt` 文件前输出 `moongrep scan: file <path>`。

Verbose 事件保留在标准错误中，不进入 JSON 记录流。

### 流式顺序

遍历恢复之前会完整写完一个命中。在文本模式中，相邻命中之间用一个空行分隔。
在 JSON 模式中，每个命中是一条以换行结束的记录，没有额外空行。

warning 和 verbose 事件保留在遍历产生它们的位置，并交错写入标准错误。因此，
合并标准输出和标准错误时可以看到遍历顺序，但仍受 shell 或调用方对两个流的正常
处理方式影响。

## 文本输出

### 命中布局

每个命中具有以下结构：

```text
<file>:<start-line>:<start-column>-<end-line>:<end-column>
rule: <rule-id>
description:
  <description line 1>
  <description line 2>
source:
<number> <marker> <source line>
```

description 末尾的换行字符会被移除，剩余每一行前面缩进两个空格。空 description
仍会产生一行带缩进的空内容。

位置使用从 1 开始的行号和 Unicode 码点列号。emoji 等非 BMP 字符计为一列；
组合标记分别计列，不合并为字素簇。起点包含在范围内，终点不包含在范围内。

### 源码上下文和长命中

源码上下文包含第一个命中行之前最多两行、所有显示的命中行，以及最后一个命中行
之后最多两行。行号会填充到该命中中最宽的行号宽度。

当命中最多跨越六行时，会显示所有命中行。当它跨越七行或更多行时，文本输出
保留最前面三行和最后面三行命中内容，并用一行报告省略的行范围和数量。JSON 的
`matched_source` 和 `source_context` 始终保留所有行。

### 颜色

默认启用颜色。环境变量的值恰好为 `NO_COLOR=1` 时关闭颜色。未设置以及其他任何
值（包括空字符串和 `true`）都会保持颜色启用。

启用颜色时，命中的源码切片为亮黄色，未命中的上下文和省略行是亮黑色；各行使用
` | ` 作为分隔符。设置 `NO_COLOR=1` 时输出纯文本，命中行或省略行使用 ` > `，
未命中的上下文行使用 ` | `。

## JSON Lines 输出

### 记录结构

`--output-json` 为每个命中写入一个紧凑 JSON object，字段结构如下：

```text
{
  "file": string,
  "rule_id": string,
  "description": string,
  "range": {
    "start": { "line": integer, "column": integer },
    "end": { "line": integer, "column": integer }
  },
  "matched_source": string,
  "source_context": [
    { "line": integer, "text": string, "is_match": boolean }
  ]
}
```

记录只包含上面列出的字段。`description` 末尾的换行字符会被移除。

### 坐标和源码文本

JSON range 坐标与文本输出使用相同的从 1 开始的 Unicode 码点列号，并遵循上面的
非 BMP 字符和组合标记计列规则。`range.start` 包含在范围内，`range.end` 不包含在
范围内。

`matched_source` 是该范围覆盖的精确源码切片。`source_context` 包含与文本输出
相同的前两行和后两行窗口。对于范围经过的每个物理行，`is_match` 都为 true，
即使第一行或最后一行只有一部分被命中。

### 无命中行为

每条 JSON 记录都以一个换行结束。零命中的扫描向标准输出写入零字节。warning
和 verbose 事件仍可能写入标准错误。

## `docs`

该命令只接受以下两种形式之一：

```text
moongrep docs --list
moongrep docs <document-name>
```

`--list` 按注册表顺序打印注册名称和摘要，两者之间用一个 tab 分隔：

```text
RuleSpec	YAML rule keys, validation, and matcher semantics.
CLISpec	Command-line parsing, scanning, output, diagnostics, and exit behavior.
```

注册表依次包含 `RuleSpec` 和 `CLISpec`，并内嵌它们的英文源码。仓库还包含对应的
`_CN.md` 译文。

文档查找进行区分大小写的精确比较。未知名称以状态码 2 退出。组合 `--list` 和
名称、提供多个名称或使用未知选项都属于状态码 2 的用法错误。不带参数调用
`docs` 会打印其帮助并以状态码 0 退出。

## `dump`

该命令只接受以下两种形式之一：

```text
moongrep dump --impl <source>
moongrep dump --expr <source>
```

`--impl` 接受一个有效的 MoonBit 顶层项，`--expr` 接受一个有效的 MoonBit
表达式。两种形式的解析结果都不能包含诊断或 recovery node。

成功时，`dump` 会把结果 untyped CST node 的 MoonBit `Repr` 调试渲染以 CST
调试文本格式写入标准输出。

同时提供 `--impl` 和 `--expr` 属于状态码 2 的用法错误。不提供任一选项调用
`dump` 会打印帮助并以状态码 0 退出。词法或解析诊断、recovery node，以及
`--impl` 结果包含零个或多个顶层项时，都以状态码 3 退出。

## 诊断和退出状态

moongrep 为每个可处置的失败类别使用固定状态码：

| 状态码 | 类别 |
|---:|---|
| 0 | 成功 |
| 1 | 内部错误或其他未分类失败 |
| 2 | 命令行用法错误 |
| 3 | 无效 `dump` 输入 |
| 4 | 规则来源错误 |
| 5 | 规则内容错误 |
| 6 | 扫描输入错误 |
| 7 | 输出错误 |

### 退出状态 0

状态 0 表示请求的命令成功完成。它包括：

- 帮助输出；
- 成功的 `docs` 列表或查找；
- 成功的 CST dump；
- 有命中的扫描；
- 没有命中的扫描；
- 产生源码解析 warning 或无效属性 warning 的扫描。

`lint` 在产生命中或源码 warning 时返回状态 0。

### 退出状态 1

状态 1 保留给内部错误，包括损坏的内嵌 builtin 规则、不可达的命令状态，以及
尚未归入其他类别的未预期错误。

### 退出状态 2

状态 2 表示命令行选择或校验失败。它包括：

- 缺少或未知顶层命令；
- 未知选项、缺少选项值或多个扫描根；
- 缺少前置 pattern、重复或不是有效 YAML 字符串映射的命令行 guard；
- 组合互斥的 `docs` 或 `dump` 参数；
- 未知内嵌文档；
- `--disable` 请求了未知规则 id。

### 退出状态 3

状态 3 表示 `dump` 收到了无效 MoonBit 输入。词法或语法诊断、recovery node，
以及 `--impl` 结果不是恰好一个顶层项时，都使用该状态码。

### 退出状态 4

状态 4 表示请求的规则来源无法使用，包括规则路径不存在、不可读或类型错误，
目录遍历或规则文件读取失败，以及规则目录不包含 YAML 文件。

### 退出状态 5

状态 5 表示规则内容无效，包括 YAML 解析、schema 与重复 id 校验，以及 pattern
或 guard 校验和编译失败。无效的命令行匿名 pattern 也使用该状态码。内嵌
builtin 规则自身失败时改用状态 1。

### 退出状态 6

状态 6 表示扫描输入无法读取，包括扫描根不存在、目录遍历失败和 MoonBit 源码
文件读取失败。扫描期间遇到的 MoonBit 源码解析失败仍只产生 warning，并返回
状态 0。

### 退出状态 7

状态 7 表示写入标准输出或标准错误失败，包括 broken pipe。如果向标准错误写出
原始失败诊断本身也失败，状态 7 优先于该失败原本的状态码，前端不会再尝试把诊断
写到标准输出。流式扫描后续发生输出或扫描输入错误时，不撤回此前已经写出的命中。
