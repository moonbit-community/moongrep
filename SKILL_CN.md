---
name: moongrep
description: 使用 moongrep 对 MoonBit 源码进行结构化搜索和污点分析。适用于需要语法感知的 MoonBit 代码搜索。
---

# moongrep

`moongrep` 是一个实验性的 MoonBit 结构化搜索和污点分析工具。

## 快速入门

要使用内置规则检查当前 MoonBit 项目，运行：

```bash
moongrep lint
```

`lint` 是加载内置规则的命令。它默认扫描当前目录，并接受 `scan` 的其他选项，
用于添加自定义规则、过滤结果或调整输出格式。

要进行结构化搜索，可以在 MoonBit 项目根目录运行 `scan` 命令。默认情况下，
它会递归扫描，并跳过 Git 和 MoonBit 工具链生成的目录。使用 `--pattern`
选项指定一个*表达式模式*进行匹配。例如，下面这条命令匹配典型的对 Option
类型的值进行 `match` 的表达式。

```bash
moongrep scan --pattern 'match $(value:exp) { Some($(some:id)) => $(some_body:exp); None => $(none_body:exp) }'
```

注:当前文档的示例均使用最直接的命令形式`moongrep`, 如果需要使用wasm cli, 请把`moongrep`替换为`moonx moonbit-community/moongrep --`.

moongrep的工作模式是一边扫描一边直接输出扫描结果, 对于人类用户, 如果想获得较好的终端阅读体验, 请结合less等终端pager使用。

```bash
moongrep scan --pattern 'match $(value:exp) { Some($(some:id)) => $(some_body:exp); None => $(none_body:exp) }' | less -R
```

## 表达式模式和元变量

`moongrep`会将表达式模式和待扫描的 MoonBit 代码解析成抽象语法树（CST），然后比较两棵语法树的结构。模式中的普通 MoonBit 语法表示固定结构，元变量表示需要匹配和捕获的语法节点。换行、缩进等排版差异通常不会影响匹配结果。

元变量使用以下格式：

```text
$(name:kind)
```

`name`是元变量的名称。匹配成功后，当前位置上的代码会记录在这个名称下。`kind`指定允许匹配的语法节点类别。

常用的 `kind` 包括：

- `exp`：匹配一个完整表达式，例如变量、函数调用、字段访问或 `if` 表达式；
- `id`：匹配一个标识符，例如变量名、参数名或 pattern 中绑定的名称；
- `const`：匹配一个字面常量，例如整数、字符串或布尔值；
- `arg`：匹配一个完整的函数调用参数；
- `pat`：匹配一个完整的 pattern；
- `type`：匹配一个完整的类型。

下面的模式匹配一个包含 `Some` 和 `None` 两个分支的 `match` 表达式：

```moonbit
match $(value:exp) {
  Some($(some:id)) => $(some_body:exp)
  None => $(none_body:exp)
}
```

其中：

- `$(value:exp)` 捕获 `match` 检查的表达式；
- `$(some:id)` 捕获 `Some` pattern 中绑定的标识符；
- `$(some_body:exp)` 捕获 `Some` 分支的表达式；
- `$(none_body:exp)` 捕获 `None` 分支的表达式。

这个模式可以匹配：

```moonbit
match load_user() {
  Some(user) => display(user)
  None => show_error()
}
```

这次匹配会产生以下捕获：

```text
value     = load_user()
some      = user
some_body = display(user)
none_body = show_error()
```

模式中的 `match`、`Some`、`None` 和两个分支的位置属于固定结构。使用 `Ok` 和 `Err` 分支的表达式不满足这个模式。`Some(1)` 也不满足 `Some($(some:id))`，因为 `1` 的语法类别是常量，`$(some:id)` 要求该位置是标识符。

同一个具名元变量可以在一条模式中出现多次。重复捕获必须按 kind 保持一致：`id`
比较规范化后的名称，`const` 比较解析后的常量，`exp`、`arg`、`pat`、`type`
等 CST 类型的捕获按忽略源码位置的语法树结构比较。例如：

```moonbit
$(value:exp) == $(value:exp)
```

这个模式可以匹配：

```moonbit
user.name == user.name
```

下面的表达式不满足该模式：

```moonbit
user.name == other.name
```

这里的 `value` 是 `exp` 捕获，因此两次捕获的语法树必须结构相等，源码位置不参与比较。

`$_` 表示忽略占位符。它可以匹配当前位置上的任意内容，不记录捕获结果。同一模式中的多个 `$_` 相互独立。

## 结构化输出

默认情况下，moongrep输出为人类用户准备的报告。如果希望让Coding Agent读取moongrep的输出, 请加上`--output-json`选项.

```bash
moongrep scan --pattern 'inspect($_, content="true")' --output-json
moongrep dump --output-json --expr 'x + 1'
```

JSON 模式下，每个非空应用输出行都是一个紧凑 JSON object。对于 `scan` 和
`lint`，标准输出只包含 `finding` 记录；对于 `dump`，成功且未启用 exit-code
模式时会在标准输出写出一条 `dump` 记录。标准错误只包含 `trace`、`warning` 和
`error` 记录。没有命中时标准输出为空。记录按遍历顺序流式写出，后续失败不会
撤回已经写出的记录。

稳定记录结构如下：

```text
finding: { "type":"finding", "file", "rule_id", "description", "range",
           "matched_source", "source_context" }
warning: { "type":"warning", "category", "message", ...详情字段 }
trace:   { "type":"trace", "event", ...事件字段 }
dump:    { "type":"dump", "kind":"impl"|"expr", "content" }
error:   { "type":"error", "category", "exit_code", "message",
           ...可选诊断字段 }
```

