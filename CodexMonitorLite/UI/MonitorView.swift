import SwiftUI

struct MonitorView: View {
    @ObservedObject var viewModel: MonitorViewModel
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectView()
                Color(red: 0.035, green: 0.075, blue: 0.12)
                    .opacity(colorScheme == .dark ? 0.36 : 0.12)
            }

            VStack(spacing: 8) {
                header
                filters
                errorBanner
                taskList
                footer
            }
            .padding(12)
        }
        .frame(minWidth: 320, idealWidth: 320, maxWidth: 320, minHeight: 320, idealHeight: 700)
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

            Spacer()

            iconButton("arrow.clockwise", help: "重新连接") { viewModel.retry() }
            iconButton("power", help: "退出 Codex Monitor Lite") { onQuit() }
        }
        .frame(height: 32)
    }

    private var filters: some View {
        HStack(spacing: 2) {
            ForEach(MonitorFilter.allCases) { filter in
                let selected = viewModel.selectedFilter == filter
                Button {
                    viewModel.selectedFilter = filter
                } label: {
                    HStack(spacing: 3) {
                        if filter != .all {
                            Circle()
                                .fill(filterAccent(filter))
                                .frame(width: 7, height: 7)
                        }
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
        .frame(height: 38)
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
                Text("暂无任务")
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
        HStack(spacing: 6) {
            Text("\(viewModel.scopedTaskCount) 个 · \(viewModel.count(for: .running)) 运行")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Text("最近 24h")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("活跃")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Toggle("", isOn: $viewModel.onlyActive)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("仅显示活跃会话")
        }
        .frame(height: 28)
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
        case .all: .clear
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
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Circle()
                    .fill(task.status.accentColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: task.status.accentColor.opacity(0.38), radius: 4)

                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(task.title)

                Spacer(minLength: 4)

                Text(task.status.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(task.status.accentColor)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(task.status.accentColor.opacity(0.2), in: Capsule())
            }

            HStack(spacing: 6) {
                Text(task.currentAction ?? task.summary ?? "暂无活动")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(task.currentAction ?? task.summary ?? "暂无活动")
                Spacer(minLength: 4)
                Text(activityLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if let path = task.workspaceDisplayPath {
                    metadata("folder", path, maxWidth: 158)
                }
                if let branch = task.branch {
                    metadata("point.3.connected.trianglepath.dotted", branch, maxWidth: 102)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    metadata("clock", EventTime.compactDuration(milliseconds: task.elapsedMilliseconds(at: context.date)))
                        .monospacedDigit()
                }
                if let model = task.model {
                    metadata("cube", model, maxWidth: 138)
                }
                Spacer(minLength: 4)

                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("在 Codex 中打开")
                .accessibilityLabel("在 Codex 中打开 \(task.title)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(height: 104)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.075 : 0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isHovering ? 0.17 : 0.11), lineWidth: 1)
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title)，\(task.status.title)，\(task.currentAction ?? "")")
    }

    private var activityLabel: String {
        if let completedAt = task.completedAt {
            return EventTime.relativeDescription(from: completedAt)
        }
        return EventTime.relativeDescription(from: task.lastActivityAt)
    }

    private func metadata(_ symbol: String, _ text: String, maxWidth: CGFloat? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .frame(maxWidth: maxWidth, alignment: .leading)
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
