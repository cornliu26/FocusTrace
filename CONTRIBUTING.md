# Contributing to FocusTrace

感谢你改进 FocusTrace。这个项目优先保护用户隐私，并保持行为分析可解释。

## 开发环境

- macOS 14 或更高版本；
- Swift 6；
- 完整 Xcode，或 Apple Command Line Tools。

构建和验证：

```bash
./Scripts/test.sh
./Scripts/build-app.sh
```

## 提交原则

- 先阅读 [产品纲领](./Docs/PRODUCT_DOCTRINE.md) 和 [质量门禁](./Docs/QUALITY_GATES.md)；
- 每个功能必须说明解决的注意力问题、明确边界，并覆盖触发、行动、反馈、恢复和完成的闭环；
- 重要产品变化先复制 [决策模板](./Docs/decisions/TEMPLATE.md)，不要从 UI 或数据字段直接开工；
- 新行为增加聚焦单元测试，已发布路径增加回归测试，性能敏感路径保留固定负载和预算；
- 不得为了通过测试而删除既有断言、放宽性能预算或悄悄改变交互形式；
- 不采集窗口标题、网页地址、聊天对象、键盘输入或手机行为；
- 「任务停车」的恢复线索必须由用户显式输入，不得从应用内容推断；聚合 Markdown 报告不得包含线索原文；
- 新增采集字段必须说明用途、保留期和界面可见性；
- 行为日志不能用于自动诊断 ADHD；
- 个性化建议应给出可读证据，并由用户确认后生效；
- 修改分析规则时同步增加可执行验证用例；
- 不要提交 `.build`、`dist`、`.focustrace` 或真实 `store.json`。

提交 Pull Request 前请运行测试，并在描述中说明用户结果、功能边界、流程闭环、回归证据和隐私影响。
