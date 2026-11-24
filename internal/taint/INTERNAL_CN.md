# 污点引擎内部说明

`internal/taint` 以单个函数为单位执行过程内污点分析：先将 MoonBit CST 转换为显式
控制流图（CFG），再基于强连通分量（SCC）工作队列求解。求解器不直接读取 CST
节点。

## 子包架构

| 子包 | 职责 |
| --- | --- |
| `domain` | 绑定身份（`BindingId`）、存储路径、不可变 `TaintValue`、污点来源与 sink finding。 |
| `model` | 规范化调用信息（`CallInfo`）、声明式调用模型与纯调用转移函数。 |
| `cfg` | 基本块、位置块参数、指令、终结指令、图验证器、Tarjan SCC 拓扑调度与临时值活跃性。 |
| `lowering` | 词法绑定解析、解析器字段规范化与规则无关的 CFG 构造。`expressions.mbt` 中的 `supports` 表声明可执行语法支持清单；未列出的语法或缺失必需字段必须输出诊断，绝不静默返回干净值。 |
| `engine` | 每原始调用点每规则仅绑定一次模型、SCC 不动点求解及收敛后收集 finding。 |

## 准备与分析流程

### 1. 准备阶段（`prepare_function_like(node)`）

- 返回 `NotApplicable`（无 body 声明或非函数项）、`Prepared(function)` 或
  `Unsupported(diagnostics)`。
- 缓存图验证结果、SCC 拓扑顺序和临时值活跃性，同一份 `PreparedFunction` 可在多条
  规则间共享。纯结构规则不会触发 CFG 构建。
- 非法图属于内部错误（`InvalidGraph`）；验证器检查身份、引用、参数个数、定义
  唯一性以及所有可达入口路径上的值可用性。

### 2. 求解阶段（`analyze(prepared, spec, options?)`）

- 返回 `Complete(findings)` 或 `Incomplete(diagnostics)`。
- `AnalysisOptions.max_scc_rounds` 默认为 `64`（不做 widening）。
- SCC 按拓扑顺序执行；分量内每个基本块每轮按稳定顺序最多执行一次，仅当输入变化
  时才调度后继。
- 不可达状态与可达干净状态分开表示；活跃性分析避免死临时值在回边上循环。
- 超过轮次预算时会抑制该函数在该规则下的**全部**命中（不发布部分结果）。
- 收敛后的 finding 按 `(sink_id, 源码范围)` 去重，并按范围与身份排序。
- 可选 `AnalysisMetrics` 记录累计块访问数、输入变更数和唯一绑定调用点数，供确定
  性复杂度测试和基准测试使用。

## 值与存储域

- `TaintValue` 用默认继承污点加显式子路径覆盖（允许干净覆盖）表示值；存储读取、
  表达式投影、解构与调用子路径传播共用 `project`。
- **强更新与弱更新**：
  - 已知结构体字段、元组槽和常量数组索引采用强更新并保留兄弟路径。
  - 数组维护默认元素摘要与常量索引覆盖：动态读取合并所有可能元素；动态写入对
    摘要与已有常量覆盖执行弱更新；动态净化不能清除无法证明唯一性的元素。
- `join` 合并有效值而非覆盖标记本身。来源身份由 `(规则, 来源身份, 原始源码位置)`
  稳定标识，集合相等比较不依赖顺序。
- 存储根为 `BindingId`（被遮蔽的变量拥有独立 ID）；参数来源通过 `ParameterPath`
  在分析入口按名称解析。清理链复制到多条退出路径时复用词法作用域与绑定 ID，从而
  共享调用模型绑定。

## 控制流语义

下列语义由 `compiler_semantics_test.mbt` 对齐已安装编译器，并与[MoonBit 官方语言
文档](https://docs.moonbitlang.com/en/latest/language/fundamentals.html#defer-and-errdefer-expressions)
保持一致（异步取消不在分析范围内）：

- **短路与分支**：短路操作数拥有执行边与跳过边；条件绑定仅在成功边可见；case 与
  guard 失败后的副作用传递到后续 case。不做通用可达性推理或隐式控制流污点传播。
- **求值顺序与更新**：receiver、索引与右值按源码顺序各求值一次；复合赋值先保存
  旧目标值再求值右值；记录更新从基准值出发，仅替换显式指定的字段。
- **循环**：初值在外层环境中求值后再引入循环绑定；更新先求值所有右值再按位置
  同时提交循环参数；循环体自然结束进入更新块，显式 `continue` 直接跳往下一轮
  头部；`break` 与外层跳转绕过 `nobreak`（仅自然结束进入 `nobreak`）。
- **清理与异常**：`defer` 在声明处捕获词法身份，退出时按声明逆序读取退出时刻的
  存储（待退出结果与跳转参数先变为块参数）。`errdefer` 仅在异常退出时运行；清理
  块抛出的错误替换待退出结果并沿剩余清理链继续传播。清理链按 `(作用域栈, 退出
  类型, 目标)` 共享缓存。`try!` 异常进入 `Abort`，不会到达外层 `catch`。

## 调用与 YAML 规则集成

- `TaintSpec.bind_call` 在每个原始调用点与规则组合上**只调用一次**，接收污点为
  空的静态元数据，返回基于求值快照 `CallInfo` 的纯转移函数。转移函数会在求解与
  最终收集期间多次执行，因此不能产生外部副作用、不能修改输入，且来源身份不得随
  迭代变化。
- 返回 `Some(transfer)` 会覆盖声明式模型与 `unknown_call_policy`；返回 `None`
  则回退到它们。
- 正常与异常 `CallOutcome` 各自拥有独立返回值与存储写入（`None` 表示不可能发生
  该退出）。只有显式 `raise` 与模型声明的异常结果才会激活异常边，未知调用从不
  隐式抛异常。
- 已解析的局部/参数被调用目标会附带 `callee_binding`，可通过
  `CallMatcher::CalleeBinding` 精确选择。
- **YAML 规则**：`internal/rule/taint_lowering` 在绑定阶段缓存 source/sanitizer/
  sink 匹配，未命中调用保持 `NoEffect`。`internal/rule/apply` 对每个函数只准备
  一次 CFG（纯结构计划不构建 CFG）：遇到不支持语法跳过整个函数，求解超限仅跳过
  受影响的 `(函数, 规则)` 组合，并按 `(文件, 范围, 原因)` 合并诊断同时保留全部
  受影响规则 ID。CLI 默认输出 `taint_incomplete` 警告并继续扫描，启用
  `--strict-taint` 时扫描完成后以状态码 `8` 退出。

## 边界与扩展说明

不在分析范围内：跨过程传播、通用堆别名分析、类型声明检查和异步取消。

新增可执行语法支持时，请先完成 lowering 与解析器字段/行为测试，再在
`expressions.mbt` 的 `supports` 表中启用。API 迁移指南见
[MIGRATION.md](MIGRATION.md)，性能数据见 [BENCHMARKS.md](BENCHMARKS.md)。
