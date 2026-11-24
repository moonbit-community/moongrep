---
name: moongrep
description: 使用 moongrep 对 MoonBit 源码进行结构化搜索和污点分析。适用于需要语法感知的 MoonBit 代码搜索。
---

# moongrep

`moongrep` 是一个实验性的 MoonBit 结构化搜索和污点分析工具。

## 命令一览

| 命令 | 用途 |
| --- | --- |
| `moongrep lint` | 使用内置规则检查项目。 |
| `moongrep scan` | 使用结构模式或 YAML 规则扫描 MoonBit 文件。 |
| `moongrep dump` | 查看 MoonBit 表达式或顶层项的无类型 CST。 |
| `moongrep docs` | 列出或打印内置英文规范文档。 |

下文示例假设已安装 `moongrep` 可执行文件。如需使用 WebAssembly CLI，请将
`moongrep` 替换为：

```bash
moonx moonbit-community/moongrep --
```

## 快速入门

### 使用内置规则检查项目

在当前目录运行内置规则：

```bash
moongrep lint
```

`lint` 默认扫描当前目录，并支持 `scan` 的所有选项，可以追加自定义规则、过滤结果
或切换为 JSON 输出。

### 执行结构化搜索

在 MoonBit 项目根目录运行 `scan`，并通过 `--pattern` 指定表达式模式。默认情况下，
`scan` 会递归遍历目录，并跳过 Git 和 MoonBit 工具链生成的目录。

例如，查找对 `Option` 值执行 `match` 的表达式：

```bash
moongrep scan --pattern 'match $(value:exp) { Some($(some:id)) => $(some_body:exp); None => $(none_body:exp) }'
```

`moongrep` 边扫描边输出结果，输出较多时可以通过管道传给分页器（如 `less -R`）：

```bash
moongrep scan --pattern 'match $(value:exp) { Some($(some:id)) => $(some_body:exp); None => $(none_body:exp) }' | less -R
```

## 表达式模式和元变量

`moongrep` 会将模式和目标 MoonBit 源码都解析成无类型具体语法树（CST），再按结构
比较：

- 模式中的普通 MoonBit 语法代表固定结构。
- 元变量用于匹配并捕获对应位置的语法节点。
- 换行、缩进等排版差异通常不影响匹配结果。

### 元变量语法与类别

带类别的元变量写作：

```text
$(name:kind)
```

`name` 是捕获名，用于在匹配成功后记录该位置的代码；`kind` 限定允许匹配的语法节点
类别：

| 类别 | 匹配范围 |
| --- | --- |
| `exp` | 完整表达式（变量、函数调用、字段访问、`if` 表达式等）。 |
| `id` | 标识符（变量名、参数名、pattern 绑定名等）。 |
| `const` | 字面常量（整数、字符串、布尔值等）。 |
| `arg` | 完整的函数调用参数（位置参数、标签参数、可选参数等）。 |
| `pat` | 完整的 pattern。 |
| `type` | 完整的类型。 |

### 示例拆解

下面的模式匹配包含 `Some` 和 `None` 两个分支的 `match` 表达式：

```moonbit
match $(value:exp) {
  Some($(some:id)) => $(some_body:exp)
  None => $(none_body:exp)
}
```

其中各占位符的含义为：

- `$(value:exp)` 捕获 `match` 检查的表达式。
- `$(some:id)` 捕获 `Some(...)` 中绑定的标识符。
- `$(some_body:exp)` 捕获 `Some` 分支的表达式。
- `$(none_body:exp)` 捕获 `None` 分支的表达式。

针对以下代码：

```moonbit
match load_user() {
  Some(user) => display(user)
  None => show_error()
}
```

匹配成功并产生如下捕获：

```text
value     = load_user()
some      = user
some_body = display(user)
none_body = show_error()
```

模式中的固定结构必须一致：

- 使用 `Ok` 和 `Err` 分支的 `match` 不会命中，因为 `Some` 和 `None` 是固定结构。
- `Some(1)` 不会命中 `Some($(some:id))`，因为 `1` 是常量而不是标识符。

