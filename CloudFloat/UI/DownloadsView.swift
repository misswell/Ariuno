import SwiftUI
import UIKit

struct DownloadsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareableFile?

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
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
                    .ignoresSafeArea()
            }
        }
    }

    private struct ShareableFile: Identifiable {
        let id = UUID()
        let url: URL
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
                if item.state == .downloading {
                    if item.totalBytes > 0 {
                        ProgressView(value: item.progress)
                    } else {
                        ProgressView()
                    }
                    Text(progressText(item))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(stateText(item))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                actionButtons(item)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func actionButtons(_ item: DownloadItem) -> some View {
        HStack(spacing: 8) {
            if item.state == .downloading || item.state == .waiting {
                Button("暂停") {
                    coordinator.downloadManager.pause(item)
                }
                if !item.isShareable {
                    Button("取消") {
                        coordinator.downloadManager.cancel(item)
                    }
                }
            }
            if item.isResumable {
                Button("继续") {
                    coordinator.downloadManager.resume(item)
                }
            }
            if item.state == .paused || item.state == .failed {
                Button("取消") {
                    coordinator.downloadManager.cancel(item)
                }
            }
            if item.isShareable, let destination = item.destinationURL {
                Button {
                    shareItem = ShareableFile(url: destination)
                } label: {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .buttonBorderShape(.capsule)
    }

    private func progressText(_ item: DownloadItem) -> String {
        if item.totalBytes > 0 {
            return "下载中 \(ByteCountFormatter.string(fromByteCount: item.receivedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))"
        }
        return "下载中…"
    }

    private func stateIcon(_ state: DownloadItem.State) -> String {
        switch state {
        case .waiting: return "clock"
        case .downloading: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private func stateColor(_ state: DownloadItem.State) -> Color {
        switch state {
        case .waiting: return .secondary
        case .downloading: return .blue
        case .paused: return .orange
        case .finished: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }

    private func stateText(_ item: DownloadItem) -> String {
        switch item.state {
        case .waiting: return "等待下载"
        case .downloading: return "下载中 \(Int(item.progress * 100))%"
        case .paused: return item.resumeData == nil ? "已暂停（无法续传）" : "已暂停"
        case .finished: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }
}
