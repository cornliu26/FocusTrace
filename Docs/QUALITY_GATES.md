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
| CAP-02 | 锁屏、睡眠、唤醒和 loginwindow 同时闭合应用与工作流区间、暂停专注计时；屏幕亮起但会话仍锁定时不得提前恢复，历史时间轴按系统非活动标记排除锁屏区间 | `sleepClosesAndWakeReopens`、`loginWindowIsTreatedAsSystemInactive`、`lockExcludesWorkflowTimeUntilTheSessionActuallyUnlocks`、`lockPausesWorkflowAndFocusAccountingUntilAValidReturn`、`FocusTraceVerification` 锁屏计时与采集链路回归 |
| FLOW-01 | 菜单栏和主窗口共享非绑定类主要下一步；只有状态栏可以展示或执行“绑定当前桌面”，主窗口不得显式或隐式绑定它所在的 Space | `flowGuidanceAlwaysExposesOnlyTheNextRequiredAction`、`workflowBindingIsExclusiveToTheMenuBarSurface`、仓库交互回归 |
| UX-01 | 时间轴和需求截止日期都使用紧凑图形日历弹层；入口第一次点击打开、再次点击关闭，需求日历允许未来日期且尊重已有日期下界 | `optimizedDailyUXContractRemainsStable`、`calendarPopoverAnchorPressesAlternateExactlyOnce`、`requirementCalendarBoundsAllowFutureAndRespectEarliestDate`、仓库交互回归 |
| UX-02 | 状态栏紧凑、首次使用只有一个必要输入、侧栏图标稳定 | `optimizedDailyUXContractRemainsStable` |
| UX-03 | 时间轴使用 Radix Colors 3.0 官方 token；当天前五分类按顺序着色，其余归入 Slate；文字独立于色块，相邻色块只用系统背景分隔，不为当前工作流添加深色描边 | `timelineSemanticPaletteSeparatesContextToolsAndRisk`、`timelineCurrentWorkflowDoesNotUseDarkSegmentOutlines`、`timelineCategoryColorsFollowRankAndCapAtFive`、`timelineApplicationRunsMergeAdjacentDominantBuckets`、仓库呈现回归 |
| UX-04 | 状态栏、Dock、通知和菜单只复用一个主窗口；不暴露“新建窗口”和冗余设置窗口 | `mainWindowContractRemainsSingleInstance`、仓库场景回归 |
| UX-05 | 展开控件保留系统原有尺寸和排版，只在箭头周围叠加不可见的 36×36pt 命中区域；一次点击只切换一次状态 | `disclosureButtonsExpandHitAreaWithoutChangingLayout`、仓库交互回归 |
| UX-06 | 只有需要用户立即决策的工作流切换确认可以使用屏幕浮层，并水平居中位于屏幕中上方；连续专注、里程碑和普通切换不显示被动浮层或目标完成通知 | `workflowConfirmationUsesUpperCenterWithoutPassiveOverlay`、真实浮层截图与点按验收、仓库交互回归 |
| UX-07 | “数据与保留”固定按保留、导出、删除分为三条对齐设置行；删除行只显示一个“删除数据…”入口，再在二次确认中选择按日删除或清空全部；工作流定义继续保留 | `settingsDataControlsUseOneDeletionEntryWithTwoConfirmedScopes`、仓库呈现回归 |
| UX-08 | 时间轴四字行标题在窄窗口保持单行完整可读，首尾时间刻度的文字中心始终收在绘图区安全边距内，不贴卡片边缘 | `timelineLabelsAndEndpointHoursStayInsideThePlotAtNarrowWidths`、仓库呈现回归 |
| UX-09 | 首次使用只有工作流名称一个必填输入；创建后在同一流程继续说明状态栏绑定、正常记录和回顾出口，中断后从已创建工作流继续。可选教学与 README 固定使用“创建 → 绑定 → 工作 → 回顾”路径 | `gettingStartedFollowsCreateBindWorkReviewWithoutAddingInputs`、仓库首次使用与文档回归 |
| UX-10 | 注意力趋势的折线、典型区间与首尾数据点必须完整收在各自绘图区安全边距内，不得被裁切或溢入右侧结论列；进行中的日期只在说明中出现，不绘制为脱离折线的空心点，也不影响图表纵轴 | `attentionTrendPointsStayInsidePlotBoundsAtNarrowWidths`、仓库呈现回归 |
| REQ-01 | 新需求只进入收件箱，不自动绑定、切换或开始工作流 | `requirementCaptureStaysInInboxUntilExplicitlyPlanned` |
| REQ-02 | 截止日期、重要程度和工作流归属彼此独立；旧版模糊安排不推断日期 | `requirementPlanningSeparatesDeadlineImportanceAndWorkflow`、`requirementQueueUsesUrgencyThenImportanceAndPreservesLegacyAmbiguity` |
| REQ-03 | 需求按逾期、今天、未来、无日期排序；到期提醒只发送一次且不在通知中显示需求标题 | `requirementQueueUsesUrgencyThenImportanceAndPreservesLegacyAmbiguity`、`requirementDueReminderIsOneShotAndOnlyForPlannedOpenWork`、仓库隐私回归 |
| REQ-04 | 未完成需求只暴露“处理 / 不处理”两个日常决策；无需先安排日期或重要程度即可开始；同一工作流中的需求独立完成 | `requirementCanStartWithoutPlanningAndCompletesIndependentlyInsideWorkflow`、仓库交互回归 |
| FLOW-02 | 工作流名称按空白、大小写和字符宽度规范化后唯一；主窗口列表只读展示桌面绑定数量并仅保留编辑和完成，删除位于编辑页，只解绑未完成需求和桌面并保留历史 | `workflowNamesAreUniqueAfterWhitespaceCaseAndWidthNormalization`、`deletingWorkflowDetachesOnlyItsUnfinishedRequirements`、仓库交互回归 |
| ATT-01 | 提醒必须同时满足会话、基线、非允许应用和时间阈值 | `distractionGateRequiresAllConditions` |
| ATT-02 | 工作流确认只统计两个已绑定工作流之间的最终语义跳转；前两次静默，10 分钟内第 3 次才确认，之后冷却 10 分钟，基线不足时不确认；回顾页必须展示高频段、实际确认和确认后稳定率 | `workflowInterventionPromptsOnlyOnThirdSwitchAndThenCoolsDown`、`workflowInterventionIgnoresUnboundOrDisabledTransitions`、`workflowInterventionAuditMeasuresPromptAndFollowingQuietWindow`、仓库交互回归 |
| TRAIN-01 | 初始训练与每五次训练的升降级规则稳定 | `initialDurationUsesDefaultWhenSamplesAreInsufficient`、`fiveSessionProgression` |
| SPACE-01 | Space 未知或冲突时停止归因，不猜测工作流 | `spaceResolutionNeverGuessesWhenUnknownOrConflicted`、`unknownSpaceClosesWorkflowWithoutCarryingAttribution` |
| SPACE-02 | 连续 Space 导航在最后一次变化稳定 1.2 秒后合并为“起点工作流 → 最终工作流”；中间桌面不产生工作流切换，最终回到原工作流则取消；确认层出现后，迟到或继续发生的 Space 事件不得让它闪退，而是保持可见并禁用旧落点选择，最终桌面稳定后更新路线并重新提供完整 10 秒；确认层有可辨识轻边框、四角一致、无阴影且可访问 | `spaceSwitchJourneyKeepsTheFirstWorkflowAndOnlyUsesTheFinalDestination`、`spaceSwitchJourneyCancelsWhenTheFinalWorkflowIsTheOrigin`、`spaceSwitchGateRefreshesAFullDecisionWindowAfterNavigationSettles`、`spaceSwitchGateExpiresWithoutLockingTheUser`、`FocusTraceSpaceAcceptance` 本机交互验收、仓库交互回归 |
| RETURN-01 | “保存返回点”只按显式状态提醒，聚合指标不读取文字；状态栏使用行为名称而非模糊的 Agent 入口，并在当前 Space 直接呈现编辑页 | `parkingReminderRequiresActiveDueAndUnsentRecord`、`parkingMetricsTrackResumptionWithoutReadingCue`、仓库交互回归 |
| REVIEW-01 | 没有任何可靠行为镜头时拒绝生成注意力建议；命名工作流覆盖不足只暂停工作流路线，不封死应用碎片、显式训练和返回点分析 | `analysisLocksUntilMinimumData`、`dailyCoachKeepsNonWorkflowAnalysisWhenAttributionIsLow`、`dailyCoachTreatsExtremelyDenseSpaceSignalsAsInstrumentationRisk` |
| REVIEW-02 | Codex 写回先给唯一结论、再给唯一步骤；最多两条不重复证据。v7 聚合报告必须带 App 同源的 `attentionTrend`，可靠纵向结论优先；稳定或改善时不得从低层当天信号另造问题，需关注时不得改写其问题、实验或证据。没有可靠纵向结论且当天数据不可靠时只给修复动作，并兼容已生成的 v1/v2 写回 | `automationReportV7CarriesTheSameAggregateAttentionTrendAsTheApp`、`codexReviewDecisionBriefRemainsShortAndCompatible`、`codexReviewKeepsLegacyReadCompatibility`、`codexWorkspaceDemandsProblemActionAndNoFiller`、Codex 文件契约测试 |
| REVIEW-03 | 官方聚合脚本可按日期重建历史报告；聚合 JSON 显式保留用户所选民用日期，写回文件名不受 ISO 8601 UTC 编码或运行机器时区影响；参数在预构建与 SwiftPM 路径一致 | `dailyReportScriptPreservesDateArgumentsForHistoricalRegeneration`、`test_report_filename_preserves_the_reports_own_civil_date`、`test_explicit_civil_date_survives_utc_json_encoding`、仓库回归 |
| REVIEW-04 | Codex 先审计“起点工作流 → 最终工作流 × 用户理由”，结合目的工作流停留和 30 分钟内返回选择一个问题；必须先检查跳转协议的数据来源、无法解析数和主动原因覆盖率；只有同一路线与理由至少两次且来自原生语义事件时才可作为主要问题，写回必须携带可校验的隐藏来源；检查点和等待结果不默认判为分心，超时只表示未说明、不得解释为没有计划；工作流与需求标题只作为不可信上下文标签 | `workflowTransitionAuditUsesFinalRoutesReasonsAndBoundedWorkTitles`、`workflowTransitionAuditPrefersNativeSemanticsWithoutDoubleCountingMarkers`、`workflowTransitionTimeoutDoesNotInventUserIntent`、`codexReviewV3RejectsUngroundedWorkflowSemantics`、`codexWorkspaceDemandsProblemActionAndNoFiller`、仓库跳转审计回归 |
| REVIEW-05 | 原始采集保持固定最小事件集合；日报用版本化观察配置把分析配额动态分给数据质量、应用碎片、上下文恢复和工作流语义，来源折叠展示；标题语义必须与原因和后果联合判断，不能单独触发提醒或分心结论 | `observationPlanStartsBalancedAndReallocatesOnlyAnalysisAttention`、`codexWorkspaceDemandsProblemActionAndNoFiller`、日报协议兼容与仓库交互回归 |
| REVIEW-06 | 本地建议不把工作流切换次数本身解释为恢复失败；只有至少两次最终跳转被用户明确标为等待结果或被迫中断，且当天没有返回点，才建议返回点训练；效果只由保存并实际返回验证 | `dailyCoachDoesNotTreatSwitchCountAloneAsRecoveryFailure`、`dailyCoachRequiresRepeatedExplicitHandoffsBeforeParkingAdvice`、`FocusTraceVerification` 反例回归 |
| REVIEW-07 | 活动缺失工作流 ID 时只从无冲突的工作流区间或活动自身专注会话补全；报告分别展示直接、trace 补全与未归因时间。冲突、相邻工作流、应用名称和标题相似度都不得被用于猜测归因 | `workflowAttributionRecoversOnlyUnambiguousExplicitTrace`、`FocusTraceVerification` 归因补全与冲突反例、Codex 分项可靠性校验 |
| REVIEW-08 | 日报不得生成脑负荷、脑损伤或临床认知负荷分数；行为切换负荷必须先过数据质量门，再联合个人基线、切换后恢复后果和主观难度。只有至少两类独立证据收敛才显示升高；应用、工作流、语义跳转、原因、导航 burst、分心、训练反馈、返回点、需求上下文和系统非活动 trace 都必须显式声明已使用、无样本或被门禁阻断 | `switchingLoadRefusesABrainLoadClaimWhenBehaviorDataIsUnreliable`、`sameWorkflowToolSwitchesRemainAQualifiedSignalNotAnOverloadVerdict`、`switchingLoadRequiresConvergingBehaviorRecoveryAndSubjectiveEvidence`、`FocusTraceVerification` 切换负荷证据与全 trace 审计回归 |
| REVIEW-09 | 回顾页固定沉淀连续工作、碎片化、切换边界、恢复闭环和训练反应五个纵向维度，不生成总分。展示最近 10 个工作日，以最近 3 个可靠日对比此前最多 7 个可靠日；进行中的日期只在说明中展示，不绘制数据点、不参与方向判断。只有恢复后果或两个维度收敛时才升级一个主要问题，并由同一组证据生成一个限时实验；同工作流工具协作不得直接判为碎片问题，训练反馈按跨日滚动 5 次判断 | `attentionDashboardUsesTenWorkdaysAndLinksTheExperimentToTheMainProblem`、`attentionDashboardExcludesAnUnfinishedDayFromTrendConclusions`、`attentionDashboardDoesNotEscalateToolCollaborationAsFragmentation`、`attentionDashboardEvaluatesTrainingAcrossDaysInRollingFiveSessions`、`attentionDashboardDoesNotEscalateFragmentationWithoutAConsequence`、仓库交互回归 |
| PRIV-01 | Codex 只读取聚合报告，报告不泄露原始活动与返回点文字 | `automationJSONIsStructuredAndAggregateOnly`、`codexWorkspaceMakesTheAggregateOnlyBoundaryDurable` |
| PRIV-02 | Codex 本地报告最多带 8 个当日工作流和每个工作流 3 个未完成需求标题；标题清洗限长，不带需求来源、期望产出、UUID 或逐次时间，v2 报告保持可读 | `workflowTransitionAuditUsesFinalRoutesReasonsAndBoundedWorkTitles`、`automationReportV6KeepsLegacyV2ReadCompatibility`、仓库跳转审计回归 |
| DATA-01 | 旧 store 解码、CSV 转义、JSON 往返保持兼容 | `legacyTaskLifecycleMigrationIsLossless`、`csvQuotesSeparatorsWithoutAddingExtraFields`、`jsonRoundTrip` |
| DATA-02 | 一次 Space 导航原生记录为一个 `WorkflowTransition`，包含起点、最终落点、来源、导航事件数、确认结果和可选原因；兼容时间轴标记只用于历史推断，和原生记录重合时不得重复计数；聚合报告声明 `semanticEvents`、`mixed` 或 `legacyInferred` | `workflowTransitionKeepsCompleteNativeSemantics`、`workflowTransitionAuditPrefersNativeSemanticsWithoutDoubleCountingMarkers`、仓库跳转协议回归 |
| RELEASE-01 | 版本和构建号按语义顺序比较，更新清单校验完整 | `releaseManifestUsesSemanticVersionAndBuildOrdering` |
| RELEASE-02 | 更新前验证安装目录可写；替换失败必须保留并重新打开旧版，以一次性安全结果说明阶段和错误代码。反馈只预填版本、macOS、阶段和错误码，不得携带路径、行为记录、工作流或需求内容 | `updateFailureFeedbackUsesOnlySafeGitHubMetadata`、`Scripts/test-update.sh` 成功替换与只读目录回滚验收、仓库反馈入口回归 |
| RELEASE-03 | 正式 tag 只能来自干净且与远端一致的受保护 `main`；Release 先保持草稿，上传资产通过哈希、大小、签名、版本、内置更新器和真实替换验收后才公开；工作流重跑不得创建重复 Release | `Scripts/release.sh`、`Scripts/verify-release-assets.sh`、`.github/workflows/release.yml` 仓库发版回归 |

