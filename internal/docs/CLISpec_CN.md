# 命令行接口规范

本文档规定 `moongrep` 命令行工具如何选择命令与规则来源、遍历并扫描 MoonBit
文件、格式化输出与诊断信息，以及分配退出状态码。

关于 YAML 规则格式、校验和匹配器语义，请参阅 [RuleSpec_CN.md](RuleSpec_CN.md)。
除非某一节另有说明，路径和规则 ID 均按区分大小写的字符串比较。

## 调用与命令选择

### 调用形式

| 分发形式 | 命令格式 |
| --- | --- |
| 已安装的可执行文件 | `moongrep <command> [arguments]` |
| 已发布的 WebAssembly CLI | `moonx moonbit-community/moongrep -- <command> [arguments]` |
| 本地 WebAssembly 产物 | `moonrun path/to/moongrep.wasm -- <command> [arguments]` |

在 WebAssembly 形式中，`--` 用于分隔 runner 参数和 `moongrep` 参数；分隔符后的
参数行为与直接运行已安装的可执行文件完全一致。

### 顶层命令

| 命令 | 摘要 | 无额外参数时的行为 |
| --- | --- | --- |
| `scan` | 使用显式指定或默认规则扫描 MoonBit 源码。 | 使用 `./.moongrep/rules` 扫描 `.`。 |
| `lint` | 默认启用内嵌 builtin 规则扫描 MoonBit 源码。 | 使用 builtin 规则扫描 `.`。 |
| `docs` | 列出或打印内嵌文档。 | 打印 `docs` 帮助并以状态码 `0` 退出。 |
| `dump` | 解析单个顶层项或表达式，输出 CST 调试文本或执行校验。 | 打印 `dump` 帮助并以状态码 `0` 退出。 |

不带任何子命令运行 `moongrep` 时，程序会打印缺少子命令的诊断和顶层帮助，并以
状态码 `2` 退出。

### 版本与帮助

- **版本**：`moongrep --version` 和 `moongrep -V` 将 `moon.mod` 中的模块版本写入
  标准输出并以状态码 `0` 退出，无需子命令。
- **帮助**：`-h` 和 `--help` 打印当前命令帮助；`moongrep help` 打印顶层帮助；
  `moongrep help <command>` 打印指定命令的帮助。所有帮助文本均写入标准输出并以
  状态码 `0` 退出。

## `scan` 和 `lint`

### 语法

```text
moongrep scan [options] [scan-root]
moongrep lint [options] [scan-root]
```

最多接受一个 `scan-root` 位置参数，它可以位于选项之前、之间或之后，省略时默认为
`.`。

### 选项

| 选项 | 参数值 | 用途 | 重复出现时的行为 |
| --- | --- | --- | --- |
| `-r`, `--rules` | `<dir>` | 选择包含 YAML 规则的目录。 | 最后一个值生效。 |
| `--rule` | `<file>` | 选择单个 YAML 规则文件（小写 `.yaml` 或 `.yml`）。 | 最后一个值生效。 |
| `--pattern` | `<source>` | 添加一条匿名结构表达式模式。 | 按顺序全部保留。 |
| `--guard` | `<yaml>` | 为最近一个尚未附加 guard 的前置 `--pattern` 附加 YAML guard 映射。 | 每个模式最多一个。 |
| `--exclude` | `<name-or-path>` | 跳过匹配的子文件或子目录条目。 | 按顺序全部保留。 |
| `--disable` | `<rule-id>` | 按精确规则 ID 禁用已加载规则。 | 按顺序保留（重复 ID 合并为一个）。 |
| `--strict-taint` | 标志 | 若污点分析不完整则以状态码 `8` 退出（默认关闭）。 | 等同于出现一次。 |
| `--verbose` | 标志 | 将规则加载和遍历事件写入标准错误。 | 等同于出现一次。 |
| `--json` | 标志 | 以 JSON Lines 格式输出命中与诊断。 | 等同于出现一次。 |
| `-h`, `--help` | 标志 | 打印命令帮助并以状态码 `0` 退出。 | 等同于出现一次。 |

其他选项约定：

- 带值的长选项同时接受 `--option value` 和 `--option=value`。其中只有 `--rules`
  提供短形式 `-r`。
- 两个命令都不接受 `--enable-builtin-rules`；内嵌 builtin 规则只能通过 `lint`
  启用。
