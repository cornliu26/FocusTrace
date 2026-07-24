import SwiftUI
import FocusTraceCore

struct RequirementsView: View {
    @ObservedObject var state: ApplicationState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCapture = false
    @State private var requirementToConvert: RequirementItemModel?
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
                        requirements: requirements(status: .active)
                    )
                    requirementSection(
                        title: "待整理",
                        subtitle: "还没决定优先级或工作流",
                        requirements: unplannedRequirements
                    )
                    requirementSection(
                        title: "今天",
                        subtitle: "今天明确要推进",
                        requirements: requirements(priority: .today)
                    )
                    requirementSection(
                        title: "本周",
                        subtitle: "本周安排，但不打断当前工作",
                        requirements: requirements(priority: .thisWeek)
                    )
                    requirementSection(
                        title: "以后",
                        subtitle: "先保留，暂不承诺时间",
                        requirements: requirements(priority: .later)
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
                                    onCreateWorkflow: {
                                        requirementToConvert = requirement
                                    }
                                )
                            }
                        }
                        .padding(.top, 10)
                    }
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
            RequirementConversionSheet(state: state, requirement: requirement)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FocusTraceTheme.mint.opacity(0.13))
                Image(systemName: "tray.and.arrow.down")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(FocusTraceTheme.mint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text("需求箱")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("先收下，再决定挂到已有工作流还是创建新工作流。记录需求不会切走当前桌面。")
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
                        onCreateWorkflow: {
                            requirementToConvert = requirement
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

    private var unplannedRequirements: [RequirementItemModel] {
        openRequirements.filter {
            $0.status != .active && $0.priority == .unplanned
        }
    }

    private func requirements(status: RequirementStatus) -> [RequirementItemModel] {
        openRequirements.filter { $0.status == status }
    }

    private func requirements(priority: RequirementPriority) -> [RequirementItemModel] {
        openRequirements.filter {
            $0.status != .active && $0.priority == priority
        }
    }
}

private struct RequirementCard: View {
    @ObservedObject var state: ApplicationState
    let requirement: RequirementItemModel
    let onCreateWorkflow: () -> Void
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
                    if let workflowID = requirement.workflowID {
                        Label(state.taskName(for: workflowID), systemImage: "rectangle.on.rectangle")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                HStack(spacing: 9) {
                    priorityMenu
                    workflowMenu
                    Spacer()
                    if requirement.status == .active {
                        Label("正在处理", systemImage: "bolt.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FocusTraceTheme.mint)
                    } else if requirement.workflowID != nil {
                        Button("开始处理") {
                            state.startRequirement(requirement.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    if requirement.status != .completed {
                        Button {
                            state.completeRequirement(requirement.id)
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.borderless)
                        .help("标记完成")
                    }
                    Menu {
                        Button("归档为不做", role: .destructive) {
                            state.archiveRequirement(requirement.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(13)
        .background(
            requirement.status == .active
                ? FocusTraceTheme.mint.opacity(0.10)
                : FocusTraceTheme.cardFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    requirement.status == .active
                        ? FocusTraceTheme.mint.opacity(0.5)
                        : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        }
    }

    private var statusMark: some View {
        Circle()
            .fill(requirement.status == .active
                  ? FocusTraceTheme.mint
                  : priorityColor.opacity(0.78))
            .frame(width: 9, height: 9)
            .padding(.top, 6)
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(RequirementPriority.allCases, id: \.self) { priority in
                Button(priority.title) {
                    state.setRequirementPriority(requirement.id, priority: priority)
                }
            }
        } label: {
            Label(requirement.priority.title, systemImage: "flag")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var workflowMenu: some View {
        Menu {
            ForEach(state.activeTasks) { workflow in
                Button(workflow.title) {
                    state.attachRequirement(requirement.id, to: workflow.id)
                }
            }
            if !state.activeTasks.isEmpty {
                Divider()
            }
            Button("转成新工作流…") {
                onCreateWorkflow()
            }
        } label: {
            Label(
                requirement.workflowID == nil ? "安排工作流" : "更换工作流",
                systemImage: "rectangle.on.rectangle"
            )
            .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var priorityColor: Color {
        switch requirement.priority {
        case .unplanned: return .secondary
        case .today: return FocusTraceTheme.mint
        case .thisWeek: return FocusTraceTheme.sky
        case .later: return FocusTraceTheme.amber
        }
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

private struct RequirementConversionSheet: View {
    @ObservedObject var state: ApplicationState
    let requirement: RequirementItemModel
    @Environment(\.dismiss) private var dismiss
    @State private var workflowTitle: String

    init(state: ApplicationState, requirement: RequirementItemModel) {
        self.state = state
        self.requirement = requirement
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
            Text("这里只创建工作流，不会立刻绑定桌面。等你点击“开始处理”时再进入它。")
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
                    if state.convertRequirementToWorkflow(
                        requirement.id,
                        workflowTitle: workflowTitle
                    ) != nil {
                        dismiss()
                    }
                }
                .buttonStyle(FocusTracePrimaryButtonStyle())
                .disabled(workflowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 500)
        .focusTraceScreen()
        .focusTraceVisualSystem()
    }
}

private extension RequirementPriority {
    var title: String {
        switch self {
        case .unplanned: return "待整理"
        case .today: return "今天"
        case .thisWeek: return "本周"
        case .later: return "以后"
        }
    }
}
