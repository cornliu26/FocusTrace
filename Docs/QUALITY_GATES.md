# FocusTrace 质量门禁

质量门禁的目标不是追求一次性大版本，而是让每一步都在已验证的基线上前进。任何发版都必须证明新增行为有效，同时没有损坏已经交付的能力。

## 变更进入主线前

1. 在产品决策中写清问题、边界、完整流程和成功证据。
2. 把业务规则放在 `FocusTraceCore` 或可独立验证的支持模块，不把关键规则藏在 SwiftUI 点击回调中。
3. 新增聚焦单元测试；修改既有交互时新增回归测试。
4. 性能敏感路径使用固定规模的数据集和显式预算。
5. 更新下面的质量基线；不以删除断言、放宽阈值或改变交互形式来规避失败。
6. 运行 `./Scripts/test.sh`。打包或部署变化还要走对应构建/部署路径。

## 自动化层级

| 层级 | 证明什么 | 执行位置 |
| --- | --- | --- |
| 单元测试 | 纯规则、排序、状态机和迁移行为 | `Tests/FocusTraceCoreTests` |
| 回归验证 | 已发布 UX、隐私、报告和兼容性契约 | `FocusTraceVerification` |
| 性能预算 | 固定工作负载不会越过可感知退化上限 | 单元测试与 `FocusTraceVerification` |
| 持续集成 | 每次主分支推送和 Pull Request 都执行完整测试 | `.github/workflows/ci.yml` |
| 发版验证 | tag 构建前重复测试，再验证打包清单 | `.github/workflows/release.yml` |
| 本机验收 | Space、状态栏、睡眠/唤醒和真实资源占用 | 发版候选版本人工验收 |

完整 Xcode 环境会实际执行 `@Test` 单元测试。只有 Command Line Tools 的机器缺少 `xctest` 运行器，`Scripts/test.sh` 会明确提示这一点：它仍编译全部单元测试，并通过 `FocusTraceVerification` 执行对应的关键行为、隐私、兼容和性能回归，不把编译成功伪装成单测执行成功。

## 当前功能基线

| ID | 已交付契约 | 自动证据 |
| --- | --- | --- |
| CAP-01 | 应用切换闭合前一片段，重复激活不制造片段 | `activationClosesPreviousAndIgnoresDuplicate` |
| CAP-02 | 锁屏、睡眠、唤醒和 loginwindow 不制造虚假活跃时间 | `sleepClosesAndWakeReopens`、`loginWindowIsTreatedAsSystemInactive` |
| FLOW-01 | 菜单栏和主窗口共享唯一主要下一步 | `flowGuidanceAlwaysExposesOnlyTheNextRequiredAction` |
| UX-01 | 时间轴和需求截止日期保持图形日历；时间轴日历一次点击打开、再次点击关闭 | `optimizedDailyUXContractRemainsStable`、`calendarPopoverAnchorPressesAlternateExactlyOnce` |
| UX-02 | 状态栏紧凑、首次使用只有一个必要输入、侧栏图标稳定 | `optimizedDailyUXContractRemainsStable` |
| UX-03 | 时间轴使用 Radix Colors 3.0 官方 token；当天前五分类按顺序着色，其余归入 Slate；文字独立于色块，相邻色块只用系统背景分隔，不为当前工作流添加深色描边 | `timelineSemanticPaletteSeparatesContextToolsAndRisk`、`timelineCurrentWorkflowDoesNotUseDarkSegmentOutlines`、`timelineCategoryColorsFollowRankAndCapAtFive`、`timelineApplicationRunsMergeAdjacentDominantBuckets`、仓库呈现回归 |
| UX-04 | 状态栏、Dock、通知和菜单只复用一个主窗口；不暴露“新建窗口”和冗余设置窗口 | `mainWindowContractRemainsSingleInstance`、仓库场景回归 |
| REQ-01 | 新需求只进入收件箱，不自动绑定、切换或开始工作流 | `requirementCaptureStaysInInboxUntilExplicitlyPlanned` |
| REQ-02 | 截止日期、重要程度和工作流归属彼此独立；旧版模糊安排不推断日期 | `requirementPlanningSeparatesDeadlineImportanceAndWorkflow`、`requirementQueueUsesUrgencyThenImportanceAndPreservesLegacyAmbiguity` |
| REQ-03 | 需求按逾期、今天、未来、无日期排序；到期提醒只发送一次且不在通知中显示需求标题 | `requirementQueueUsesUrgencyThenImportanceAndPreservesLegacyAmbiguity`、`requirementDueReminderIsOneShotAndOnlyForPlannedOpenWork`、仓库隐私回归 |
| REQ-04 | 未完成需求只暴露“处理 / 不处理”两个日常决策；无需先安排日期或重要程度即可开始；同一工作流中的需求独立完成 | `requirementCanStartWithoutPlanningAndCompletesIndependentlyInsideWorkflow`、仓库交互回归 |
| FLOW-02 | 工作流名称按空白、大小写和字符宽度规范化后唯一；列表以整行点击作为唯一选中/绑定动作，仅保留编辑和完成；删除位于编辑页，只解绑未完成需求和桌面并保留历史 | `workflowNamesAreUniqueAfterWhitespaceCaseAndWidthNormalization`、`deletingWorkflowDetachesOnlyItsUnfinishedRequirements`、仓库交互回归 |
| ATT-01 | 提醒必须同时满足会话、基线、非允许应用和时间阈值 | `distractionGateRequiresAllConditions` |
| TRAIN-01 | 初始训练与每五次训练的升降级规则稳定 | `initialDurationUsesDefaultWhenSamplesAreInsufficient`、`fiveSessionProgression` |
| SPACE-01 | Space 未知或冲突时停止归因，不猜测工作流 | `spaceResolutionNeverGuessesWhenUnknownOrConflicted`、`unknownSpaceClosesWorkflowWithoutCarryingAttribution` |
| RETURN-01 | Agent 返回点只按显式状态提醒，聚合指标不读取文字 | `parkingReminderRequiresActiveDueAndUnsentRecord`、`parkingMetricsTrackResumptionWithoutReadingCue` |
| REVIEW-01 | 数据不足或归因不可靠时拒绝生成注意力建议 | `analysisLocksUntilMinimumData`、`dailyCoachRefusesBehaviorAdviceWhenWorkflowAttributionIsLow` |
| REVIEW-02 | Codex 写回先给唯一问题、再给唯一行动；最多两条不重复证据，数据不可靠时只给修复动作，并兼容已生成的 v1 写回 | `codexReviewV2EnforcesADecisionBriefInsteadOfAnEssay`、`codexReviewKeepsLegacyReadCompatibility`、`codexWorkspaceDemandsProblemActionAndNoFiller` |
| REVIEW-03 | 官方聚合脚本可按日期重建历史报告；写回按报告自身时区的日期单独展示，不受运行机器时区影响；参数在预构建与 SwiftPM 路径一致 | `dailyReportScriptPreservesDateArgumentsForHistoricalRegeneration`、`test_report_filename_preserves_the_reports_own_civil_date`、仓库回归 |
| PRIV-01 | Codex 只读取聚合报告，报告不泄露原始活动与返回点文字 | `automationJSONIsStructuredAndAggregateOnly`、`codexWorkspaceMakesTheAggregateOnlyBoundaryDurable` |
| DATA-01 | 旧 store 解码、CSV 转义、JSON 往返保持兼容 | `legacyTaskLifecycleMigrationIsLossless`、`csvQuotesSeparatorsWithoutAddingExtraFields`、`jsonRoundTrip` |
| RELEASE-01 | 版本和构建号按语义顺序比较，更新清单校验完整 | `releaseManifestUsesSemanticVersionAndBuildOrdering` |

