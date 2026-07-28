<p align="center">
  <img src="./Docs/Media/Posters/focustrace-product-github.png" alt="FocusTrace：看清切换，不丢上下文">
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-supported-0F766E?style=flat-square">
  <img alt="Local first" src="https://img.shields.io/badge/data-local--first-10B981?style=flat-square">
</p>

<p align="center">
  <a href="https://github.com/cornliu26/FocusTrace/releases/latest"><strong>下载 FocusTrace</strong></a>
  ·
  <a href="#30-秒上手">快速上手</a>
  ·
  <a href="#重要特性">重要特性</a>
  ·
  <a href="#高级特性">高级特性</a>
</p>

---

## 安装

> [!IMPORTANT]
> 当前版本支持 **macOS 14 或更高版本**，以及 **Apple Silicon Mac**。

1. 打开 [最新版本下载页](https://github.com/cornliu26/FocusTrace/releases/latest)。
2. 下载 `FocusTrace-macOS-arm64.zip` 并解压。
3. 将 `FocusTrace.app` 拖进“应用程序”文件夹。
4. 第一次启动时，如果 macOS 提示无法验证开发者，请右键应用并选择“打开”。

安装或重新安装都不会删除已有的工作轨迹和偏好。

<details>
<summary><strong>从源码一键安装</strong></summary>

需要 Swift 6 Command Line Tools：

```bash
git clone https://github.com/cornliu26/FocusTrace.git
cd FocusTrace
./Scripts/deploy-mac.sh
```

也可以在 Finder 中双击 `Deploy-FocusTrace.command`。

</details>

## 30 秒上手

| | 你要做什么 |
| --- | --- |
| **1 · 命名当前工作流** | 第一次打开只需要输入当前正在做的事情，例如“排查登录问题”。 |
| **2 · 自动绑定当前桌面** | 创建后，当前 macOS Space 会自动绑定到这个工作流；以后切桌面就会恢复对应上下文。 |
| **3 · 正常工作** | 不用一直盯着 FocusTrace。应用切换会自动形成轨迹，但不会被武断地判定为分心。 |
| **4 · 下班再回顾** | 在时间轴看今天如何切换，在回顾分析里决定明天只调整哪一件事。 |

> [!TIP]
> 突然收到一个新需求时，先在菜单栏点“收下一个需求”。它不会打断或切换当前工作流。

## 重要特性

<p align="center">
  <img src="./Docs/Media/Posters/focustrace-features-github.png" alt="FocusTrace 核心能力：看见碎片、接住需求、用证据改进">
</p>

| 日常最痛的事 | FocusTrace 怎样处理 |
| --- | --- |
| **忙了一天，却不知道是在推进还是只是在切屏** | **看清**：时间轴区分工具切换与工作流切换，只记录事实，不凭一次切屏判断分心。 |
| **Agent 等待、消息和口头需求插入后，原来的工作回不去** | **不丢**：需求先进入收件箱，准备做时只需选择处理或不处理；多条需求可以归入同一工作流，Space 与返回点保留原来的工作上下文。 |
| **知道注意力变差，却不知道怎样改善才适合自己** | **改善**：先建立个人基线，再一次调整一个训练变量，用后续数据验证是否有效。 |

所有数据默认只在本机。FocusTrace 不读取窗口标题、网页内容、输入内容、聊天对象或手机行为。

## 高级特性

### Agent 返回点

等待 Agent、构建或测试时，保存“回来后第一步”再切走。回到这个桌面时，FocusTrace 会把下一步重新放到眼前，减少重新进入上下文的成本。

### 需求箱

临时需求先“收下”，不会自动创建、绑定或切换工作流。准备做时点击“处理”，它会进入已归属或当前工作流；没有明确上下文时才询问一次工作流。截止日期和重要程度可以在详情里补，多条需求可以归入同一工作流，完成其中一条不会结束工作流。

### 针对个人的训练调整

积累至少 **10 个工作日和 20 次训练** 后，FocusTrace 才会进入阶段 2。它每周最多建议一项变化，并说明证据；任何训练计划调整都需要你确认。

### Codex 每日行动复盘

在“回顾分析”中点击“在 Codex 中接入每日复盘”，即可建立本地聚合报告与 Codex 定时任务之间的连接，不需要 API key。

每天的写回只回答三件事：

1. **当前问题**：今天最值得处理的唯一阻塞；
2. **今天怎么做**：一个可以立即执行的动作；
3. **如何验收**：下一次检查的指标和目标。

选择过去的日期，也可以重新查看已经写回的历史复盘。

<details>
<summary><strong>Codex 会看到什么？</strong></summary>

Codex 只读取 FocusTrace 生成的本地聚合报告。除了每小时切换次数、连续专注时长和训练完成率，报告还会按“起点工作流 → 最终工作流 × 切换原因”汇总路线，并附上有界的工作流与未完成需求标题，帮助 Codex 分清计划性交接和真正需要改善的跳转。

标题只作为上下文标签，每个工作流最多带三个需求标题；报告不会包含需求来源、期望产出、UUID、逐次切换时间、原始活动行、Bundle ID、窗口标题、URL、输入内容或 Agent 返回点文字。

数据不足或工作流归因不可靠时，Codex 只能指出一个数据问题和修复动作，不能据此评价注意力。写回还会拒绝重复证据、空泛总结和无关的阶段解锁进度。

连接流程会打开 Codex 并预填设置说明，最后一次发送仍由你确认。即使不接入 Codex，时间轴、本地分析和训练也会正常工作。

</details>

## 隐私边界

- 只记录前台应用、起止时间、工作流标签和训练反馈。
- 不读取窗口标题、网页地址、聊天对象、键盘内容或手机行为。
- 不需要辅助功能、屏幕录制或输入监控权限。
- 需求来源、期望产出和 Agent 返回点仅保存在本机；聚合日报最多只带每个工作流三个未完成需求标题作为上下文标签。
- 不自动修改训练计划、允许应用、系统通知或其他偏好。

<details>
<summary><strong>本地数据与技术边界</strong></summary>

数据保存在：

```text
~/Library/Application Support/FocusTrace/store.json
```

macOS 没有公开稳定的 Space ID。FocusTrace 读取系统的 Space 身份，但不读取窗口内容；无法可靠识别时会停止归因，而不是猜测当前工作流。

更完整的设计说明见 [WORKFLOW_SPACES_DESIGN.md](./Docs/WORKFLOW_SPACES_DESIGN.md)。

</details>

<details>
<summary><strong>开发、测试与贡献</strong></summary>

```bash
./Scripts/test.sh
./Scripts/build-app.sh
./Scripts/run-space-acceptance.sh
```

- `FocusTraceCore`：行为模型、训练与分析规则。
- `FocusTraceMacSupport`：Space 身份与工作流绑定。
- `FocusTrace`：macOS 菜单栏应用与本地界面。

欢迎提交 issue 和 pull request。开始前请阅读 [产品纲领](./Docs/PRODUCT_DOCTRINE.md)、[质量门禁](./Docs/QUALITY_GATES.md) 和 [CONTRIBUTING.md](./CONTRIBUTING.md)，不要提交真实活动数据或本地生成的报告。

</details>

## 说明

FocusTrace 是工作行为记录与专注习惯训练工具，不诊断或治疗 ADHD。如果注意力问题持续在多个场景造成明显影响，请寻求具备资质的专业评估。

---

<p align="center">
  <sub>Local-first · Explainable · User-controlled</sub>
</p>