### 重复元变量与 `$_`

同一个具名元变量在模式中出现多次时，所有出现位置必须按类别一致：

- `id` 比较规范化后的名称。
- `const` 比较解析后的常量。
- CST 类捕获（`exp`、`arg`、`pat`、`type`）比较语法树结构，忽略源码位置。

例如：

```moonbit
$(value:exp) == $(value:exp)
```

它可以匹配 `user.name == user.name`，但不会匹配 `user.name == other.name`。

如果只想匹配任意节点而不记录捕获，可使用忽略占位符 `$_`。同一模式中的多个 `$_`
相互独立。

## 模式附加条件（`--guard`）

使用 `--guard` 可以筛选 `--pattern` 中元变量捕获到的值。例如，查找预期字符串为
数字的 `inspect` 调用：

```bash
moongrep scan \
  --pattern 'inspect($_, content=$(str:const))' \
  --guard '{$str: "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?$"}'
```

### 语法与引号规则

`--guard` 接受一个 YAML 映射，通常紧跟在对应的 `--pattern` 之后：

```text
--pattern '...$(name:id)...$(value:const)...' \
--guard '{$name: "正则表达式", $value: "正则表达式"}'
```

- 键必须是模式中已声明的具名元变量，并保留 `$` 前缀。
- 值必须是正则表达式字符串。
- 用单引号包住整个 YAML 映射，避免 shell 展开 `$name`；用双引号包住正则字符串。
- YAML 双引号字符串中的反斜杠需要转义（例如将正则中的 `\.` 写成 `\\.`）。

### 筛选规则

- **支持的类别**：仅支持 `id` 和 `const` 捕获；不支持 `exp`、`arg`、`pat`、
  `type`、省略号捕获或 `$_`。
- **匹配文本**：
  - `id` 捕获匹配规范化后的标识符（如 `name` 或 `@pkg.name`）。
  - `const` 捕获匹配解析器得到的常量值（例如 `"raw"` 对应 `raw`，`42` 对应
    `42`，`true` 对应 `true`）。
- **正则语义**：默认按子串匹配（例如 `"raw"` 也会匹配 `"draw"`）。需要整串匹配时
  请加上 `^` 和 `$`（如 `"^raw$"`）。
- **多条件组合**：同一映射中的所有条件必须同时满足（逻辑 AND）。每个 `--pattern`
  最多接受一个 `--guard`；扫描多个带条件模式时请成对提供 `--pattern` 和
  `--guard`。

同时限定函数名和常量参数的示例：

```bash
moongrep scan \
  --pattern '$(callee:id)($(value:const))' \
  --guard '{$callee: "^@html\\.render$", $value: "^(danger|raw)$"}'
```

## 结构化输出（`--json`）

`moongrep` 默认输出便于人阅读的文本报告。使用 `--json` 可输出紧凑的 JSON Lines，
方便编程智能体和脚本消费：

```bash
moongrep scan --pattern 'inspect($_, content="true")' --json
moongrep dump --json --expr 'x + 1'
```

### 流约定

- 每条非空程序输出行都是一个紧凑的 JSON 对象。
- **标准输出**：
  - `scan` 和 `lint`：仅输出 `finding` 记录（无命中时为空）。
  - `dump`：成功且未启用 `--exit-code` 时输出一条 `dump` 记录。
- **标准错误**：仅输出 `trace`、`warning` 和 `error` 记录。
- 记录按遍历顺序流式写出；后续失败不会撤回已经写出的记录。
- 当首个命令为 `scan`、`lint` 或 `dump` 时，CLI 会在完整参数解析前识别独立的
  `--json`，因此用法错误也会以 JSON 输出。选项终止符 `--` 之后的 `--json` 不会被
  当作选项。成功的帮助信息仍为普通文本。

### 记录结构

```text
finding: { "type":"finding", "file", "rule_id", "description", "range",
           "matched_source", "source_context" }
warning: { "type":"warning", "category", "message", ...详情字段 }
trace:   { "type":"trace", "event", ...事件字段 }
dump:    { "type":"dump", "kind":"impl"|"expr", "content" }
error:   { "type":"error", "category", "exit_code", "message",
           ...可选诊断字段 }
```

