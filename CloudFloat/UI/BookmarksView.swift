import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    let canAddCurrentPage: Bool

    @State private var selectedFolderID: UUID?
    @State private var editingBookmark: Bookmark?
    @State private var showNewFolderField = false
    @State private var newFolderName = ""
    @State private var editingFolder: BookmarkFolder?
    @State private var sortMode: BookmarkSortOrder = .title

    var body: some View {
        NavigationStack {
            List {
                folderSection
                bookmarkSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $editingBookmark) { bookmark in
                EditBookmarkSheet(bookmark: bookmark) { updated in
                    coordinator.bookmarks.update(updated)
                }
            }
            .sheet(item: $editingFolder) { folder in
                EditFolderSheet(folder: folder) { updated in
                    coordinator.bookmarks.renameFolder(updated.id, to: updated.name)
                }
            }
            .onAppear {
                selectedFolderID = coordinator.bookmarks.rootFolder?.id
                if coordinator.bookmarks.bookmarks.isEmpty, coordinator.bookmarks.folders.count == 1 {
                    showNewFolderField = false
                }
            }
        }
    }

    private var currentFolder: BookmarkFolder? {
        coordinator.bookmarks.folders.first { $0.id == selectedFolderID }
            ?? coordinator.bookmarks.rootFolder
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("完成") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                addCurrentPage()
            } label: {
                Image(systemName: "plus")
            }
            .disabled(!canAddCurrentPage || !canBookmarkCurrentPage)
            .accessibilityLabel("添加当前页面到书签")
        }
    }

    private var folderSection: some View {
        Section("文件夹") {
            ForEach(coordinator.bookmarks.folders) { folder in
                Button {
                    selectedFolderID = folder.id
                } label: {
                    HStack {
                        Label(folder.name, systemImage: "folder")
                        Spacer()
                        if folder.id == selectedFolderID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("重命名") {
                        editingFolder = folder
                    }
                    Button("排序：按名称") { coordinator.bookmarks.sortBookmarks(in: folder.id, by: .title) }
                    Button("删除文件夹", role: .destructive) {
                        coordinator.bookmarks.removeFolder(folder.id)
                        selectedFolderID = coordinator.bookmarks.rootFolder?.id
                    }
                }
            }
            if showNewFolderField {
                TextField("新文件夹名称", text: $newFolderName)
                    .onSubmit {
                        coordinator.bookmarks.createFolder(named: newFolderName)
                        newFolderName = ""
                        showNewFolderField = false
                    }
            }
        }
    }

    private var bookmarkSection: some View {
        Section {
            if canAddCurrentPage, canBookmarkCurrentPage {
                Button {
                    addCurrentPage()
                } label: {
                    Label("添加当前网页", systemImage: "plus")
                }
            }
            let bookmarks = currentFolderBookmarks
            if bookmarks.isEmpty {
                Text("此文件夹暂无书签")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bookmarks) { bookmark in
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
                    .contextMenu {
                        Button("编辑") {
                            editingBookmark = bookmark
                        }
                        Button("移到当前文件夹") {
                            if let folder = currentFolder {
                                coordinator.bookmarks.move(bookmark.id, to: folder.id)
                            }
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            coordinator.bookmarks.remove(bookmark.id)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("书签")
                Spacer()
                Picker("排序", selection: $sortMode) {
                    ForEach(BookmarkSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: sortMode) { _, order in
                    if let folder = currentFolder {
                        coordinator.bookmarks.sortBookmarks(in: folder.id, by: order)
                    }
                }
            }
        }
    }

    private var canBookmarkCurrentPage: Bool {
        guard let url = coordinator.browser.currentURL else { return false }
        return url.absoluteString != "about:blank"
    }

    private var currentFolderBookmarks: [Bookmark] {
        guard let folder = currentFolder else { return [] }
        let bookmarks = coordinator.bookmarks.bookmarks(in: folder.id)
        if sortMode == .newest {
            return bookmarks.sorted { $0.createdAt > $1.createdAt }
        }
        return bookmarks
    }

    private func addCurrentPage() {
        guard let url = coordinator.browser.currentURL else { return }
        coordinator.bookmarks.add(
            title: coordinator.browser.pageTitle,
            url: url,
            folderID: currentFolder?.id
        )
        coordinator.showToast("已添加书签", .info)
    }
}

private struct EditBookmarkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let bookmark: Bookmark
    let onSave: (Bookmark) -> Void

    @State private var title: String
    @State private var urlString: String

    init(bookmark: Bookmark, onSave: @escaping (Bookmark) -> Void) {
        self.bookmark = bookmark
        self.onSave = onSave
        _title = State(initialValue: bookmark.title)
        _urlString = State(initialValue: bookmark.urlString)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $title)
                TextField("网址", text: $urlString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
            }
            .navigationTitle("编辑书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(Bookmark(
                            id: bookmark.id,
                            title: title,
                            urlString: urlString,
                            folderID: bookmark.folderID,
                            sortOrder: bookmark.sortOrder,
                            createdAt: bookmark.createdAt
                        ))
                        dismiss()
                    }
                    .disabled(title.isEmpty || urlString.isEmpty)
                }
            }
        }
    }
}


@MainActor
private struct EditFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let folder: BookmarkFolder
    let onSave: (BookmarkFolder) -> Void

    @State private var name: String

    init(folder: BookmarkFolder, onSave: @escaping (BookmarkFolder) -> Void) {
        self.folder = folder
        self.onSave = onSave
        _name = State(initialValue: folder.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("文件夹名称", text: $name)
            }
            .navigationTitle("编辑文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(BookmarkFolder(
                            id: folder.id,
                            name: name,
                            sortOrder: folder.sortOrder,
                            createdAt: folder.createdAt
                        ))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
