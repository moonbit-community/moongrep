# 污点引擎

引擎通过语义降级、显式 CFG 和 SCC 工作队列完成过程内分析。求解器不读取 CST 子字段。

- `domain`：绑定身份、存储路径、不可变 `TaintValue`、来源与 finding。
- `model`：归一后的调用信息、纯调用 transfer、正常及异常结果的独立写入。
- `cfg`：基本块、位置参数、指令、终结指令、验证器、SCC 和临时值活跃性。
- `lowering`：词法绑定解析、parser 字段映射、表达式及控制流降级。
- `engine`：每规则每源码调用点只绑定一次模型，仅输入变化时调度后继。

先调用 `prepare_function_like(node)`，得到不适用、准备成功或不支持诊断。
准备结果缓存验证、SCC 和活跃性，多条规则共享。结构规则不构建 CFG。
再调用 `analyze(prepared, spec, options?)`，得到 `Complete(findings)` 或
`Incomplete(diagnostics)`。`AnalysisOptions.max_scc_rounds` 默认 64；超限不发布
该函数、该规则的任何部分 finding。非法图属于内部错误。不可达状态与可达的干净状态分开。

`TaintValue` 用默认污染及显式子路径覆盖表示值，允许干净覆盖。
存储、临时值、解构及调用子路径共用投影操作。已知字段、tuple 位置和常量索引强更新，
保留兄弟路径；动态索引读取合并可能元素，写入对摘要和已有覆盖弱更新，净化不清除不唯一目标。
join 合并有效值，而非覆盖标记。存储根为 `BindingId`，参数源用 `ParameterPath` 按名解析。
变量遮蔽及清理链展开后的绑定身份均由前端处理，无字符串作用域恢复逻辑。

短路使用执行及跳过边；条件绑定仅成功时可见。case 和 guard 失败后的副作用传向后续 case。
receiver、索引和右侧按顺序各执行一次；增量赋值先保存旧值。record 更新保留未覆盖字段。
循环初值先在外层求值，再引入绑定；更新先保存所有结果，再按位置同时传递。
普通循环体进入更新块，显式 continue 跳过更新。只有自然结束进入 nobreak。

清理在退出时逆序执行，使用声明处词法身份和退出时存储。待退出结果先成为块参数。
errdefer 仅异常时执行；清理抛错替换待退出结果，并继续剩余异常清理。
try! 异常进入中止，不能进入外层 catch。清理链按栈、退出种类和目标共享。
这些语义由 `compiler_semantics_test.mbt` 和
[官方语言文档](https://docs.moonbitlang.com/en/latest/language/fundamentals.html#defer-and-errdefer-expressions)核对。

`TaintSpec.bind_call` 收到污点为空的静态调用信息，返回以求值快照为输入的纯 transfer。
transfer 可重复执行，禁止外部副作用和随迭代变化的 source 身份。返回 `None` 时使用通用模型。
正常与异常 `CallOutcome` 各有独立值和写入；结果为 `None` 表示不可能的退出。
异常边仅来自显式 raise 和模型声明，未知调用不推断异常。

YAML 格式和 finding 字段不变。默认输出 `taint_incomplete` warning 并继续扫描。
不支持语法跳过整个函数，求解超限仅跳过函数与规则组合。`--strict-taint` 在扫描完成后
以状态码 8 结束；妨碍污点分析的解析失败也计入。跨过程、通用堆别名、async 取消及隐式控制流污点
不在本轮范围。API 迁移见 [MIGRATION.md](MIGRATION.md)，性能见 [BENCHMARKS.md](BENCHMARKS.md)。
