import AppKit
import SwiftUI

struct LANSharingView: View {
    @ObservedObject var controller: LANSharingController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Android 局域网")
                    .font(.system(size: 14, weight: .semibold))
                Text("同一 Wi-Fi 下只读同步任务")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "开启局域网共享",
                isOn: Binding(
                    get: { controller.isEnabled },
                    set: { controller.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)

            if controller.isEnabled {
                Divider().opacity(0.45)

                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(controller.statusText)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("连接码")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(controller.pairingCode)
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("复制") { copyPairingCode() }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                Text("在 Android App 输入此连接码。手机仅在前台且位于同一可信 Wi-Fi 时连接。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("生成新连接码") { controller.regeneratePairingCode() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 280)
        .preferredColorScheme(.dark)
    }

    private var statusColor: Color {
        switch controller.statusColor {
        case .inactive: MonitorPalette.inactive
        case .waiting: MonitorPalette.attention
        case .connected: MonitorPalette.running
        case .failed: .red
        }
    }

    private func copyPairingCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.pairingCode, forType: .string)
    }
}
