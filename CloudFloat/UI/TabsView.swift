import SwiftUI

struct TabsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(coordinator.tabs.sessions) { session in
                    tabRow(session)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let session = coordinator.tabs.sessions[index]
                        coordinator.closeTab(session)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("标签页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        coordinator.createTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建标签页")
                }
            }
        }
    }

    @ViewBuilder
    private func tabRow(_ session: BrowserSession) -> some View {
        let isActive = session.id == coordinator.tabs.activeSessionID
        Button {
            coordinator.activateTab(session)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.pageTitle.isEmpty ? "未命名页面" : session.pageTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(session.currentURL?.absoluteString ?? "空白页")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(isActive ? "当前标签页" : "后台标签页")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
