# FocusTrace 工作流跳转协议

## 目标

分析单位不是一次 macOS 通知，也不是经过的每个桌面，而是一次完整导航：

`已验证起点 → 连续 Space 导航 → 最终稳定落点 → 用户原因或系统结果`

这个单位只用于回答三个与专注和效率直接相关的问题：

1. 哪些工作流之间的跳转反复打断当前产出；
2. 哪些跳转是健康交接，哪些缺少明确目的或恢复动作；
3. 改变一个交接动作后，目的工作流停留和返回结果是否改善。

FocusTrace 不从跳转次数诊断注意力，也不把等待 Agent、到达检查点或必要工具切换默认判为分心。

## 本地原生记录

快照中的 `workflowTransitions` 每项是一条 `WorkflowTransition`：

| 字段 | 语义 |
| --- | --- |
| `id` | 本地去重标识；不进入 LLM 报告 |
| `sourceRaw` | `space` 或 `manual`；首版原生原因只覆盖 `space` |
| `navigationStartedAt` | 第一次导航事件 |
| `settledAt` | 最终桌面第一次稳定 |
| `resolvedAt` | 用户确认、超时、取消或识别失败 |
| `originKindRaw` / `originWorkflowID` | 起点类型及可选本地工作流引用 |
| `destinationKindRaw` / `destinationWorkflowID` | 最终落点类型及可选本地工作流引用 |
| `outcomeRaw` | `confirmed`、`timedOut`、`cancelled`、`automatic` 或 `unresolved` |
| `reasonRaw` | `reachedCheckpoint`、`waitingForResult`、`forcedInterruption`、`unstructured` 或空 |
| `interventionTriggerRaw` | `frequentSwitchBurst` 或空；只说明为何请求确认，不是分心结论 |
| `navigationEventCount` | 此次连续导航合并了多少个 Space 事件 |

端点类型固定为 `workflow`、`unbound`、`unknown`、`conflict`。冲突候选 ID 不写入跳转记录，避免错误归因和不必要的数据扩散。

结果规则：

- 用户选择三个短理由之一：`confirmed`；
- 完整决策窗口未选择：`timedOut + unstructured`；
- 最终回到起点：`cancelled`，不算工作流切换；
- 切换门未启用但最终落点可验证：`automatic`；
- 最终身份未知或冲突：`unresolved`，不能用于行为结论。

确认策略只使用上述原生语义跳转：前三个基线工作日不确认；两个已绑定工作流之间在 10 分钟内的第 3 次最终切换才确认一次；确认后冷却 10 分钟。普通切换、未绑定端点和中间 Space 不触发。

`TimelineMarker` 继续承担时间轴展示与旧数据兼容，但不再是新数据的主要语义来源。

## 给 Codex / LLM 的聚合协议

`Reports/latest.json` 的报告协议为 `schemaVersion: 5`，并以
`reportCivilDate` 显式保留用户选择的 `yyyy-MM-dd` 日期，避免 UTC 编码
跨日。它不会输出原生逐条跳转，而只输出：

- `workflowContexts`：最多 8 个工作流的有界标题、归因分钟和最多 3 个未完成需求标题；
- `transitionAudit.protocolVersion`：当前为 `2`；
- `transitionAudit.dataSource`：
  - `semanticEvents`：原生完整跳转；
  - `mixed`：原生跳转与历史推断并存；
  - `legacyInferred`：落点由旧标记附近的工作流区间推断；
  - `none`：没有可分析跳转；
- `finalSwitches`、`explicitReasonSwitches`、`timedOutSwitches`、
  `automaticSwitches`、`cancelledNavigations`、`unresolvedNavigations`；
- `explicitReasonCoverage`：主动说明原因的最终跳转占比；
- `frequentSwitchEpisodes`、`interventionPrompts`、`assessedInterventionPrompts`、`postPromptQuietRate`：高频切换段、实际确认、完整观察窗和确认后 10 分钟稳定率；
- `routes`：有界的起点—落点聚合，含原因、结果、时段、目的工作流停留中位数和 30 分钟内返回数。
- `observationPlan`：固定采集边界、四类分析配额、当天与近 7 日来源，以及保守的提醒策略建议。

原生跳转和两秒内的兼容标记只计一次。报告不包含 UUID、逐事件时间戳、原始应用行、Bundle ID、窗口标题、URL、输入内容、需求来源或返回点文字。
`timedOut + unstructured` 在报告中只显示为“超时 / 未说明”，不能解释成用户没有计划或发生了分心。

`observationPlan.allocations` 是分析精力分配，不是原始事件抽样率。FocusTrace 不会因为某天的复盘结论而少记一类应用事件，或自动扩大到窗口标题、URL、输入内容等敏感数据。

## LLM 决策顺序

1. 先检查 `dataQuality.isReliableForBehavior`；
2. 再检查 `dataSource`、`unresolvedNavigations`、
   `explicitReasonCoverage` 和干预效果，决定证据是否足以解释跳转以及确认是否值得继续；
3. 只选择一条同时具备路线、原因和后果证据的问题；
4. 一次只改变一个交接动作，并在下一工作日检查同一路线的同一指标。

数据不足时修复记录质量，不猜测注意力。任何建议都不得自动修改训练计划、允许应用、通知或工作流绑定。
