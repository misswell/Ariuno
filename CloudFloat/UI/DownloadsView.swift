import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if coordinator.downloadManager.items.isEmpty {
                    Text("暂无下载")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.downloadManager.items) { item in
                        downloadRow(item)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func downloadRow(_ item: DownloadItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stateIcon(item.state))
                .foregroundStyle(stateColor(item.state))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.suggestedFilename)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let destination = item.destinationURL {
                    Text(destination.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let error = item.errorText {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Text(stateText(item))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.state == .downloading {
                Button("取消") {
                    coordinator.downloadManager.cancel(item)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func stateIcon(_ state: DownloadItem.State) -> String {
        switch state {
        case .waiting, .downloading: return "arrow.down.circle"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private func stateColor(_ state: DownloadItem.State) -> Color {
        switch state {
        case .waiting, .downloading: return .blue
        case .finished: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    private func stateText(_ item: DownloadItem) -> String {
        switch item.state {
        case .waiting: return "等待下载"
        case .downloading: return "下载中 \(Int(item.progress * 100))%"
        case .finished: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}
