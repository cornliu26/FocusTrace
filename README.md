# FocusTrace

FocusTrace 是一个完全本地运行的 macOS 菜单栏应用，用于区分并记录：

- 前台应用切换；
- 用户主动标记的任务切换；
- 专注会话中经用户确认的非必要偏离。

它不会读取窗口标题、浏览器地址、聊天对象、键盘内容或手机数据，也不用于诊断或治疗 ADHD。

本项目以 [MIT License](LICENSE) 开源。欢迎先阅读 [贡献指南](CONTRIBUTING.md)，尤其是其中的隐私边界。

## 当前功能

- 按自定义工作日和工作时间自动记录前台应用；
- 记录 Space、锁屏、睡眠和唤醒标记；
- 手动任务标签，以及每个任务自己的允许应用集合；
- 3 个工作日静默基线；
- 专注倒计时、20 秒温和提醒和提醒后的四种处理方式；
- 任务/应用双层时间轴、每日统计和疑似事件人工修正；
- 5 次训练一轮的 5 分钟升降级规则；
- 满足 10 个工作日和 20 次训练后启用本地针对性分析；
- 训练计划版本、接受调整与回退；
- JSON/CSV 导出、90 天默认保留和按日/全部删除；
- 可选登录时启动。

## 构建与测试

环境要求：macOS 14 或更高版本、Apple Silicon、Swift 6 Command Line Tools。

```bash
./Scripts/test.sh
./Scripts/build-app.sh
```

`test.sh` 会先编译 Swift Testing 测试目标，再运行独立的
`FocusTraceVerification` 验证器。后者用于弥补仅安装 Command Line Tools
时缺少 `xctest` 运行器的问题，确保检查不是只编译而没有执行。

生成的应用位于：

```text
dist/FocusTrace.app
```

双击应用，或运行：

```bash
open dist/FocusTrace.app
```

当前系统的 Swift 编译器和 SDK 存在一个补丁版本差异。`Scripts/swiftc-compatible.sh` 会自动检测并仅在需要时增加兼容参数；Command Line Tools 更新匹配后会自动退化为普通 `swiftc`。

## Codex 每日定时回顾

项目提供一个不需要额外 API Key 的本地报告入口：

```bash
./Scripts/generate-daily-report.sh
```

它会由本地 Swift 规则引擎读取 `store.json`，并只把聚合结果写入：

```text
.focustrace/reports/latest.md
```

报告不包含逐条应用轨迹、Bundle ID、事件 ID、窗口标题、URL 或输入内容。
Codex 桌面端的本地定时任务只需执行上述脚本并读取 `latest.md`，不需要
单独开发服务端或配置 OpenAI API Key。Codex 定时任务本身仍使用 Codex
登录态和在线模型；机器需要开机，Codex 桌面应用需要运行。

建议的定时任务提示词是：执行 `./Scripts/generate-daily-report.sh`，只读取
`.focustrace/reports/latest.md`；报告阶段 2 是否解锁、今日指标和唯一一项
建议；不要读取 `store.json`，不要自动修改训练计划。

## 数据与权限

行为数据保存在：

```text
~/Library/Application Support/FocusTrace/store.json
```

写入采用 250ms 合并和原子替换，正常退出时强制落盘；异常退出后，未闭合片段最多恢复为 5 分钟，避免产生无限时长记录。

应用只请求本地通知权限。应用级前台切换采集不需要辅助功能、屏幕录制或输入监控权限。登录时启动只有在设置页明确开启后才注册。

原方案选择 SwiftData，但当前纯 Command Line Tools 缺少 `SwiftDataMacros`，在不安装完整 Xcode 的前提下无法编译 `@Model`。首版因此通过独立 `FocusTraceStore` 使用 Codable 原子快照；领域模型、Core 模块和 UI 不依赖具体存储实现，安装完整 Xcode 后可迁移为 SwiftData 后端而无需重写业务规则。

## 行为定义

- 应用切换：前台 Bundle ID 变化，进入原始时间轴。
- 任务切换：用户明确选择另一个任务。
- 疑似分心：基线完成后，专注会话进入非允许应用并持续达到提醒阈值。
- 确认分心：只能由用户通过提醒或每日回顾确认。

短于阈值的非允许应用切换仍会出现在原始时间轴，但不会生成分心事件。

## 工程结构

- `Sources/FocusTraceCore`：纯 Foundation 领域类型、状态机、指标、训练与分析规则、导出。
- `Sources/FocusTrace`：AppKit/SwiftUI 事件采集、本地存储、通知、菜单栏和界面。
- `Sources/FocusTraceReport`：为 Codex 定时任务生成隐私收敛后的本地聚合日报。
- `Sources/FocusTraceVerification`：在纯 Command Line Tools 环境中实际执行验收检查。
- `Tests/FocusTraceCoreTests`：采集、阈值、基线、升降级、指标、阶段二门槛和导出测试。
- `Packaging` 与 `Scripts`：无 Xcode 的 `.app` 组装、本地签名和验证。

## 手动验收建议

1. 首次启动选择包含当天的工作日和覆盖当前时间的工作时段。
2. 新建任务，将终端和浏览器加入允许应用。
3. 在多个允许应用之间切换，确认时间轴有记录但没有分心提醒。
4. 完成 3 个不同工作日的任务记录后开始专注会话。
5. 切到非允许应用并超过阈值，验证提醒只出现一次。
6. 分别验证“返回任务”“本任务所需”“切换任务”和“结束专注”。
7. 锁屏后恢复，确认睡眠区间未被计入应用时间。
8. 导出 JSON 和 CSV，确认没有窗口标题、URL 或输入内容字段。

## 医疗边界

FocusTrace 只能帮助观察和训练工作习惯。应用切换频繁并不能证明存在 ADHD；如果注意力问题持续在多个场景造成明显影响，应由具备资质的专业人士进行完整评估。
