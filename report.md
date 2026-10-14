# cli/jq 问题报告

本文记录在将 moongrep 的 e2e 测试从 `sed` 改写为 `jq` 时发现的问题。
所有现象均通过直接调用 `moonx` 复现，不依赖 mooncram 或 moongrep。

## 验证范围

- 环境：Linux。
- 被测版本：`cli/jq@0.2.1`，使用 MoonX 默认 Wasm 后端。
- 对照工具：系统安装的 jq 1.6。
- 本文区分实际观察到的行为与原因推测；尚未检查实现源码定位根因。

## 问题概览

| 问题 | 版本 | 实际行为 | 退出码 |
| --- | --- | --- | --- |
| `.end` 字段访问解析失败 | 0.2.1 | 报 `UnexpectedToken("TEnd", "end of query")` | 3 |
| 插值中的 `.end` 字段访问产生错误结果 | 0.2.1 | 输出整个父对象，stderr 为空 | 0 |

## 共用输入

两个问题使用以下文件：

```sh
cat > /tmp/jq-repro.json <<'EOF'
{"range":{"start":{"line":3,"column":4},"end":{"line":5,"column":6}}}
EOF
```

## 1. `.end` 字段访问解析失败

### 复现命令

```sh
moonx cli/jq@0.2.1 -r '.range.end.line' /tmp/jq-repro.json
```

### 预期行为

stdout：

```text
5
```

stderr 为空，退出码为 0。

### 实际行为

stdout 为空，stderr：

```text
moonjq: UnexpectedToken("TEnd", "end of query")
```

退出码为 3。

作为对照，以下命令正常输出 `3`，退出码为 0：

```sh
moonx cli/jq@0.2.1 -r '.range.start.line' /tmp/jq-repro.json
```

系统 jq 1.6 能正确执行原查询，输出 `5`，退出码为 0：

```sh
jq -r '.range.end.line' /tmp/jq-repro.json
```

### 规避方式

使用字符串键访问：

```sh
moonx cli/jq@0.2.1 -r '.range["end"].line' /tmp/jq-repro.json
```

已验证该命令输出 `5`，stderr 为空，退出码为 0。

### 原因推测

错误中的 `TEnd` 提示解析器可能把点号后的字段名 `end` 当成了关键字。
这只是根据错误信息作出的推测，尚未通过源码确认。

## 2. 插值中的 `.end` 字段访问静默产生错误结果

### 最小复现命令

```sh
moonx cli/jq@0.2.1 -r '"\(.range.end.line)"' /tmp/jq-repro.json
```

### 预期行为

stdout：

```text
5
```

stderr 为空，退出码为 0。

### 实际行为

stdout：

```text
{"start":{"line":3,"column":4},"end":{"line":5,"column":6}}
```

stderr 为空，退出码为 0。查询输出了整个 `range` 对象，未取得结束行号。

### 对位置快照的影响

下面的表达式用于组合起止位置：

```sh
moonx cli/jq@0.2.1 -r '"\(.range.start.line):\(.range.start.column)-\(.range.end.line):\(.range.end.column)"' /tmp/jq-repro.json
```

预期 stdout：

```text
3:4-5:6
```

实际 stdout：

```text
3:4-{"start":{"line":3,"column":4},"end":{"line":5,"column":6}}:{"start":{"line":3,"column":4},"end":{"line":5,"column":6}}
```

退出码仍为 0，stderr 为空。系统 jq 1.6 对上述两条插值查询均输出预期结果。

### 风险

普通查询会明确报错，而插值查询成功退出并产生错误数据。
仅检查退出码的调用方无法发现问题；更新测试快照时，也可能把错误结果保存为预期。

### 规避方式

插值内部同样使用字符串键访问：

```sh
moonx cli/jq@0.2.1 -r '"\(.range.start.line):\(.range.start.column)-\(.range["end"].line):\(.range["end"].column)"' /tmp/jq-repro.json
```

已验证该命令输出 `3:4-5:6`，stderr 为空，退出码为 0。

### 原因推测

错误结果与只执行了 `.range` 的结果相同，因此插值解析可能在遇到 `end`
时保留了前面的表达式，而未正确报告剩余部分的解析错误。
尚未检查源码，不能确认具体的截断、错误传播或语法校验过程。

## 建议的回归检查

- `.range.end.line` 应输出 `5`，与 `.range["end"].line` 一致。
- `"\(.range.end.line)"` 应输出 `5`，与普通字段查询一致。
- 起止位置插值应输出 `3:4-5:6`。
- 插值内的非法查询应明确报错，不能接受部分表达式并成功退出。

当前 moongrep e2e 测试的规避方式是固定使用 `cli/jq@0.2.1`，并将结束位置字段
写成 `.range["end"]`。本报告不表示项目整体 e2e 验证已经完成。
