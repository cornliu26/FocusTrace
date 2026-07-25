<p align="center">
  <img src="./Assets/FocusTraceIcon.png" width="104" alt="FocusTrace">
</p>

<h1 align="center">FocusTrace</h1>

<p align="center">
  <strong>把切屏变成轨迹，把多任务重新变成有边界的工作。</strong>
</p>

<p align="center">
  一款本地运行的 macOS 专注记录与训练工具。<br>
  它理解合理的工具切换，也把真正的工作流切换交还给你。
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
| **2 · 绑定当前桌面** | 一个 macOS Space 对应一个工作流；以后切桌面就会自动恢复工作上下文。 |
| **3 · 正常工作** | 不用一直盯着 FocusTrace。应用切换会自动形成轨迹，但不会被武断地判定为分心。 |
| **4 · 下班再回顾** | 在时间轴看今天如何切换，在回顾分析里决定明天只调整哪一件事。 |

> [!TIP]
> 突然收到一个新需求时，先在菜单栏点“收下一个需求”。它不会打断或切换当前工作流。

## 重要特性

| | |
| --- | --- |
| **🌿 清晰的时间轴**<br><sub>按工作流、应用和切换密度还原一天，不读取窗口标题或网页内容。</sub> | **🖥️ Space 就是工作流**<br><sub>桌面切换即上下文切换，不必每次重新选择正在做什么。</sub> |
| **📥 需求箱**<br><sub>先收下口头需求，再安排到今天、本周或以后；只有“开始处理”才会切换工作流。</sub> | **🎯 专注训练**<br><sub>先观察个人基线，再渐进调整训练时长；合理的工具切换不会导致失败。</sub> |
| **🧭 温和的专注护栏**<br><sub>短暂切屏只记录，稳定且频繁地切换工作流时才提醒。</sub> | **🔒 数据只在本机**<br><sub>无需账号，不上传行为数据，也不读取输入内容、聊天对象或手机行为。</sub> |

## 高级特性

### Agent 返回点

等待 Agent、构建或测试时，保存“回来后第一步”再切走。回到这个桌面时，FocusTrace 会把下一步重新放到眼前，减少重新进入上下文的成本。

### 针对个人的训练调整

积累至少 **10 个工作日和 20 次训练** 后，FocusTrace 才会进入阶段 2。它每周最多建议一项变化，并说明证据；任何训练计划调整都需要你确认。

### Codex 每日回顾

在“回顾分析”中点击“在 Codex 中接入每日复盘”，即可建立本地聚合报告与 Codex 定时任务之间的连接，不需要 API key。

<details>
<summary><strong>Codex 会看到什么？</strong></summary>

Codex 只读取 FocusTrace 生成的聚合指标，例如每小时切换次数、连续专注时长和训练完成率。它不会收到原始活动行、Bundle ID、窗口标题、URL、输入内容或 Agent 返回点文字。

连接流程会打开 Codex 并预填设置说明，最后一次发送仍由你确认。即使不接入 Codex，时间轴、本地分析和训练也会正常工作。

</details>

## 隐私边界

- 只记录前台应用、起止时间、工作流标签和训练反馈。
- 不读取窗口标题、网页地址、聊天对象、键盘内容或手机行为。
- 不需要辅助功能、屏幕录制或输入监控权限。
- 需求文字和 Agent 返回点仅保存在本机，不进入聚合日报。
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

欢迎提交 issue 和 pull request。开始前请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)，不要提交真实活动数据或本地生成的报告。

</details>

## 说明

FocusTrace 是工作行为记录与专注习惯训练工具，不诊断或治疗 ADHD。如果注意力问题持续在多个场景造成明显影响，请寻求具备资质的专业评估。

---

<p align="center">
  <sub>Local-first · Explainable · User-controlled</sub>
</p>
