# Scope 处理审查报告

## 结论

当前分支新增的递归 `then` scope 在规则层级可见性和兄弟节点隔离方面基本正确，但运行时将 `id` 捕获关联到源码词法绑定时存在三个确定的正确性问题，以及一个需要明确语义的遗漏。

其中，第一个问题直接来自新增的递归 `then` scope 实现。第二、三个问题在旧的 `inside` 模型中可能已有类似行为，不一定都是相对 `main` 的新回归，但当前分支把这一模型推广到了通用递归 `then`，扩大了影响范围。

## 问题 1：新捕获的标识符在 target 入口被重新绑定

严重度：高

相关代码：`internal/rule/apply/capture_environment.mbt:116-146`

`target_environment` 为当前 shape 新产生的单值 `id` 捕获建立锚点时，使用：

```moonbit
self.index.resolve(target.scope, text)
```

这会按照捕获文本在 target 入口重新解析绑定，而不是保留捕获点原本的标识符角色和绑定身份。

复现场景：

```yaml
patterns:
  - shape: if $_ is Some($(name:id)) { $_ } else { __TARGET__ }
    then:
      patterns:
        - shape: sink($(name:id))
```

```moonbit
fn sample {
  let item = outer()
  if input is Some(item) {
    consume(item)
  } else {
    sink(item)
  }
}
```

条件中的 `item` 是只在 then 分支可见的绑定变量，而 else 分支中的 `item` 指向外层绑定。当前实现会在 else target 入口把捕获文本 `item` 重新解析为外层绑定，随后错误地接受 `sink(item)`，产生误报。

`SourceIndex` 对条件绑定只流入 then 分支的索引处理本身是正确的；问题发生在 capture environment 丢失捕获来源后重新解析名称。

建议：

- 让匹配结果携带捕获标识符的语法角色和来源节点。
- 对词法变量捕获保留原始 `BindingId`，在进入 target 时验证该绑定是否可见。
- 不要仅根据捕获文本在 target scope 中重新构造绑定身份。

## 问题 2：只检查候选区域入口，漏掉候选内部的遮蔽

严重度：高

相关代码：`internal/rule/apply/capture_environment.mbt:64-85`

`environment_blocks` 只取得整个候选 region 的入口 scope，并在该 scope 中解析所有继承的标识符捕获。对于包含多条语句的原子候选，入口之后可能出现新的局部绑定，从而遮蔽继承捕获，但当前检查无法发现。

复现场景：

```yaml
patterns:
  - shape: wrapper($(name:id), __TARGET__)
    then:
      patterns:
        - shape: let $_ = $_; sink($(name:id))
```

```moonbit
fn sample {
  wrapper(item, {
    let item = source()
    sink(item)
  })
}
```

候选 region 的入口处仍可见外层 `item`，所以入口检查通过；但 `sink(item)` 中的实际引用已经被前一条 `let item` 遮蔽。当前实现仍会报告匹配，产生误报。

这与 `internal/docs/RuleSpec_CN.md:675-678` 中“候选引用被遮蔽的祖先 `id` 时匹配失败”的描述不一致。

建议：

- 按继承 metavariable 在候选中的每个实际出现位置检查源码 scope。
- 或者让匹配器返回捕获出现位置及其解析后的绑定身份，再与继承锚点比较。
- 增加跨语句、候选内部发生绑定遮蔽的回归测试。

## 问题 3：所有 `id` 都被当作值变量参与词法遮蔽

严重度：中

相关代码：`internal/rule/apply/capture_environment.mbt:134-138`

当前实现对所有 `MetavarKind::Identifier` 且为单值的捕获建立词法绑定锚点，没有区分值变量、绑定变量、字段名、访问器 label、构造器或类型名等不同语法角色和命名空间。

复现场景：

```yaml
patterns:
  - shape: wrapper($_.$(field:id), __TARGET__)
    then:
      patterns:
        - shape: sink($_.$(field:id))
```

```moonbit
fn sample {
  wrapper(object.field, {
    let field = source()
    sink(object.field)
  })
}
```

局部值变量 `field` 不应遮蔽访问器字段名 `.field`。当前实现却会把两者放入同一词法名称解析流程，因而阻止子规则匹配，产生漏报。

建议：

- 在 capture 中保留 identifier 的语法角色或命名空间。
- 仅对值变量引用和绑定变量建立 `BindingId` 锚点。
- 字段、label、构造器、类型名等捕获继续按对应命名空间或文本等价规则处理。

## 问题 4：typed-id ellipsis 未参与 scope 检查

严重度：中，需确认预期语义

相关代码：`internal/rule/apply/capture_environment.mbt:134-138`

当前建立词法锚点的条件限定为单值 `Identifier`。`$$$(names:id)` 的结果是多值捕获，因此不会记录任何绑定锚点，后续也不会检查其中各个标识符是否被遮蔽。

复现场景：

```yaml
patterns:
  - shape: wrapper($$$(names:id), __TARGET__)
    then:
      patterns:
        - shape: sink($$$(names:id))
```

```moonbit
fn sample {
  wrapper(a, b, {
    let a = source()
    sink(a, b)
  })
}
```

即使 `sink` 中的 `a` 已经指向新的局部绑定，当前实现仍可能接受匹配。规范把 typed-id ellipsis 作为 `id` 捕获，并允许多值捕获向子规则继承，因此需要明确它是否同样具有词法绑定一致性要求。

建议：

- 如果需要词法一致性，为多值 `id` 捕获逐元素保存锚点。
- 如果有意只对单值 `id` 执行 scope 检查，应在规则规范中明确说明。

## 未发现明显问题的部分

- 递归 `then` 中祖先 capture 的向下可见性。
- 兄弟规则之间的新 capture 隔离。
- immutable capture environment 的分支传递方式。
- `if` 条件绑定只进入 then body 的基础 scope 索引。

## 验证结果

- `moon test`：628/628 通过。
- `moon check`：通过。
- `node scripts/e2e.mjs test`：通过。

现有测试全部通过，说明上述边界场景目前没有被测试覆盖，不能据此排除 scope 正确性问题。
