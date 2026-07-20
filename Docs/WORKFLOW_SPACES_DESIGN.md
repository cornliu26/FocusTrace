# FocusTrace：以 macOS 桌面为工作流上下文

> 实现状态（2026-07-20）：W1 生命周期、W2 单显示器锚点原型，以及 W3 的快速创建绑定与训练跨桌面暂停/恢复已接入应用；当前桌面绑定、冲突保护和解除已通过无持久化 AppKit 自检。三桌面 30 次真实往返切换已通过（30/30、0 次误识别、最大延迟 0.265 秒）；多显示器组合仍属于待验收阶段。

## 结论

桌面（Space）应成为 FocusTrace 的**主要工作流上下文**，应用切换只作为桌面内部的次级行为信号。

采用以下约束：

1. 一个桌面最多绑定一个未完成工作流；一个工作流可以绑定多个桌面。
2. 工作流切换由桌面切换触发，不再从应用或浏览器标签推断。
3. 桌面内的允许应用切换只是工具使用；非允许应用持续出现才是“疑似子分心”。
4. 创建、完成、解除绑定都需要用户明确动作；普通桌面切换零确认、零弹窗。
5. 识别失败时进入“上下文未知”，不沿用旧工作流，也不猜测。

## macOS 公开 API 边界

`NSWorkspace.activeSpaceDidChangeNotification` 能可靠通知 Space 发生变化，但通知不包含 `userInfo`，因此没有公开的 Space ID。

Apple 的公开 AppKit 接口也没有创建、删除或给系统 Space 命名的 API。FocusTrace 首版只绑定用户已经通过 Mission Control 创建的桌面，不用辅助功能脚本替用户操作 Mission Control。

公开 API 可行的首版方案是“桌面锚点”：

- 用户在当前桌面绑定工作流时，FocusTrace 创建一个属于该桌面的不可交互 `NSPanel`；
- 锚点使用默认的单 Space collection behavior，不加入所有 Spaces；
- 收到 Space 变化通知后，检查每个锚点的 `NSWindow.isOnActiveSpace`；
- 恰好一个命中时识别对应工作流；零个命中时进入未绑定状态；多个命中时进入冲突状态。

相关公开接口：

- [activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification)
- [NSWindow.isOnActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace)
- [NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)

不在默认版本中调用 SkyLight / CoreGraphics 私有 Space API。私有 API 虽可读取内部 Space ID，但存在系统升级失效、签名与分发风险。

### 锚点恢复边界

锚点窗口属于进程。正常运行期间，绑定可以无感工作；应用异常退出或系统重启后，不能把旧桌面身份当作已确认。

恢复顺序：

1. 尝试通过 AppKit window restoration 恢复锚点；
2. 逐个验证恢复后的锚点是否能唯一命中当前桌面；
3. 无法验证的绑定标记为 `needsRebind`；
4. 用户下次进入该桌面时，只显示菜单栏内联操作“重新绑定到 ××”，不弹阻塞窗口；
5. 未重新绑定期间记录原始应用行为，但不归因到任何工作流。

## 概念与数据模型

### 1. Workflow

工作流按**预期产出**命名，不按应用命名。

```text
Workflow
  id
  name
  expectedOutcome
  allowedBundleIDs / toolProfileIDs
  lifecycle: open | completed | archived
  createdAt
  completedAt?
```

`open / completed / archived` 是持久生命周期，不表示它此刻是否在前台。

### 2. WorkflowPresence

工作流在某一刻的运行位置单独表示：

```text
unbound       已创建但未绑定桌面
background    已绑定，但不是当前桌面
foreground    当前桌面对应的工作流
parked        用户明确留下恢复线索
unknown       当前桌面无法可靠识别
```

这样“切走桌面”只会令工作流从 `foreground` 变为 `background`，不会把工作流错误地完成或挂起。

### 3. WorkflowSpaceBinding

```text
WorkflowSpaceBinding
  id
  workflowID
  anchorRestorationID
  displayHint?
  state: verified | needsRebind | conflict | released
  boundAt
  lastVerifiedAt?
```

关系约束：桌面到工作流是 0..1；工作流到桌面是 0..N。

### 4. WorkflowInterval

```text
WorkflowInterval
  workflowID?
  startedAt
  endedAt?
  source: space | manual | recovery
  confidence: verified | unknown
```

每次稳定桌面切换都闭合旧区间并打开新区间。`workflowID == nil` 表示未绑定桌面，不把时间错误归给之前的工作流。

### 5. WorkflowCheckpoint

沿用现有任务停车能力，但把它定义为可选检查点：

```text
WorkflowCheckpoint
  workflowID
  resumeCue
  createdAt
  resolvedAt?
  remindAt?
```

只有用户需要“回来后的第一步”时才创建检查点；普通桌面切换不要求填写。

## 完整生命周期

### A. 创建

入口只在菜单栏提供，不阻塞当前工作：

- 用户先用原有习惯在 Mission Control 中增加一个桌面；
- 当前桌面未绑定时显示 `未绑定桌面`；
- 主操作：`新建工作流并绑定当前桌面`；
- 次操作：`绑定到已有工作流`；
- 新建只要求名称，默认生成 `工作流 N`，产出与工具可稍后补充；
- 创建成功立即进入 `open + foreground`，开始 WorkflowInterval。

创建工作流不会创建专注训练，也不会弹出任务编辑大表单。

