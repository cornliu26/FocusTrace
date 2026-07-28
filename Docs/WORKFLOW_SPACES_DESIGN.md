# FocusTrace：以 macOS 桌面为工作流上下文

> 实现状态（2026-07-21）：W1 生命周期与 W3 无感交互已接入。W2 已从窗口锚点迁移到稳定 `(display UUID, managed Space ID/UUID)`；新增桌面不会改变已有绑定。旧锚点数据升级后需一次性重新绑定。多显示器组合仍属于持续验收阶段。

## 结论

桌面（Space）应成为 FocusTrace 的**主要工作流上下文**，应用切换只作为桌面内部的次级行为信号。

采用以下约束：

1. 一个桌面最多绑定一个未完成工作流；一个工作流可以绑定多个桌面。
2. 工作流切换由桌面切换触发，不再从应用或浏览器标签推断。
3. 桌面内的允许应用切换只是工具使用；非允许应用持续出现才是“疑似子分心”。
4. 创建、完成、解除绑定都需要用户明确动作；连续找桌面的过程合并为一次最终工作流切换，普通切换静默，只有 10 分钟内第 3 次已绑定工作流切换才出现一次确认。
5. 识别失败时进入“上下文未知”，不沿用旧工作流，也不猜测。

## macOS Space 身份边界

`NSWorkspace.activeSpaceDidChangeNotification` 能可靠通知 Space 发生变化，但通知不包含 `userInfo`，因此没有公开的 Space ID。

Apple 的公开 AppKit 接口也没有创建、删除、命名或持久标识系统 Space 的 API。
旧版曾使用不可见 `NSPanel` 作为桌面锚点，但窗口归属会在新建或重排 Space
时被系统改变，因此会让绑定移位，不能作为身份来源。

当前本地版动态读取 SkyLight 返回的 managed display spaces：

- 身份键是 `(display UUID, managedSpaceID, space UUID)`，不包含桌面序号；
- Space UUID 可用时优先匹配 UUID，数值 ID 只作为兼容回退；
- 新建、删除或重排其他桌面不会改变原 Space 的身份；
- 多块显示器各自拥有当前 Space，绑定与解析都按显示器 UUID 隔离；
- 菜单栏点击绑定或解除时，使用鼠标点击所在显示器的 `Current Space`；
- 连续 Space 变化保留第一跳之前的工作流，并在最后一次变化稳定 1.2 秒后解析最终 `Current Space`；单个显示器差量优先于可能陈旧的全局 active Space；
- 绑定存在时每秒做一次只读差量兜底，以覆盖 `NSWorkspace` 偶尔漏掉的非全局显示器切换；没有差量时不改变上下文；
- 读取失败时进入 `unknown`，不回退到序号或窗口位置猜测。

相关公开接口：

- [activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification)
- [NSWindow.isOnActiveSpace](https://developer.apple.com/documentation/appkit/nswindow/isonactivespace)（仅用于说明旧方案边界，不再用于绑定身份）

SkyLight 是未公开系统接口，存在系统升级失效和分发风险。实现通过 `dlopen` / `dlsym`
按运行时探测，不静态链接私有框架；当前目标是本地自用的 ad-hoc 签名应用，
不承诺 Mac App Store 兼容性。

### 恢复边界

稳定 Space 身份会随绑定持久化。正常退出、异常退出或系统重启后，只要该身份仍存在，
绑定可以直接恢复，不再依赖窗口 restoration。

恢复顺序：

1. 启动时读取当前全部 managed Space 身份；
2. 持久身份仍存在则恢复为 `verified`；
3. Space 已删除，或绑定来自旧版窗口锚点 / 全局 active 算法，则标记为 `needsRebind`；
4. SkyLight 临时不可用时保留用户绑定，但解析为 `unknown`，不删除、不猜测；
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
  anchorRestorationID       # 仅保留用于旧数据兼容
  displayHint?
  spaceIdentity?            # display UUID + managedSpaceID + Space UUID
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
  -> 保留第一跳之前的工作流
  -> 每次新事件重置 1.2 秒稳定计时
  -> 只解析最后停留的桌面
  -> 比较各显示器 Current Space 的前后差量
     -> 1 个：解析该 Space；有绑定则切换，无绑定则 unbound
     -> 0 个：视为无净变化，不选择其他显示器
     -> 多个：仅用全局 active Space 消歧；仍不唯一则 unknown

```

一段连续导航只保留起点和最终状态；最终回到原工作流则不形成工作流切换。切换时：

1. 闭合旧 WorkflowInterval；
2. 打开新 WorkflowInterval；
3. 重新关联当前前台应用片段；
4. 菜单栏标题无动画地更新；
5. 开启“高频工作流切换确认”、基线已完成且 10 分钟内发生第 3 次已绑定工作流之间的最终切换时，在屏幕中上方显示一次最多 10 秒的待确认状态；前两次静默，确认后冷却 10 分钟；选择离开理由后确认，继续切桌面则保持确认层并重新等待最终目标，超时安全放行；
6. 不要求写恢复线索、不拦截系统手势、不自动完成任何工作流。

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

### 阶段 W2：稳定 Space 身份

- 在单显示器上绑定三个桌面到三个工作流；
- 连续来回切换 30 次，识别正确率 100%，稳定切换延迟小于 1 秒；
- 新增、删除、重排其他桌面后，已有绑定不移位；
- 没有额外可见窗口、Dock 图标或 Mission Control 干扰；
- 无匹配和冲突时绝不沿用旧工作流。

### 阶段 W3：无感交互

- 菜单栏完成新建/绑定/完成/撤销；
- 不拦截桌面手势；只有高频切换段的最终工作流变化才在屏幕中上方显示一次确认；
- 回到有检查点的桌面时恢复线索；
- 时间轴展示工作流轨道和 unknown 区间。

### 阶段 W4：恢复与多显示器

- 验证正常退出、崩溃、重启后的稳定身份恢复；
- 无法可靠恢复时进入 needsRebind；
- 多显示器“独立 Spaces”模式单独验证，未通过前不宣称支持。

只有 W2 的真实桌面切换验收通过后，Space 识别才可替代现有手动任务切换。