- 颜色输出由 `NO_COLOR` 环境变量控制（见[颜色](#颜色)）。
- 多个 `scan-root` 位置参数、缺少选项值、未知选项和未知命令均属于用法错误（状态码
  `2`）。

### 扫描根与平台路径规则

`scan-root` 可以是目录，也可以是单个普通文件：

- 目录目标会递归遍历。
- 普通文件仅在路径以精确小写 `.mbt` 结尾时被扫描。
- 扫描器会跟随目录符号链接，并通过 `realpath` 识别目录身份，每个解析后的目录最多
  进入一次，从而跳过符号链接环及指向已访问目录的后续别名。命中和事件仍保留遍历时
  经过的路径（不改写为真实路径）。

平台路径处理差异：

- **Linux 和 macOS**：保留用户提供的 `scan-root` 拼写，并使用 `/` 拼接子路径。
- **Windows**：在任何文件系统操作前对 `scan-root` 做词法规范化。`/` 和 `\` 均被
  接受，重复分隔符会被折叠，`.` 与 `..` 按 Windows 路径规则规范化（不会把相对扫描
  根转成绝对路径）。子路径使用 `\` 拼接。文件系统访问、命中位置、warning、verbose
  事件和 JSON 输出共用同一规范化原生路径。目录身份检查会另外解析符号链接，但不会
  改变渲染路径。

### 规则来源与加载顺序

`scan` 和 `lint` 可组合多种规则来源。无论命令行上选项出现的先后顺序如何，加载顺序
固定为：

1. 内嵌 builtin 规则（仅 `lint`）。
2. 有效的 `--rules` 目录（若存在）。
3. 有效的 `--rule` 文件（若存在）。
4. 匿名 `--pattern` 规则（按命令行出现顺序）。

默认来源规则：

- 对 `scan` 而言，未提供 `--rules`、`--rule` 或 `--pattern` 时默认使用
  `./.moongrep/rules`。指定任一显式来源会替换该默认目录；显式 `--rules` 目录会与
  其他来源组合。
- 对 `lint` 而言，builtin 规则始终排在首位，显式 `--rules`、`--rule` 和
  `--pattern` 会追加在后。

规则路径与单文件约定：

- 单个 `--rule` 文件的后缀检查在所有平台上均区分大小写（仅接受小写 `.yaml` 或
  `.yml`）。可读但后缀不符的文件会作为无效规则内容被拒绝（状态码 `5`）。
- 在 Windows 上，有效的 `--rules` 和 `--rule` 路径会在访问文件系统前做词法规范化；
  递归规则发现使用 `\` 拼接，单文件 `--rule` 所在目录按 Windows 路径规则计算。
  Linux 和 macOS 保留 `/` 拼接方式。
- 规则发现会跟随目录符号链接，且每个解析后的规则目录最多访问一次。
- 规则目录发现、规则 ID、YAML 校验、目录内排序及编译细节见
  [RuleSpec_CN.md](RuleSpec_CN.md)。

### 匿名模式与 Guard

- 每条 `--pattern` 会生成一条包含单个正向模式的结构规则：规则 ID 为模式源码本身，
  描述为 `Anonymous CLI pattern.`，使用默认 match mode。
- 每个 `--guard` 附加到最近一个尚未绑定 guard 的前置 `--pattern`。若不存在可用的
  前置模式，则属于用法错误（状态码 `2`）。
- `--guard` 的值必须恰好包含一个 YAML 文档且顶层为映射；键必须是非空 `$` 前缀名，
  值必须是字符串。YAML 语法错误、多文档、非映射、非法键或非字符串值均为用法错误
  （状态码 `2`）。
- 捕获类型兼容性与正则表达式合法性在规则编译阶段校验（状态码 `5`），详见
  [RuleSpec_CN.md](RuleSpec_CN.md)。

### 规则禁用（`--disable`）

- 所有选中的规则来源先全部加载，随后再应用 `--disable`。
- 禁用 ID 在所有平台上均与已加载规则 ID 做区分大小写的精确比较。
- 每个请求的 ID 都必须存在；遇到的第一个未知 ID 会导致状态码 `2` 的用法错误。
- 被禁用的规则在编译和扫描计划生成前移除。重复指定的 ID 按一个处理。verbose 的
  `rule_loaded` 事件只报告最终启用的规则。

## 文件遍历

### 合格文件与遍历顺序

- 面对目录目标时，`moongrep` 递归遍历子条目，只解析路径以精确小写 `.mbt` 结尾的
  普通文件（全平台区分大小写），忽略其他条目。
- 目标不存在或不可读时扫描失败（状态码 `6`）。普通文件存在但后缀非 `.mbt` 时以
  零命中成功结束（状态码 `0`）。
- 目录条目先排序再做深度优先遍历，完整处理完一个条目后再进入下一个同级条目。命中、
  warning 和 verbose 事件均按该遍历顺序流式写出。
- 文件类型检查在扫描根及其下层都会跟随符号链接。目录身份经 `realpath` 解析，每次
  扫描中同一真实目录最多进入一次，符号链接环及后续别名会被跳过。

### 默认目录排除

遍历 `scan-root` 下任意深度的子条目时，匹配以下名称的条目会被默认跳过：

- 任意以 `.` 开头的名称（不涉及大小写）
- `_build`
- `node_modules`
- `target`

精确名称比较在 Linux 和 macOS 上区分大小写；仅在 Windows 上采用逐字符 Unicode
小写映射做不区分大小写比较。默认排除只针对遍历中发现的子条目；如果用户显式指定的
`scan-root` 自身末段名称命中上述规则，它仍会被检查。

### 显式排除（`--exclude`）

比较前的规范化规则：

- **Linux 和 macOS**：先去掉末尾所有 `/`（保留单独的 `/`），再去掉开头所有 `./`。
  例如 `./vendor/` 变为 `vendor`，`./src/generated///` 变为 `src/generated`。
  `..` 等其余分量保持字面含义。
- **Windows**：同时接受 `/` 和 `\`，折叠重复分隔符，按 Windows 路径规则规范化 `.`
  与 `..`。非根路径去掉尾部分隔符，`C:\` 和 `\\server\share\` 等根路径保留尾部分
  隔符。空值保持为空。

匹配规则：

- 访问子条目前，每个规范化后的排除项会分别与**子条目名称**及**经过相同规范化的已
  构造子路径**做整串比较，任一命中即跳过该条目。
- Linux 和 macOS 区分大小写；Windows 使用与路径比较一致的逐字符 Unicode 小写映射。
- 所有平台均将 glob 字符（`*`、`?`、`[` 等）视为普通字面字符。
- 因为每层都匹配条目名称，`--exclude vendor` 会跳过任意层级的 `vendor`，
  `--exclude generated.mbt` 会跳过任意层级的 `generated.mbt`。
- 含路径分隔符的项（如 `src/generated`）只匹配按平台规则与其相等的已构造子路径。
  绝对路径排除项只匹配绝对已构造子路径，程序不会为了匹配它而将相对 `scan-root`
  转为绝对路径。
- 排除规则只作用于目录遍历中发现的子条目，不会排除显式指定的 `scan-root` 本身。

## 源码处理

### 预过滤

编译后的规则会生成带保守源码文本预过滤器的扫描计划：

1. 首先过滤整个文件内容；若所有已启用规则都被排除，则直接跳过分块和解析。
2. 否则，对每个源码块独立过滤，仅解析仍有候选规则的块。

因此，只有通过文件级和块级预过滤的源码才会产生解析 warning 或属性 warning。

### 源码块与解析 Warning

- 第 1 列以 `///|` 开头的行开启一个新的源码块，该分隔行归属于后续块；缩进后的
  `///|` 保留在当前块内。没有后续分隔符的文件作为单块解析。
- 每个相关块按 MoonBit 顶层结构解析。若解析产生诊断或留下 recovery node，该块被
  跳过并向标准错误写入一条 warning，同文件内的其他相关块继续扫描。
- 多块文件的 warning 会注明被跳过块在原文件中的起始行；单块文件只注明文件名。解析
  器消息会压缩为单行。解析 warning 保持退出状态 `0`（除非在 `--strict-taint` 下
  影响了污点分析，见[污点分析不完整](#污点分析不完整)）。

### `#moongrep.skip`

- 已解析顶层项上的裸 `#moongrep.skip` 会对该整个顶层项抑制所有结构规则；污点规则
  仍会运行。
- `#moongrep.skip()` 等带 payload 的写法无效：每个无效属性都会输出带源码位置的
  `invalid_skip_payload` warning，且不抑制结构规则。若同一项同时包含裸
  `#moongrep.skip` 和无效 payload，结构规则会被抑制，同时每个无效 payload 仍会
  报告 warning。
- 属性检查在预过滤和成功解析后运行，因此 warning 仅来自预过滤保留且成功解析的块。

## 输出流与顺序

### 标准输出与标准错误

| 输出流 | 内容 |
| --- | --- |
| `stdout` | `scan`/`lint` 的命中结果（文本模式零命中时输出 `no match hits`，JSON 模式为空）、帮助文本、`docs` 输出，以及 `dump` 文本或 JSON 记录（`dump --exit-code` 成功时为空）。 |
| `stderr` | 所有致命错误诊断（状态码 `1`–`8`）、解析 warning、无效 `#moongrep.skip` warning、`taint_incomplete` warning，以及 `--verbose` 跟踪事件。 |

### Verbose 事件（`--verbose`）

启用 `--verbose` 后，标准错误会按时机输出四类事件：

- `moongrep scan: loaded rule <id>` — 遍历开始前，为每条已启用编译规则输出一次。
- `moongrep scan: entering <path>` — 进入目录时输出。
- `moongrep scan: skipping <path>` — 路径因排除规则或目录已访问被跳过时输出。
- `moongrep scan: file <path>` — 处理合格的 `.mbt` 文件前输出。

JSON 模式下，标准错误改为输出 `trace`、`warning` 和 `error` JSON Lines 记录，
标准输出仅包含 `finding` 记录。

### 流式顺序

- 每条命中完整写出后再继续遍历。文本模式用空行分隔相邻命中；JSON 模式每条命中占
  一行，无额外空行。
- warning 和 verbose 事件在遍历产生的当下直接交错写入标准错误。
- 后续发生致命错误时会在标准错误追加一条错误诊断，不会撤回此前已写出的命中。

## 文本输出

### 命中布局与坐标

```text
<file>:<start-line>:<start-column>-<end-line>:<end-column>
rule: <rule-id>
description:
  <description line 1>
  <description line 2>
source:
<number> <marker> <source line>
```

- `description` 末尾换行会被去除，其余每行前缩进两个空格；空描述仍输出一行带缩进
  的空行。
- 行号和列号均从 1 开始，列号按 Unicode 码点计数。emoji 等非 BMP 字符计为 1 列，
  组合标记分别计列（不合并为字素簇）。起点包含，终点不包含。

### 源码上下文与长命中

- 上下文展示首个命中行之前最多 2 行、展示的命中行，以及最后一个命中行之后最多 2
  行。行号按该命中中最宽行号右对齐填充。
- 命中跨度 `<= 6` 行时完整展示所有命中行；跨度 `>= 7` 行时保留前 3 行和后 3 行，
  中间替换为一行省略提示（标明被省略的行范围与行数）。
- JSON 的 `matched_source` 和 `source_context` 始终保留完整行，不做省略。

### 颜色

- 默认开启颜色。仅当环境变量精确设置为 `NO_COLOR=1` 时关闭；未设置或设为其他值
  （包括空字符串和 `true`）均保持开启。
- **开启颜色**：命中切片为亮黄色，未命中上下文与省略行为亮黑色，所有行均使用
  ` | ` 分隔。
- **关闭颜色（`NO_COLOR=1`）**：纯文本输出，命中行与省略行使用 ` > `，未命中上下
  文行使用 ` | `。

## JSON Lines 输出

### 协议与模式识别

- `scan`、`lint` 和 `dump` 支持通过 `--json` 启用 JSON Lines 输出。
- `--json` 必须是出现在 `--` 选项终止符之前的独立参数（例如 `scan -- --json` 和
  `dump -- --json` 不会启用 JSON 模式），且首个子命令必须是 `scan`、`lint` 或
  `dump`。
- 对 `scan` 和 `lint` 而言，两个标准流上的每个非空程序输出行都是紧凑 JSON 对象。
  对 `dump` 而言，成功且未启用 `--exit-code` 时向标准输出写出一个紧凑 JSON 对象。
- 成功的帮助输出与 `docs` 输出不走该协议；例如 `dump --json --help` 仍输出普通
  帮助文本。
- 模式识别在完整参数解析之前进行，因此只要存在有效位置的 `--json`，未知选项、缺少
  参数值等用法错误也会输出 JSON `error` 记录。

### 记录结构

#### `finding`（标准输出）

```text
{
  "type": "finding",
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

仅包含以上字段，`description` 末尾换行已去除。

#### `warning`（标准错误）

```text
{ "type": "warning", "category": "parse", "message": string,
  "file": string, "reason": string, "block_start_line": integer? }

{ "type": "warning", "category": "invalid_skip_payload", "message": string,
  "file": string, "range": range }

{ "type": "warning", "category": "taint_incomplete", "message": string,
  "file": string, "range": range, "rule_ids": [string], "reason": string }
```

`parse` 警告中的 `block_start_line` 仅在多块文件能定位被跳过块时出现。

#### `trace`（标准错误，需 `--verbose`）

```text
{ "type": "trace", "event": "rule_loaded", "rule_id": string }
{ "type": "trace", "event": "directory_entered", "path": string }
{ "type": "trace", "event": "path_skipped", "path": string }
{ "type": "trace", "event": "file_started", "path": string }
```

#### `dump`（标准输出）

```text
{ "type": "dump", "kind": "impl" | "expr", "content": string }
```

`dump --json` 成功时向标准输出写出恰好一条单行记录，字段顺序固定为 `type`、
`kind`、`content`。`content` 与文本模式的 CST `Repr` 文本一致（经 JSON 转义保持
单行）。`dump --exit-code --json` 在所有检查通过时保持静默。

#### `error`（标准错误）

```text
{ "type": "error", "category": string, "exit_code": integer,
  "message": string, "source": string?, "pattern": string?,
  "reason": string?, "help": string? }
```

`category` 取值为 `internal`、`usage`、`dump_input`、`rule_source`、
`rule_content`、`scan_input`、`output` 或 `taint_incomplete`。

- 结构化诊断的 `message` 为摘要；argparse 诊断的完整多行消息经转义后整体放入
  `message`。
- 空的可选字段会被省略。
- `pattern` 中的换行与文本模式一样统一为 LF 并去除一个末尾换行。

### 坐标、上下文与无命中行为

- `range` 采用与文本输出相同的 1-based Unicode 码点列号（起点包含、终点不包含）。
- `matched_source` 是该范围覆盖的精确源码切片。
- `source_context` 使用与文本输出相同的前两行、后两行窗口（不省略长命中）。只要
  物理行与 `range` 相交，`is_match` 即为 `true`（即使首行或末行只有部分被命中）。
- 每条 JSON 记录均以单个换行结束。零命中扫描向标准输出写入零字节（标准错误仍可能
  写出 `warning`、`trace` 或 `error` 记录）。

## `docs`

```text
moongrep docs --list
moongrep docs <document-name>
```

- `--list` 按注册顺序打印文档名与摘要，中间以单个 Tab 分隔：

```text
RuleSpec	YAML rule keys, validation, and matcher semantics.
CLISpec	Command-line parsing, scanning, output, diagnostics, and exit behavior.
```

- 注册表依次内嵌英文版的 `RuleSpec` 和 `CLISpec`（仓库内另附中文 `_CN.md` 译文）。
- 文档名按区分大小写的精确匹配查找。未知名称、同时传入 `--list` 与名称、传入多个
  名称或未知选项均以状态码 `2` 退出。
- 不带参数调用 `moongrep docs` 打印 `docs` 帮助并以状态码 `0` 退出。

## `dump`

```text
moongrep dump [--exit-code] [--strict-check] [--json] --impl <source>
moongrep dump [--exit-code] [--strict-check] [--json] --expr <source>
```

- **输入选项**（二选一且互斥）：
  - `--impl <source>`：必须解析为恰好一个有效 MoonBit 顶层项，且无诊断或
    recovery node。
  - `--expr <source>`：必须解析为一个有效 MoonBit 表达式，且无诊断或 recovery
    node。
- **严格模式校验（`--strict-check`）**：
  - 在基础解析通过后执行 `scan` 所用的附加校验。
  - `--expr` 按普通结构表达式模式编译。
  - `--impl` 按默认 `inside-toplevel` 语义编译：必须在受支持的表达式位置恰好包含
    一个 `__TARGET__`，且函数 shape 默认使用 `partial` 匹配模式。不接受 guard 或
    显式 match-mode 选项。
  - 不会改变成功时输出的 CST 内容（始终渲染第一次解析得到的 CST）。
- **输出与 `--exit-code`**：
  - 未启用 `--exit-code` 时，成功输出无类型 CST 的 MoonBit `Repr` 调试文本；启用
    `--json` 时将其封装为单条 `dump` 记录。
  - `--exit-code` 抑制所有 CST 输出并优先于 `--json`：检查全部通过时标准输出和标准
    错误均为空，并以状态码 `0` 退出。
- **失败状态**：
  - 不带参数调用 `dump` 打印帮助并以状态码 `0` 退出。
  - 同时传入 `--impl` 与 `--expr`，或仅传 `--exit-code`、`--strict-check`、
    `--json` 而无输入选项，以状态码 `2` 退出（`dump --json --help` 仍打印普通帮助
    并退出 `0`）。
  - 词法/解析诊断、recovery node 或 `--impl` 含零个/多个顶层项会在 `--strict-check`
    之前失败，输出 `dump_input` 诊断并以状态码 `3` 退出。
  - `--strict-check` 失败时输出 `invalid dump pattern` 诊断（`category` 为
    `rule_content`，`pattern` 为原始输入），并以状态码 `5` 退出。
  - 传入 `--json` 时，上述失败均按标准 JSON `error` 记录输出。

## 诊断和退出状态

### 文本诊断布局

状态码 `1` 到 `8` 的致命诊断使用无颜色英文纯文本：

```text
error: <摘要>
  source: <相关路径或输入>
  pattern:
    <pattern 第 1 行>
    <pattern 第 2 行>
  reason: <具体原因>
  help: <可执行建议>
```

- `source`、`reason` 和 `help` 为空时省略。
- 仅当诊断关联模式时才显示 `pattern` 区块；每行缩进 4 个空格，CRLF/CR 统一为 LF
  并忽略一个末尾换行，同时保留原有相对缩进与内部空行。显式空模式仍输出 `pattern:`。
- 匿名 `--pattern` 规则的 `source` 显示为 `--pattern`，模式内容仅出现在 `pattern`
  区块中。
- 诊断格式化器本身不附带末尾换行，由输出层写出时补齐。
- 参数解析器自带 `error:`、`Usage:` 及可选 `tip:` 的诊断保留完整布局；扫描 warning
  保留 `warning:` 格式。
- 文本措辞与可选详情行不属于机器可读契约，后续可能调整；需要稳定解析请使用
  `--json`。命中记录从不承载致命诊断，所有致命错误均写入标准错误。

### 退出状态总览

| 状态码 | 类别 | 触发条件 |
| ---: | --- | --- |
| `0` | 成功 | 帮助输出、`docs` 成功、`dump` 或 `dump --exit-code` 成功（含 `--strict-check`）、有/无命中的扫描与 lint，以及仅产生可恢复解析或 `#moongrep.skip` 警告的扫描。 |
| `1` | `internal` | 损坏的内嵌 builtin 规则、不可达命令状态或其他未分类内部错误。 |
| `2` | `usage` | 缺少/未知命令、未知选项、缺少选项值、多个扫描根、无效/错位/重复 `--guard`、冲突的 `docs`/`dump` 参数、未知内嵌文档名，或未知 `--disable` 规则 ID。 |
| `3` | `dump_input` | `dump` 收到无效 MoonBit 输入（词法/语法诊断、recovery node，或 `--impl` 非恰好一个顶层项）。在 `--strict-check` 之前检查。 |
| `4` | `rule_source` | 规则路径不存在、不可读或类型错误；规则目录遍历或读取失败；规则目录不含任何 `.yaml` / `.yml` 文件。 |
| `5` | `rule_content` | YAML 解析错误、schema 或重复 ID 错误、单文件 `--rule` 后缀不受支持、pattern/guard 校验编译失败（含匿名 `--pattern`），或 `dump --strict-check` 模式失败。（内嵌 builtin 规则损坏使用状态码 `1`。） |
| `6` | `scan_input` | 扫描根不存在、目录遍历失败或 `.mbt` 文件读取失败。（扫描期间的源码解析失败仍为 warning 并返回 `0`。） |
| `7` | `output` | 写入标准输出或标准错误失败（含 broken pipe）。若向标准错误写出原失败诊断本身也失败，则状态码 `7` 优先且不会改写到标准输出。此前已流式写出的命中不会撤回。 |
| `8` | `taint_incomplete` | 启用 `--strict-taint` 时存在不完整的污点分析（见下文）。 |

### 污点分析不完整

`scan` 和 `lint` 支持 `--strict-taint`（默认关闭）：

- 不支持的可执行语法、未收敛的污点 SCC，或妨碍污点分析的源码块解析失败，会在标准
  错误输出 `taint_incomplete` 警告（含文件、源码范围、受影响规则 ID 与原因），同时
  继续扫描其余内容。
- 受不支持语法影响的函数以及未收敛的函数/规则组合均不发布部分命中。纯结构扫描不
  构建污点 CFG。
- 默认模式下，若无其他错误命令仍以状态码 `0` 退出。
- 启用 `--strict-taint` 时，扫描结束后命令以状态码 `8` 退出；JSON 模式下还会在
  末尾追加一条 `category: "taint_incomplete"`、`exit_code: 8` 的 `error` 记录。
  原有 finding 字段与坐标保持不变。
