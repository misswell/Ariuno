import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    let canAddCurrentPage: Bool

    var body: some View {
        NavigationStack {
            List {
                if coordinator.bookmarks.bookmarks.isEmpty {
                    Text("暂无书签。浏览网页后可从工具栏添加。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.bookmarks.bookmarks) { bookmark in
                        Button {
                            if let url = bookmark.url {
                                coordinator.openURL(url)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bookmark.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text(bookmark.urlString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            coordinator.bookmarks.remove(
                                coordinator.bookmarks.bookmarks[index].id
                            )
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                if canAddCurrentPage, canBookmarkCurrentPage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            addCurrentPage()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("添加当前页面到书签")
                    }
                }
            }
        }
    }

    private var currentURL: URL? {
        coordinator.browser.currentURL
    }

    private var canBookmarkCurrentPage: Bool {
        guard let url = currentURL else { return false }
        return url.absoluteString != "about:blank"
    }

    private func addCurrentPage() {
        guard let url = currentURL else { return }
        coordinator.bookmarks.add(
            title: coordinator.browser.pageTitle,
            url: url
        )
        coordinator.showToast("已添加书签", .info)
    }
}
