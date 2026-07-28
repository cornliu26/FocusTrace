import SwiftUI
import FocusTraceCore

struct RequirementsView: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCapture = false
    @State private var requirementToConvert: RequirementItemModel?
    @State private var requirementToPlan: RequirementItemModel?
    @State private var requirementToChooseWorkflow: RequirementItemModel?
    @State private var requirementToDecline: RequirementItemModel?
    @State private var showCompleted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if openRequirements.isEmpty {
                    ContentUnavailableView {
                        Label("还没有待处理需求", systemImage: "tray")
                    } description: {
                        Text("别人临时提到的事情先收下来；不用马上创建或切换工作流。")
                    } actions: {
                        Button("收下第一个需求") { showingCapture = true }
                            .buttonStyle(FocusTracePrimaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    requirementSection(
                        title: "正在处理",
                        subtitle: "同一时刻只保留一个当前工作项",
                        requirements: requirements(in: .active)
                    )
                    requirementSection(
                        title: "已逾期",
                        subtitle: "已经超过你确认的截止日期",
                        requirements: requirements(in: .overdue)
                    )
                    requirementSection(
                        title: "今天",
                        subtitle: "今天需要完成",
                        requirements: requirements(in: .dueToday)
                    )
                    requirementSection(
                        title: "待决定",
                        subtitle: "处理，或明确不处理",
                        requirements: requirements(in: .needsPlanning)
                    )
                    requirementSection(
                        title: "接下来",
                        subtitle: "未来有明确截止日期",
                        requirements: requirements(in: .upcoming)
                    )
                    requirementSection(
                        title: "无截止日期",
                        subtitle: "已经整理，但没有时间承诺",
                        requirements: requirements(in: .unscheduled)
                    )
                }

                if !completedRequirements.isEmpty {
                    DisclosureGroup(
                        "已完成（\(completedRequirements.count)）",
                        isExpanded: $showCompleted
                    ) {
                        VStack(spacing: 10) {
                            ForEach(completedRequirements) { requirement in
                                RequirementCard(
                                    state: state,
                                    requirement: requirement,
                                    onPlan: {
                                        requirementToPlan = requirement
                                    },
                                    onCreateWorkflow: {
                                        requirementToConvert = requirement
                                    },
                                    onProcess: {
                                        process(requirement)
                                    },
                                    onDecline: {
                                        requirementToDecline = requirement
                                    }
                                )
                            }
                        }
                        .padding(.top, 10)
                    }
                    .focusTraceDisclosureHitTarget(isExpanded: $showCompleted)
                    .padding(14)
                    .background(
                        FocusTraceTheme.cardFill(colorScheme),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
            }
            .focusTracePageContent()
        }
        .focusTraceScreen()
        .sheet(isPresented: $showingCapture) {
            QuickRequirementCaptureSheet(state: state)
        }
        .sheet(item: $requirementToConvert) { requirement in
            RequirementConversionSheet(
                state: state,
                requirement: requirement
            )
        }
        .sheet(item: $requirementToPlan) { requirement in
            RequirementPlanningSheet(state: state, requirement: requirement)
        }
        .sheet(item: $requirementToChooseWorkflow) { requirement in
            RequirementWorkflowSelectionSheet(
                state: state,
                requirement: requirement
            )
        }
        .confirmationDialog(
            "不处理这条需求？",
            isPresented: Binding(
                get: { requirementToDecline != nil },
                set: { if !$0 { requirementToDecline = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let requirementToDecline {
                Button("不处理“\(requirementToDecline.title)”", role: .destructive) {
                    state.archiveRequirement(requirementToDecline.id)
                    self.requirementToDecline = nil
                }
                Button("取消", role: .cancel) {
                    self.requirementToDecline = nil
                }
            }
        } message: {
            Text("它会离开需求箱，但不会完成或删除所属工作流。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FocusTraceTheme.sky.opacity(0.13))
                Image(systemName: "tray.and.arrow.down")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FocusTraceTheme.sky)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text("需求箱")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("先收下；准备做时点“处理”，时间和归属可以在详情里补。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("收下需求", systemImage: "plus") {
                showingCapture = true
            }
            .buttonStyle(FocusTracePrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private func requirementSection(
        title: String,
        subtitle: String,
        requirements: [RequirementItemModel]
    ) -> some View {
        if !requirements.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(requirements.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(requirements) { requirement in
                    RequirementCard(
                        state: state,
                        requirement: requirement,
                        onPlan: {
                            requirementToPlan = requirement
                        },
                        onCreateWorkflow: {
                            requirementToConvert = requirement
                        },
                        onProcess: {
                            process(requirement)
                        },
                        onDecline: {
                            requirementToDecline = requirement
                        }
                    )
                }
            }
        }
    }

    private var openRequirements: [RequirementItemModel] {
        state.orderedRequirements.filter {
            ![RequirementStatus.completed, .archived].contains($0.status)
        }
    }

    private var completedRequirements: [RequirementItemModel] {
        state.orderedRequirements.filter { $0.status == .completed }
    }

    private func requirements(
        in section: RequirementQueueSection
    ) -> [RequirementItemModel] {
        openRequirements.filter {
            RequirementEngine.queueSection(
                for: $0.record,
                at: state.now
            ) == section
        }
    }

    private func process(_ requirement: RequirementItemModel) {
        let activeWorkflowIDs = Set(state.activeTasks.map(\.id))
        if let workflowID = requirement.workflowID,
           activeWorkflowIDs.contains(workflowID) {
            state.startRequirement(requirement.id, in: workflowID)
        } else if let currentWorkflowID = state.currentTaskID,
                  activeWorkflowIDs.contains(currentWorkflowID) {
            state.startRequirement(requirement.id, in: currentWorkflowID)
        } else if state.activeTasks.count == 1,
                  let onlyWorkflowID = state.activeTasks.first?.id {
            state.startRequirement(requirement.id, in: onlyWorkflowID)
        } else {
            requirementToChooseWorkflow = requirement
        }
    }
}

private struct RequirementWorkflowSelectionSheet: View {
    @ObservedObject var state: ApplicationState
    let requirement: RequirementItemModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingWorkflowCreator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("在哪个工作流处理？")
                    .font(.title2.bold())
                Text("一个工作流可以承接多条需求；这里只选择上下文，不要求先排日期。")
                    .foregroundStyle(.secondary)
            }

            Text(requirement.title)
                .font(.callout.weight(.medium))
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    FocusTraceTheme.sky.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            if state.activeTasks.isEmpty {
                ContentUnavailableView(
                    "还没有工作流",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("创建一个工作流后，这条需求会直接进入处理状态。")
                )
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                VStack(spacing: 0) {
                    ForEach(state.activeTasks) { workflow in
                        Button {
                            if state.startRequirement(
                                requirement.id,
                                in: workflow.id
                            ) {
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.on.rectangle")
                                    .foregroundStyle(FocusTraceTheme.sky)
                                Text(workflow.title)
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if workflow.id != state.activeTasks.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("新建工作流来处理", systemImage: "plus") {
                    showingWorkflowCreator = true
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 500)
        .focusTraceScreen()
        .focusTraceVisualSystem()
        .sheet(isPresented: $showingWorkflowCreator) {
            RequirementConversionSheet(
                state: state,
                requirement: requirement,
                startAfterCreation: true,
                onCreated: {
                    dismiss()
                }
            )
        }
    }
}

private struct RequirementCard: View {
    @ObservedObject var state: ApplicationState
    let requirement: RequirementItemModel
    let onPlan: () -> Void
    let onCreateWorkflow: () -> Void
    let onProcess: () -> Void
    let onDecline: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusMark
            VStack(alignment: .leading, spacing: 6) {
                Text(requirement.title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(requirement.capturedAt, style: .relative)
                    if !requirement.source.isEmpty {
                        Text("来自 \(requirement.source)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    deadlineLabel
                    importanceLabel
                    if let workflowID = requirement.workflowID {
                        Label(
                            state.taskName(for: workflowID),
                            systemImage: "rectangle.on.rectangle"
                        )
                    } else {
                        Label("未指定工作流", systemImage: "rectangle.dashed")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)

                if requirement.priority != .unplanned {
                    Label(
                        "旧版安排“\(requirement.priority.legacyTitle)”需要重新确认截止日期",
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(FocusTraceTheme.amber)
                }

                HStack(spacing: 9) {
                    Spacer()
                    if requirement.status == .active {
                        Button("完成需求") {
                            state.completeRequirement(requirement.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else if requirement.status != .completed {
                        Button("处理") { onProcess() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    if requirement.status != .completed {
                        Button("不处理", role: .destructive) { onDecline() }
                        .buttonStyle(.borderless)
                    }
                    if requirement.status != .completed {
                        Menu {
                            Button("调整时间、重要程度与工作流…") {
                                onPlan()
                            }
                            Button("创建新工作流承接…") {
                                onCreateWorkflow()
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
        }
        .padding(13)
        .background(
            requirement.status == .active
                ? FocusTraceTheme.sky.opacity(0.10)
                : FocusTraceTheme.cardFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    requirement.status == .active
                        ? FocusTraceTheme.sky.opacity(0.5)
                        : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        }
    }

    private var statusMark: some View {
        Circle()
            .fill(requirement.status == .active
                  ? FocusTraceTheme.sky
                  : queueColor.opacity(0.82))
            .frame(width: 9, height: 9)
            .padding(.top, 6)
    }

    @ViewBuilder
    private var deadlineLabel: some View {
        if let dueDate = requirement.dueDate {
            Label(deadlineText(dueDate), systemImage: "calendar")
                .foregroundStyle(queueColor)
        } else if RequirementEngine.needsPlanning(requirement.record) {
            Label("待确认时间", systemImage: "calendar.badge.exclamationmark")
                .foregroundStyle(FocusTraceTheme.amber)
        } else {
            Label("无截止日期", systemImage: "calendar.badge.minus")
                .foregroundStyle(.secondary)
        }
    }

    private var importanceLabel: some View {
        Label(requirement.importance.title, systemImage: "flag")
            .foregroundStyle(
                requirement.importance == .high
                    ? FocusTraceTheme.coral
                    : Color.secondary
            )
    }

    private var queueColor: Color {
        switch RequirementEngine.queueSection(
            for: requirement.record,
            at: state.now
        ) {
        case .active: return FocusTraceTheme.sky
        case .overdue: return FocusTraceTheme.coral
        case .dueToday: return FocusTraceTheme.amber
        case .upcoming: return FocusTraceTheme.sky
        case .unscheduled: return .secondary
        case .needsPlanning: return FocusTraceTheme.amber
        case nil: return .secondary
        }
    }

    private func deadlineText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天截止" }
        if calendar.isDateInTomorrow(date) { return "明天截止" }
        if calendar.startOfDay(for: date) < calendar.startOfDay(for: state.now) {
            return "已逾期 · \(date.formatted(.dateTime.month().day()))"
        }
        return "\(date.formatted(.dateTime.month().day())) 截止"
    }
}

struct QuickRequirementCaptureSheet: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var source = ""
    @State private var showSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 11) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.title2)
                    .foregroundStyle(FocusTraceTheme.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("先把需求收下来")
                        .font(.title2.bold())
                    Text("保存后不会切换工作流，也不会绑定当前桌面。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField(
                "例如：下周前补上训练任务失败后的告警",
                text: $title,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            .controlSize(.large)

            DisclosureGroup("补充来源（可选）", isExpanded: $showSource) {
                TextField("例如：张三 / 周会 / 口头同步", text: $source)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 8)
            }
            .focusTraceDisclosureHitTarget(isExpanded: $showSource)
            .font(.callout)

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("收下需求") {
                    if state.captureRequirement(title: title, source: source) {
                        dismiss()
                    }
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 470)
        .focusTraceScreen()
        .focusTraceVisualSystem()
    }
}

private struct RequirementPlanningSheet: View {
    @ObservedObject var state: ApplicationState
    let requirement: RequirementItemModel
    @Environment(\.dismiss) private var dismiss
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var importance: RequirementImportance
    @State private var workflowID: UUID?

    init(state: ApplicationState, requirement: RequirementItemModel) {
        self.state = state
        self.requirement = requirement
        let today = Calendar.current.startOfDay(for: Date())
        _hasDeadline = State(initialValue: requirement.dueDate != nil)
        _deadline = State(initialValue: requirement.dueDate ?? today)
        _importance = State(initialValue: requirement.importance)
        _workflowID = State(initialValue: requirement.workflowID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("整理这个需求")
                    .font(.title2.bold())
                Text("三个决定彼此独立；保存不会切换工作流。")
                    .foregroundStyle(.secondary)
            }

            Text(requirement.title)
                .font(.callout.weight(.medium))
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    FocusTraceTheme.sky.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            if requirement.priority != .unplanned {
                Label(
                    "旧版只记录了“\(requirement.priority.legacyTitle)”，无法推断真实截止日期，请重新确认。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(FocusTraceTheme.amber)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("有明确截止日期", isOn: $hasDeadline)
                    if hasDeadline {
                        FocusTraceCompactDatePicker(
                            "截止日期",
                            selection: $deadline,
                            minimumDate: earliestDeadline
                        )
                    } else {
                        Text("没有时间承诺的需求仍会保留，但不会触发到期提醒。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Label("什么时候必须完成", systemImage: "calendar")
            }

            GroupBox {
                Picker("重要程度", selection: $importance) {
                    ForEach(RequirementImportance.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } label: {
                Label("同样紧迫时，哪一项更重要", systemImage: "flag")
            }

            GroupBox {
                Picker("工作流", selection: $workflowID) {
                    Text("暂不指定").tag(nil as UUID?)
                    ForEach(state.activeTasks) { workflow in
                        Text(workflow.title).tag(Optional(workflow.id))
                    }
                }
                .labelsHidden()
                Text("一个工作流可以承接多个需求；只有确实需要独立上下文时才新建工作流。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } label: {
                Label("在哪里处理", systemImage: "rectangle.on.rectangle")
            }

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存安排") {
                    if state.planRequirement(
                        id: requirement.id,
                        dueDate: hasDeadline ? deadline : nil,
                        importance: importance,
                        workflowID: workflowID
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .focusTraceScreen()
        .focusTraceVisualSystem()
    }

    private var earliestDeadline: Date {
        min(
            Calendar.current.startOfDay(for: requirement.dueDate ?? Date()),
            Calendar.current.startOfDay(for: Date())
        )
    }
}

private struct RequirementConversionSheet: View {
    @ObservedObject var state: ApplicationState
    let requirement: RequirementItemModel
    let startAfterCreation: Bool
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var workflowTitle: String

    init(
        state: ApplicationState,
        requirement: RequirementItemModel,
        startAfterCreation: Bool = false,
        onCreated: @escaping () -> Void = {}
    ) {
        self.state = state
        self.requirement = requirement
        self.startAfterCreation = startAfterCreation
        self.onCreated = onCreated
        _workflowTitle = State(
            initialValue: RequirementEngine.suggestedWorkflowTitle(
                from: requirement.title
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("转成新工作流")
                .font(.title2.bold())
            Text(
                startAfterCreation
                    ? "创建后会直接开始处理；这条需求不会影响同一工作流中的其他需求。"
                    : "这里只创建工作流，不会立刻绑定桌面。等你点击“处理”时再进入它。"
            )
                .foregroundStyle(.secondary)
            Text(requirement.title)
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            TextField("工作流名称", text: $workflowTitle)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("创建工作流") {
                    if let workflowID = state.convertRequirementToWorkflow(
                        requirement.id,
                        workflowTitle: workflowTitle
                    ) {
                        if startAfterCreation {
                            state.startRequirement(
                                requirement.id,
                                in: workflowID
                            )
                        }
                        onCreated()
                        dismiss()
                    }
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .disabled(
                    state.workflowNameValidationMessage(
                        for: workflowTitle
                    ) != nil
                )
            }
            if let validationMessage = state.workflowNameValidationMessage(
                for: workflowTitle
            ) {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(22)
        .frame(width: 500)
        .focusTraceScreen()
        .focusTraceVisualSystem()
    }
}

private extension RequirementPriority {
    var legacyTitle: String {
        switch self {
        case .unplanned: return "待整理"
        case .today: return "今天"
        case .thisWeek: return "本周"
        case .later: return "以后"
        }
    }
}

private extension RequirementImportance {
    var title: String {
        switch self {
        case .high: return "高"
        case .normal: return "普通"
        case .low: return "低"
        }
    }
}