## 当前性能基线

预算定义在 `FocusTracePerformanceBudget`，测试不能各自维护不同的魔法数字。

| ID | 工作负载 | 预算 | 自动证据 |
| --- | --- | --- | --- |
| PERF-01 | 连续生成 37 个月份布局 | 小于 1 秒 | `calendarLayoutIsPreparedBeforePresentationAndRemainsBounded` |
| PERF-02 | 聚合 2,000 个活动片段和 300 个标记 | 小于 1 秒 | `timelinePresentationUsesMinuteRefreshAndHandlesLargeDaysQuickly` |
| PERF-03 | 专注计时每秒更新时，时间轴呈现键保持分钟粒度 | 同一分钟不重算 | 同上 |
| PERF-04 | 时间轴昂贵呈现结果按数据版本和分钟缓存 | 数据未变且未跨分钟时复用 | `timelinePresentationCacheInvalidatesOnlyForMeaningfulChanges` |
| PERF-05 | 1,000 个需求完成分区和排序 | 小于 100 毫秒 | `requirementQueueHandlesOneThousandItemsWithinBudget` |

以下属于发版候选版本的本机验收，不能用有噪声的共享 CI 机器冒充精确测量：

- 空闲稳定后 CPU 目标低于 1%；
- 常规工作日数据下内存目标低于 100 MB；
- 打开日历、时间轴和状态栏面板时无可感知卡顿；
- 连续切换 Space、睡眠/唤醒后记录仍正确闭合。

在它们实现稳定、隔离的自动测量前，发版说明必须记录执行环境和实测结果，不能宣称已有自动保证。

## 有意改变既有契约

既有行为可以被改进，但不能悄悄漂移。需要：

1. 新建产品决策记录；
2. 说明旧行为解决了什么，以及为什么现在需要改变；
3. 更新质量基线和对应测试；
4. 给出兼容、迁移和回退方式；
5. 在 Pull Request 中明确标记“有意变更既有契约”。

发现测试与真实体验不一致时，应补强测试覆盖真实问题，而不是把“测试通过”当作体验良好的证明。