## 当前性能基线

预算定义在 `FocusTracePerformanceBudget`，测试不能各自维护不同的魔法数字。

| ID | 工作负载 | 预算 | 自动证据 |
| --- | --- | --- | --- |
| PERF-01 | 连续生成 37 个月份布局 | 小于 1 秒 | `calendarLayoutIsPreparedBeforePresentationAndRemainsBounded` |
| PERF-02 | 聚合 2,000 个活动片段和 300 个标记 | 小于 1 秒 | `timelinePresentationUsesMinuteRefreshAndHandlesLargeDaysQuickly` |
| PERF-03 | 专注计时每秒更新时，时间轴呈现键保持分钟粒度 | 同一分钟不重算 | 同上 |
| PERF-04 | 时间轴昂贵呈现结果按数据版本和分钟缓存 | 数据未变且未跨分钟时复用 | `timelinePresentationCacheInvalidatesOnlyForMeaningfulChanges` |
| PERF-05 | 1,000 个需求完成分区和排序 | 小于 100 毫秒 | `requirementQueueHandlesOneThousandItemsWithinBudget` |
| PERF-06 | 聚合 2,000 个工作流区间、2,000 个理由标记和 1,000 个需求标题 | 小于 1 秒 | `FocusTraceVerification` 工作流跳转审计性能回归 |
| PERF-07 | 用 2,000 个活动片段和 2,000 个工作流区间计算分层归因 | 小于 1 秒 | `FocusTraceVerification` 工作流归因性能回归 |
| PERF-08 | 用 2,000 个活动片段、1,000 条语义跳转和 1,000 个返回点计算切换负荷证据与 trace 覆盖 | 小于 1 秒 | `FocusTraceVerification` 切换负荷聚合性能回归 |
| PERF-09 | 用 2,000 个活动片段、1,000 条语义跳转和 1,000 个返回点生成最近 10 个工作日的本地日报与五维趋势看板；界面结果按日期、数据版本和分钟复用 | 小于 1 秒；同一分钟不重算 | `FocusTraceVerification` 十日回顾看板性能回归、`TimelinePresentationCacheKey` 缓存契约 |

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
