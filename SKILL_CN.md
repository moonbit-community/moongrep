# moongrep

`moongrep` 是一个实验性的 MoonBit 结构化搜索和污点分析工具。



## 扫描

`moongrep`的最简单使用方法是在一个MoonBit项目根目录运行scan命令(默认递归扫描，但是会绕过Git和MoonBit工具链生成的目录), 并使用`--pattern`选项指定一个*表达式模式*进行匹配。例如，下面这条命令匹配典型的对Option类型的值进行`match`的表达式。

```bash
moongrep scan --pattern 'match $(value:exp) { Some($(some:id)) => $(some_body:exp); None => $(none_body:exp) }'
```

### 表达式模式和元变量

`moongrep`会将表达式模式和待扫描的 MoonBit 代码解析成抽象语法树（AST），然后比较两棵语法树的结构。模式中的普通 MoonBit 语法表示固定结构，元变量表示需要匹配和捕获的语法节点。换行、缩进等排版差异通常不会影响匹配结果。

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

同一个具名元变量可以在一条模式中出现多次。每次出现都必须捕获结构相同的语法节点。例如：

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

重复捕获的比较基于语法树结构，源码位置不参与比较。

`$_` 表示忽略占位符。它可以匹配当前位置上的任意内容，不记录捕获结果。同一模式中的多个 `$_` 相互独立。

默认情况下，moongrep输出为人类用户准备的报告。如果希望让Coding Agent读取moongrep的输出, 请加上`--output-json`选项.

```bash
moongrep scan --pattern 'match $(value:exp) { Some($(some:id)) => $(some_body:exp); None => $(none_body:exp) }' --output-json
```

命令行参数概要：

```text
moon runwasm moonbit-community/moongrep -- scan [--verbose] [--output-json] [--enable-builtin-rules] [--exclude-dir <dir>...] [--exclude-rules <rule-id>...] ((--rules <rules-root> | --rules=<rules-root> | -r <rules-root> | --rule <rule-file>) | --pattern <pattern> [--guard <guard>])... [scan-root]
```

## 打印ast

MoonBit `untyped_ast` 调试 dump 可通过 `dump` 子命令使用：

```bash
moon runwasm moonbit-community/moongrep -- dump --impl 'fn answer { 42 }'
moon runwasm moonbit-community/moongrep -- dump --expr 'x + 1'
```

命令行参数概要：

```text
moon runwasm moonbit-community/moongrep -- dump (--impl <impl> | --expr <expr>)
```

使用 `--impl <impl>` 可以解析一个 MoonBit 顶层实现项，并打印它的 `untyped_ast`
调试输出。使用 `--expr <expr>` 可以解析一个 MoonBit 表达式，并打印它的
`untyped_ast` 调试输出。这两个选项互斥，且必须提供其中之一。

用法错误，包括同时缺少两种 dump 模式，或组合使用 `--impl` 和 `--expr`，会打印
消息并以退出码 2 退出。解析或词法失败会打印消息并以退出码 1 退出。

## 文档

内嵌文档可通过 `docs` 子命令查看：

```bash
moon runwasm moonbit-community/moongrep -- docs --list
moon runwasm moonbit-community/moongrep -- docs RuleSpec
```
