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

- 不采集窗口标题、网页地址、聊天对象、键盘输入或手机行为；
- 新增采集字段必须说明用途、保留期和界面可见性；
- 行为日志不能用于自动诊断 ADHD；
- 个性化建议应给出可读证据，并由用户确认后生效；
- 修改分析规则时同步增加可执行验证用例；
- 不要提交 `.build`、`dist`、`.focustrace` 或真实 `store.json`。

提交 Pull Request 前请运行测试，并在描述中说明行为变化和隐私影响。
