# moongrep

`moongrep` 是一个实验性的 MoonBit 结构化搜索和污点分析工具。
匹配规则以 YAML 文件声明。

## Scan

使用规则目录，以及一个可选的扫描目标目录或 `.mbt` 文件来运行扫描器：

```bash
moon runwasm moonbit-community/moongrep -- scan --rules path/to/rules path/to/src
moon runwasm moonbit-community/moongrep -- scan --pattern 'target()' path/to/src
moon runwasm moonbit-community/moongrep -- scan --pattern '$(callee:id)()' --guard '{$callee: "^safe_"}' path/to/src
```

用法概要：

```text
moon runwasm moonbit-community/moongrep -- scan [--verbose] [--enable-builtin-rules] [--exclude-dir <dir>...] [--exclude-rules <rule-id>...] ((--rules <rules-root> | --rules=<rules-root> | -r <rules-root> | --rule <rule-file>) | --pattern <pattern> [--guard <guard>])... [scan-root]
```

扫描器通过 `scan` 子命令使用。当提供了 `--rule <rule-file>`、至少一个
`--pattern <pattern>`，或启用了 `--enable-builtin-rules` 时，`--rules` /
`-r` 是可选的。长规则选项同时接受 `--rules <rules-root>` 和
`--rules=<rules-root>` 两种形式。使用 `--rule <rule-file>` 可以只加载一个
YAML 规则文件。内联模式会被视为匿名结构化规则，其规则 id 就是模式字符串
本身。`--enable-builtin-rules` 会在命令行提供的规则和内联模式之外，额外加载
内嵌的内置规则。`scan` 参数列表中可以出现一个可选的位置参数 `scan-root`，
默认值为 `.`。如果规则或规则选项出现多次，最后一个值生效。重复的
`--pattern` 值会作为独立的匿名规则追加。可以在匿名 `--pattern` 之后使用
`--guard <guard>`，为其附加 YAML guard 映射；该映射使用以 `$` 为前缀的元变量
键，并采用与规则文件中 `guard` 相同的 schema。

使用 `--exclude-dir <dir>...` 可以在递归扫描源码树时跳过指定的目录名或路径。
当在一个 flag 后传入多个排除目录时，请把 `scan-root` 放在 `--exclude-dir`
之前；也可以重复使用 `--exclude-dir <dir>` 和 `--exclude-dir=<dir>` 形式。

使用 `--exclude-rules <rule-id>...` 可以通过精确的规则 id 禁用已加载的规则。
这适用于内置规则、文件规则、目录规则和匿名模式规则。当在一个 flag 后传入多个
排除规则 id 时，请把 `scan-root` 放在 `--exclude-rules` 之前；也可以重复使用
`--exclude-rules <rule-id>` 和 `--exclude-rules=<rule-id>` 形式。未知的排除
规则 id 会被视为用法错误。

用法错误会打印消息并以退出码 2 退出：缺少 `scan` 命令、缺少所有规则来源
（`--rules`、`--rule`、`--pattern` 和 `--enable-builtin-rules`）、缺少选项值、
`--guard` 位置错误或格式错误、未知选项、未知的排除规则 id，或出现多个扫描
根目录。非用法错误，包括路径不可读、规则目录为空、YAML/schema/shape 无效，
或源码读取失败，都会中止本次运行；CLI 会打印错误并以退出码 1 退出。

传入 `--verbose` 可以在警告和匹配结果之前，打印已加载的规则 id 和目录遍历进度。

每个匹配结果都会打印发现项覆盖的源码行，以及最多两行周边源码上下文。周边上下文
行以灰色渲染；匹配的源码行不使用灰色样式。设置 `NO_COLOR=1` 可以禁用灰色上下文
样式，并使用 `>` 而不是 `|` 渲染匹配的源码行。

如果省略 `scan-root`，`moongrep` 会扫描当前目录：

```bash
moon runwasm moonbit-community/moongrep -- scan --rules path/to/rules
moon runwasm moonbit-community/moongrep -- scan -r path/to/rules
moon runwasm moonbit-community/moongrep -- scan --rule path/to/rule.yaml
moon runwasm moonbit-community/moongrep -- scan --pattern 'target()'
moon runwasm moonbit-community/moongrep -- scan --pattern '$(callee:id)()' --guard '{$callee: "^safe_"}'
moon runwasm moonbit-community/moongrep -- scan --enable-builtin-rules
```

扫描器会递归读取 `.mbt` 文件。从 `scan-root` 向下遍历时，名为 `.git`、`_build`、
`.mooncakes` 或 `target` 的子项会被跳过；如果这些目录之一被显式作为 `scan-root`
传入，则会被扫描。通过 `--exclude-dir` 提供的目录会按 `scan-root` 下任意位置的
条目名跳过，或按精确的子路径跳过。

递归遍历源码或规则时遇到的符号链接会被跟随。解析失败的文件会作为警告报告并跳过；
其他文件会继续被扫描。

## Dump

MoonBit `untyped_ast` 调试 dump 可通过 `dump` 子命令使用：

```bash
moon runwasm moonbit-community/moongrep -- dump --impl 'fn answer { 42 }'
moon runwasm moonbit-community/moongrep -- dump --expr 'x + 1'
```

用法概要：

```text
moon runwasm moonbit-community/moongrep -- dump (--impl <impl> | --expr <expr>)
```

使用 `--impl <impl>` 可以解析一个 MoonBit 顶层实现项，并打印它的 `untyped_ast`
调试输出。使用 `--expr <expr>` 可以解析一个 MoonBit 表达式，并打印它的
`untyped_ast` 调试输出。这两个选项互斥，且必须提供其中之一。

用法错误，包括同时缺少两种 dump 模式，或组合使用 `--impl` 和 `--expr`，会打印
消息并以退出码 2 退出。解析或词法失败会打印消息并以退出码 1 退出。

## Document

内嵌文档可通过 `docs` 子命令使用：

```bash
moon runwasm moonbit-community/moongrep -- docs --list
moon runwasm moonbit-community/moongrep -- docs RuleSpec
```