### B. 处理

桌面切换状态机：

```text
收到 Space changed
  -> 等待 600ms 动画稳定
  -> 读取锚点命中
     -> 1 个：切换到对应工作流
     -> 0 个：进入 unknown / unbound
     -> 多个：进入 conflict，不自动归因
```

同一目标在 2 秒内反复通知只保留最终状态。切换时：

1. 闭合旧 WorkflowInterval；
2. 打开新 WorkflowInterval；
3. 重新关联当前前台应用片段；
4. 菜单栏标题无动画地更新；
5. 不弹窗、不要求写恢复线索、不自动完成任何工作流。

### C. 挂起与恢复

挂起不是桌面切换的必经步骤。

- 用户需要保存脑内状态时，主动选择 `留下恢复线索`；
- 回到该工作流桌面时自动标记为已恢复，并在菜单栏短暂展示线索；
- 普通 `background -> foreground` 不产生挂起记录。

### D. 完成

完成只能由用户明确触发：

- 菜单栏提供 `完成当前工作流`；
- 一次点击完成，不强制填写总结；
- 立即闭合当前 WorkflowInterval 和专注计时；
- 释放该工作流的所有桌面绑定，使桌面回到未绑定状态；
- 30 秒内可撤销；撤销后恢复为 `open`，但桌面绑定需要重新确认；
- 完成记录保留，之后可归档或重新打开。

不根据窗口关闭、应用退出、一天结束或长时间无操作自动完成。

### E. 归档与删除

- 归档只隐藏已完成工作流，不删除行为数据；
- 删除行为数据继续使用现有设置页的显式操作；
- 解除桌面绑定不等于完成工作流。

## 行为与“子分心”语义

### 一级：工作流切换

进入另一个已绑定桌面，记录 `workflowSwitch`。这是上下文变化，不自动等于分心。

### 二级：工作流内工具切换

桌面不变时的 Bundle ID 变化只进入 `appSwitch` 和密度统计：

- 允许工具之间切换：正常工具使用；
- 非允许应用不足阈值：静默记录；
- 非允许应用达到阈值：`suspectedSubDistraction`；
- 仍需用户确认后才能成为 `confirmedDistraction`。

### 训练期间离开工作流

首版采用可解释规则：

- 进入另一个已绑定工作流超过 10 秒：暂停当前训练倒计时并记录 `workflowDeparture`；
- 10 秒内返回：视为桌面误触，不暂停；
- 返回原工作流时恢复倒计时；
- 不把合理的并发工作流切换自动算成训练失败，结束回顾时由用户确认是否必要。

## 无感与无损不变量

1. 任意时刻最多一个 `foreground` 工作流。
2. 每个 WorkflowInterval 必须闭合；异常退出最多恢复到最后事件时间。
3. 识别不确定时宁可记为 unknown，也不沿用旧工作流。
4. 切换桌面不完成、不删除、不强制挂起工作流。
5. 完成、归档、删除都不能由推断触发。
6. 同一桌面不能同时绑定两个未完成工作流。
7. 同一工作流可以绑定多个桌面，但这些桌面进入同一统计口径。
8. 浏览器标签、窗口标题、URL 和输入内容继续不采集。

## 可视化（优化项）

时间轴从上到下：

1. **工作流轨道**：按桌面识别出的 WorkflowInterval；
2. **桌面切换标记**：只展示工作流 A → B，不再展示全部 Space 原始事件；
3. **主应用与工具切换密度**：保留现有 5 分钟聚合；
4. **上下文未知区间**：灰色斜纹，提醒数据未归因而不是错误归因。

工作流列表默认只展示：当前、后台、已挂起；已完成折叠。可视化不能改变生命周期语义。

## 迁移方案

为保证旧数据无损，分两步迁移：

1. UI 和领域语言先从 Task 改为 Workflow，存储中的 `tasks` / `taskID` 键暂时保留；旧任务全部迁移为 `open + unbound`。
2. 新增 `workflowSpaceBindings` 和带来源/置信度的 WorkflowInterval；旧 TaskInterval 迁移为 `source = manual, confidence = verified`。

旧的允许应用、专注会话、分心记录、停车线索和训练计划全部保留。

## 实施阶段与验收

### 阶段 W1：生命周期内核

- 新增 WorkflowLifecycle、Presence、Binding、Interval 和转换引擎；
- 完成旧 Task 数据兼容解码；
- 单测覆盖创建、切换、unknown、挂起、完成、撤销和异常恢复。

### 阶段 W2：桌面锚点原型

- 在单显示器上绑定三个桌面到三个工作流；
- 连续来回切换 30 次，识别正确率 100%，稳定切换延迟小于 1 秒；
- 没有可见窗口、Dock 图标或 Mission Control 干扰；
- 无匹配和冲突时绝不沿用旧工作流。

### 阶段 W3：无感交互

- 菜单栏完成新建/绑定/完成/撤销；
- 普通桌面切换零弹窗；
- 回到有检查点的桌面时恢复线索；
- 时间轴展示工作流轨道和 unknown 区间。

### 阶段 W4：恢复与多显示器

- 验证正常退出、崩溃、重启后的锚点恢复；
- 无法可靠恢复时进入 needsRebind；
- 多显示器“独立 Spaces”模式单独验证，未通过前不宣称支持。

只有 W2 的真实桌面切换验收通过后，Space 识别才可替代现有手动任务切换。
