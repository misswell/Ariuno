import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("搜索历史记录", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Section("历史记录（\(filtered.count)）") {
                    if filtered.isEmpty {
                        Text("暂无历史记录")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filtered) { entry in
                            Button {
                                if let url = entry.url {
                                    coordinator.openURL(url)
                                    dismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(entry.urlString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Text(Self.timeFormatter.string(from: entry.visitedAt))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                coordinator.library.history.remove(filtered[index].id)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(coordinator.library.history.entries.isEmpty)
                    .accessibilityLabel("清空历史记录")
                }
            }
            .confirmationDialog(
                "清空历史记录？",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清空", role: .destructive) {
                    coordinator.library.history.clear()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("隐私标签页不会记录历史。")
            }
        }
    }

    private var filtered: [HistoryEntry] {
        coordinator.library.history.entries(matching: query)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