warning category 是 `parse` 和 `invalid_skip_payload`。trace event 是
`rule_loaded`、`directory_entered`、`path_skipped` 和 `file_started`。error
category 是 `internal`、`usage`、`dump_input`、`rule_source`、
`rule_content`、`scan_input` 和 `output`。

CLI 会在完整解析前识别首个命令为 `scan`、`lint` 或 `dump` 时的独立
`--output-json`，因此未知选项、缺少参数值等用法错误也输出 JSON。选项终止符
`--` 之后的 `--output-json` 不会被当作选项。成功的帮助输出仍是普通文本。

## 模式附加条件

`--guard`选项可以为表达式模式添加额外的筛选条件，筛选条件的对象是表达式模式里面的元变量捕获的内容。

下面的例子使用 `--guard` 查找预期值为数字的 `inspect` 调用。

```bash
moongrep scan --pattern 'inspect($_, content=$(str:const))' --guard '{$str: "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?$"}'
```

`--guard`的参数是一个YAML Map，通常紧跟在需要筛选的`--pattern`之后：

```text
--pattern '...$(name:id)...$(value:const)...' \
--guard '{$name: "正则表达式", $value: "正则表达式"}'
```

映射的键必须是模式中已经声明的具名元变量，并保留`$`前缀；映射的值必须是正则表达式字符串。建议用单引号包住整个YAML Map，避免shell展开`$name`，再用双引号包住其中的正则字符串。双引号YAML字符串中的反斜杠需要转义，例如正则中的`\.`要写成`\\.`。

目前guard只能筛选`id`和`const`捕获，不能筛选`exp`、`arg`、`pat`、`type`、ellipsis捕获或`$_`。对于`id`捕获，正则匹配的是归一化后的标识符，例如`name`或`@pkg.name`；对于`const`捕获，正则匹配的是parser得到的常量值，例如字符串字面量`"raw"`对应`raw`，数字`42`对应`42`，布尔值`true`对应`true`。

正则默认使用包含匹配语义。例如`"raw"`也会匹配`"draw"`；需要匹配整个捕获值时，应使用`^`和`$`，写成`"^raw$"`。同一个映射中的多个条件必须全部满足，因此可以同时限定函数名和参数：

```bash
moongrep scan --pattern '$(callee:id)($(value:const))' --guard '{$callee: "^@html\\.render$", $value: "^(danger|raw)$"}'
```

每个`--pattern`最多接受一个`--guard`。如果需要扫描多个带筛选条件的模式，应按`--pattern`、`--guard`成对书写；一个模式需要多个条件时，应把它们放在同一个YAML Map中。

## 打印 CST

MoonBit `untyped_cst` 调试 dump 可通过 `dump` 子命令使用：

```bash
moongrep dump --impl 'fn answer { 42 }'
moongrep dump --expr 'x + 1'
moongrep dump --output-json --expr 'x + 1'
moongrep dump --exit-code --expr 'x + 1'
```

命令行参数概要：

```text
moongrep dump [--exit-code] [--output-json] (--impl <impl> | --expr <expr>)
```

使用 `--impl <impl>` 可以解析一个 MoonBit 顶层实现项，并打印它的 `untyped_cst`
调试输出。使用 `--expr <expr>` 可以解析一个 MoonBit 表达式，并打印它的
`untyped_cst` 调试输出。要生成 dump，必须且只能提供这两个互斥选项中的一个。

使用 `--output-json` 会写出一条紧凑记录，其中 `type` 为 `"dump"`，`kind` 为
`"impl"` 或 `"expr"`，`content` 包含相同的 CST `Repr` 文本。JSON 转义保证整条
记录只占一个物理输出行。

使用 `--exit-code` 可以执行相同的解析校验而不打印 CST。检查成功时不输出 CST，
即使同时提供 `--output-json`，两个输出流也都为空，并以退出码 0 退出；输入无效时
仍打印诊断并以退出码 3 退出，存在 `--output-json` 时使用现有 JSON `error` 记录
schema。

不带参数调用 `moongrep dump` 会打印 `dump` 帮助，并以退出码 0 成功退出。用法
错误，例如组合使用 `--impl` 和 `--expr`，会打印消息并以退出码 2 退出。解析或
词法失败会打印消息并以退出码 3 退出。`dump --output-json` 未提供输入时报告 JSON
usage error；`dump --output-json --help` 仍打印普通帮助。

## 退出状态

帮助、成功 dump、有命中、无命中和可恢复扫描 warning 都返回 0。失败使用以下
固定类别：

| 状态码 | 含义 |
|---:|---|
| 1 | 内部或未分类错误，包括损坏的 builtin 规则 |
| 2 | 命令行用法错误 |
| 3 | 无效 `dump` 输入 |
| 4 | 规则来源不存在、不可读或类型错误，或规则目录不包含 `.yaml` 或 `.yml` 文件 |
| 5 | YAML 为空白或无效、单文件 `--rule` 后缀不受支持，或规则 schema、pattern、guard、编译后的规则内容无效 |
| 6 | 扫描输入不存在或不可读 |
| 7 | 标准输出或标准错误写入失败 |

无命中扫描不采用 grep 风格的状态码 1，源码解析 warning 也仍返回 0。

## 文档

仓库内提供以下中文详细文档：

- [规则规范](docs/RuleSpec_CN.md) 规定 YAML 规则、校验和匹配器语义。
- [CLI 规范](docs/CLISpec_CN.md) 规定命令行解析、扫描、输出、诊断和退出行为。

英文版本也可以通过 `docs` 子命令查看：

```bash
moongrep docs --list
moongrep docs RuleSpec
moongrep docs CLISpec
```
