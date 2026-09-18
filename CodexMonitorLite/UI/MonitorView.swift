import SwiftUI

struct MonitorView: View {
    @ObservedObject var viewModel: MonitorViewModel
    @ObservedObject var lanSharing: LANSharingController
    let onTogglePin: () -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showingLANSharing = false

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectView()
                Color(red: 0.035, green: 0.075, blue: 0.12)
                    .opacity(colorScheme == .dark ? 0.36 : 0.12)
            }

            VStack(spacing: 7) {
                header
                filters
                errorBanner
                taskList
                footer
            }
            .padding(10)
        }
        .frame(minWidth: 320, idealWidth: 320, maxWidth: 320, minHeight: 280, idealHeight: 480)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Codex")
                .font(.system(size: 18, weight: .semibold))

            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(viewModel.connectionState.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if viewModel.isPinned {
                WindowDragArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            } else {
                Spacer()
            }

            Button {
                showingLANSharing.toggle()
            } label: {
                Image(systemName: "iphone")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if lanSharing.isEnabled {
                            Circle()
                                .fill(MonitorPalette.running)
                                .frame(width: 6, height: 6)
                                .offset(x: -2, y: 3)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("连接 Android 手机")
            .accessibilityLabel(lanSharing.isEnabled ? "Android 局域网共享已开启" : "连接 Android 手机")
            .popover(isPresented: $showingLANSharing, arrowEdge: .bottom) {
                LANSharingView(controller: lanSharing)
            }

            iconButton(
                viewModel.isPinned ? "pin.slash" : "pin",
                help: viewModel.isPinned ? "取消固定到桌面" : "固定到桌面",
                action: onTogglePin
            )
            iconButton("power", help: "退出 Codex Monitor Lite") { onQuit() }
        }
        .frame(height: 30)
    }

    private var filters: some View {
        HStack(spacing: 2) {
            ForEach(MonitorFilter.allCases) { filter in
                let selected = viewModel.selectedFilter == filter
                Button {
                    viewModel.selectedFilter = filter
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(filterAccent(filter))
                            .frame(width: 7, height: 7)
                        Text(filter.title)
                        Text(compactCount(viewModel.count(for: filter)))
                            .fontDesign(.monospaced)
                            .opacity(0.72)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(selected ? Color.black.opacity(0.82) : Color.primary.opacity(0.76))
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? Color.white.opacity(0.9) : Color.white.opacity(0.025))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(filter.title)，\(viewModel.count(for: filter)) 个任务")
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(height: 36)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if case .failed(let message) = viewModel.connectionState {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.red.opacity(0.92))
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Button("重试") { viewModel.retry() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var taskList: some View {
        if viewModel.connectionState == .connecting && viewModel.tasks.isEmpty {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在读取本地 Codex 状态")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.visibleTasks.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(.secondary)
                Text(emptyStateTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.visibleTasks) { task in
                        TaskCardView(task: task) { viewModel.open(task) }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("仅显示最近 24h")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(height: 22)
    }

    private var emptyStateTitle: String {
        switch viewModel.selectedFilter {
        case .running: "暂无运行中的任务"
        case .needsAttention: "暂无需要处理的任务"
        case .awaitingReview: "暂无待查看的任务"
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .connecting: .gray
        case .connected: MonitorPalette.running
        case .failed: .red
        }
    }

    private func filterAccent(_ filter: MonitorFilter) -> Color {
        switch filter {
        case .running: MonitorPalette.running
        case .needsAttention: MonitorPalette.attention
        case .awaitingReview: MonitorPalette.review
        }
    }

    private func compactCount(_ count: Int) -> String { count > 999 ? "999+" : String(count) }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct TaskCardView: View {
    let task: MonitoredTask
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 4) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(task.status.accentColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: task.status.accentColor.opacity(0.34), radius: 3)

                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Text(activityLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(activityText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                }

                HStack(spacing: 10) {
                    metadata("folder", task.projectName)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        metadata("clock", EventTime.compactDuration(milliseconds: task.elapsedMilliseconds(at: context.date)))
                            .monospacedDigit()
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(isHovering ? 0.95 : 0.5))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(height: 82)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.075 : 0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isHovering ? 0.17 : 0.11), lineWidth: 1)
        }
        .onHover { isHovering = $0 }
        .help("在 Codex 中打开 \(task.title)")
        .accessibilityLabel("在 Codex 中打开 \(task.title)，\(task.status.title)，\(activityText)")
    }

    private var activityText: String {
        switch task.status {
        case .running:
            task.currentAction ?? task.summary ?? "正在运行"
        case .needsAttention:
            task.currentAction ?? task.summary ?? "等待你的操作"
        case .awaitingReview:
            "任务已完成"
        case .inactive:
            "已查看"
        }
    }

    private var activityLabel: String {
        if let completedAt = task.completedAt {
            return EventTime.relativeDescription(from: completedAt)
        }
        return EventTime.relativeDescription(from: task.lastActivityAt)
    }

    private func metadata(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .frame(maxWidth: 150, alignment: .leading)
        .help(text)
    }
}

enum MonitorPalette {
    static let running = Color(red: 0.19, green: 0.84, blue: 0.48)
    static let attention = Color(red: 1.0, green: 0.67, blue: 0.20)
    static let review = Color(red: 0.37, green: 0.54, blue: 0.77)
    static let inactive = Color(red: 0.67, green: 0.71, blue: 0.76)
}

private extension MonitorTaskStatus {
    var accentColor: Color {
        switch self {
        case .running: MonitorPalette.running
        case .needsAttention: MonitorPalette.attention
        case .awaitingReview: MonitorPalette.review
        case .inactive: MonitorPalette.inactive
        }
    }
}