- **警告类别（`warning`）**：`parse`、`invalid_skip_payload`、`taint_incomplete`
- **跟踪事件（`trace`，需 `--verbose`）**：`rule_loaded`、`directory_entered`、
  `path_skipped`、`file_started`
- **错误类别（`error`）**：`internal`、`usage`、`dump_input`、`rule_source`、
  `rule_content`、`scan_input`、`output`、`taint_incomplete`

## 查看 CST（`dump`）

使用 `dump` 打印 MoonBit `untyped_cst` 调试输出或校验模式语法：

```text
moongrep dump [--exit-code] [--strict-check] [--json] (--impl <impl> | --expr <expr>)
```

示例：

```bash
moongrep dump --impl 'fn answer { 42 }'
moongrep dump --expr 'x + 1'
moongrep dump --json --expr 'x + 1'
moongrep dump --exit-code --expr 'x + 1'
moongrep dump --strict-check --impl 'fn wrapper { __TARGET__ }'
```

### 选项说明

- `--impl <impl>`：解析一个 MoonBit 顶层实现项并打印其 `untyped_cst` 调试输出。
  与 `--expr` 互斥。
- `--expr <expr>`：解析一个 MoonBit 表达式并打印其 `untyped_cst` 调试输出。与
  `--impl` 互斥。
- `--strict-check`：在基础解析成功后继续执行 `scan` 使用的附加模式校验。
  `--expr` 按普通结构模式校验；`--impl` 按默认 `inside-toplevel` 语义校验，且必须
  在可绑定表达式位置恰好包含一个 `__TARGET__`。不影响成功时的文本或 JSON 输出。
- `--json`：输出单行 JSON `dump` 记录（包含 `type`、`kind` 和 JSON 转义后的
  `content`）。
- `--exit-code`：执行相同校验但不打印 CST。校验通过时两个输出流均为空并以 `0`
  退出（即使同时传入 `--json` 或 `--strict-check`）。基础语法错误仍返回 `3`；仅在
  `--strict-check` 失败时返回 `5`（`invalid dump pattern`）。传入 `--json` 时，两类
  失败均按标准 JSON `error` 结构输出。

不带参数运行 `moongrep dump` 会打印 `dump` 帮助并返回 `0`。用法错误（如同时提供
`--impl` 和 `--expr`，或仅传 `dump --json` 而不给输入）返回 `2`；
`dump --json --help` 仍打印普通帮助并返回 `0`。

## 退出状态

帮助、成功 `dump`、有命中扫描、无命中扫描和可恢复扫描警告都返回 `0`。无命中扫描
不采用 grep 风格的状态码 `1`。

| 状态码 | 含义 |
| ---: | --- |
| `0` | 成功（包括无命中扫描和可恢复警告）。 |
| `1` | 内部或未分类错误，包括损坏的内置规则。 |
| `2` | 命令行用法错误。 |
| `3` | 无效 `dump` 输入（词法或解析失败）。 |
| `4` | 规则来源不存在、不可读或类型错误，或规则目录中不含 `.yaml` / `.yml` 文件。 |
| `5` | 规则内容无效（空白或无效 YAML、单文件 `--rule` 后缀不受支持、schema/pattern/guard/编译结果无效）或 `--strict-check` 模式校验失败。 |
| `6` | 扫描输入不存在或不可读。 |
| `7` | 标准输出或标准错误写入失败。 |
| `8` | 启用 `--strict-taint` 时存在不完整的污点分析。 |

## 详细文档

仓库内的中文完整规范：

- [规则规范](internal/docs/RuleSpec_CN.md) — YAML 规则 schema、校验规则、元变量、
  结构规则和污点语义。
- [CLI 规范](internal/docs/CLISpec_CN.md) — 命令行解析、遍历、过滤、输出格式、诊断
  和退出码。

英文规范也可以通过 `docs` 子命令直接查看：

```bash
moongrep docs --list
moongrep docs RuleSpec
moongrep docs CLISpec
```
