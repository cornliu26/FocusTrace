# FocusTrace

FocusTrace 是一个完全本地运行的 macOS 菜单栏应用，用于区分并记录：

- 前台应用切换；
- 由 macOS 桌面（Space）识别的工作流切换；
- 用户主动标记的任务切换；
- 专注会话中经用户确认的非必要偏离。

它不会读取窗口标题、浏览器地址、聊天对象、键盘内容或手机数据，也不用于诊断或治疗 ADHD。

本项目以 [MIT License](LICENSE) 开源。欢迎先阅读 [贡献指南](CONTRIBUTING.md)，尤其是其中的隐私边界。

## 当前功能

- 按自定义工作日和工作时间自动记录前台应用；
- 将当前 macOS 桌面绑定到工作流，并在切换桌面后自动切换工作流上下文；
- 菜单栏可只填名称后“新建工作流并绑定当前桌面”，产出和允许应用稍后补充；
- 未绑定、识别中或冲突桌面绝不沿用旧工作流归因；
- 工作流完成、30 秒撤销、重新打开、归档，以及重启后的明确重新绑定；
- 记录 Space、锁屏、睡眠和唤醒标记；
- 将 macOS `loginwindow` 识别为锁屏边界，解锁前的时间不计入应用时长；
- 手动任务标签，以及每个任务自己的允许应用集合；
- 「任务停车」：Agent 等待或临时切换前留下一句恢复线索，可选本地提醒；
- 3 个工作日静默基线；
- 专注倒计时、20 秒温和提醒和提醒后的四种处理方式；
- 训练中离开所属工作流有 10 秒宽限，超过后暂停有效计时，返回原桌面自动恢复；
- 5 分钟聚合的任务/主应用/切换密度时间轴，关键事件按 15 分钟合并，原始片段可按需展开；
- 5 次训练一轮的 5 分钟升降级规则；
- 满足 10 个工作日和 20 次训练后启用本地针对性分析；
- 训练计划版本、接受调整与回退；
- JSON/CSV 导出、90 天默认保留和按日/全部删除；
- 可选登录时启动。
- 跨天时自动切到今日时间轴；未创建或未选任务时显示明确引导。

## 构建与测试

环境要求：macOS 14 或更高版本、Apple Silicon、Swift 6 Command Line Tools。

```bash
./Scripts/test.sh
./Scripts/build-app.sh
./Scripts/run-space-acceptance.sh  # 可选：独立三桌面验收
```

`test.sh` 会先编译 Swift Testing 测试目标，再运行独立的
`FocusTraceVerification` 验证器。后者用于弥补仅安装 Command Line Tools
时缺少 `xctest` 运行器的问题，确保检查不是只编译而没有执行。

`run-space-acceptance.sh` 会启动一个跨所有 Space 显示的独立验收窗口。
它只创建进程内临时锚点，不读取或写入正式 FocusTrace 数据；依次绑定三个
桌面后，工具会统计 30 次真实切换的正确率和最大识别延迟，并将结果写入
`.build/space-acceptance-result.json`。

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
任务停车的「回来后第一步」也不会进入 Markdown 日报，只会输出
挂起次数、返回次数和平均恢复耗时。
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
- 工作流切换：进入另一个已绑定的 macOS 桌面；这是主要上下文边界，不自动等于分心。
- 任务切换：用户明确选择另一个任务。
- 疑似分心：基线完成后，专注会话进入非允许应用并持续达到提醒阈值。
- 确认分心：只能由用户通过提醒或每日回顾确认。
- 任务停车：用户主动挂起未完成任务，并手动写下回来后的第一步；返回时记录恢复耗时。

短于阈值的非允许应用切换仍会出现在原始时间轴，但不会生成分心事件。

## 任务、工具与浏览器上下文的粒度

FocusTrace 不把应用当成任务。三个概念分开处理：

- **工作流**按期望产出定义，例如“修复登录问题”或“写完设计文档”；启用桌面模式后由 Space 切换驱动；
- **工具**是可复用的允许应用集合，例如 Chrome、Codex 和终端，同一个工具可以属于多个任务；
- **浏览器上下文**是窗口、标签组或标签页。隐私默认模式看不到这一层，因此 Chrome 内部切换不会被记为应用切换，也不会触发自动任务切换。

创建任务时可以复制已有任务的工具集合，避免重复勾选。应用层高频切换只是一项描述性指标，不等于任务切换或分心。

如果未来需要在不读取 URL、标题和页面内容的前提下区分 Chrome 上下文，推荐采用明确选择后才启用的本地浏览器扩展：只传递临时 `windowId` / `groupId` 和用户手动建立的“标签组 → FocusTrace 任务”映射。默认模式仍保持零浏览内容采集；未分组标签页继续依靠用户手动切换任务。相比读取标签标题或 URL，这种方案可解释、可纠正，也更符合最小权限原则。

## 工程结构

桌面驱动的工作流模型、公开 API 边界与完整生命周期见 [Docs/WORKFLOW_SPACES_DESIGN.md](Docs/WORKFLOW_SPACES_DESIGN.md)。当前版本已实现单显示器锚点原型，并通过三桌面 30 次真实切换验收；多显示器组合尚未验证，因此不宣称完整支持。

- `Sources/FocusTraceCore`：纯 Foundation 领域类型、状态机、指标、训练与分析规则、导出。
- `Sources/FocusTraceMacSupport`：基于 AppKit 公开 API 的单 Space 隐形锚点注册器；单显示器三 Space 已完成 30/30 次真实切换验收，多显示器组合仍待验证。
- `Sources/FocusTrace`：AppKit/SwiftUI 事件采集、本地存储、通知、菜单栏和界面。
- `Sources/FocusTraceReport`：为 Codex 定时任务生成隐私收敛后的本地聚合日报。
- `Sources/FocusTraceVerification`：在纯 Command Line Tools 环境中实际执行验收检查。
- `Sources/FocusTraceSpaceAcceptance`：不污染正式数据的三桌面 30 次切换人工验收工具。
- `Tests/FocusTraceCoreTests`：采集、阈值、基线、升降级、指标、阶段二门槛和导出测试。
- `Packaging` 与 `Scripts`：无 Xcode 的 `.app` 组装、本地签名和验证。

## 手动验收建议

1. 首次启动选择包含当天的工作日和覆盖当前时间的工作时段。
2. 新建任务，将终端和浏览器加入允许应用。
3. 在多个允许应用之间切换，确认时间轴有记录但没有分心提醒。
4. 完成 3 个不同工作日的任务记录后开始专注会话。
5. 切到非允许应用并超过阈值，验证提醒只出现一次。
6. 创建三个 macOS 桌面和三个工作流，在各桌面通过菜单栏绑定；往返切换 30 次，确认工作流识别无误且未绑定桌面不继承旧工作流。
6. 分别验证“返回任务”“本任务所需”“切换任务”和“结束专注”。
7. 锁屏后恢复，确认睡眠区间未被计入应用时间。
8. 导出 JSON 和 CSV，确认没有窗口标题、URL 或输入内容字段。
9. 在 Agent 等待时挂起当前任务，留下一句恢复线索并切换；验证提醒只发送一次，点击「返回任务」后时间轴和回顾立即更新。

## 医疗边界

FocusTrace 只能帮助观察和训练工作习惯。应用切换频繁并不能证明存在 ADHD；如果注意力问题持续在多个场景造成明显影响，应由具备资质的专业人士进行完整评估。
