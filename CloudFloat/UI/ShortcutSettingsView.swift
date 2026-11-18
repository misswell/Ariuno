import SwiftUI

struct ShortcutSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var isAdding = false
    @State private var editingShortcut: StartPageShortcut?

    var body: some View {
        List {
            Section {
                ForEach(coordinator.shortcuts.shortcuts) { shortcut in
                    Button {
                        editingShortcut = shortcut
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: shortcut.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 36, height: 36)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shortcut.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(shortcut.host)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    coordinator.shortcuts.remove(at: offsets)
                }
                .onMove { source, destination in
                    coordinator.shortcuts.move(from: source, to: destination)
                }

                Button {
                    isAdding = true
                } label: {
                    Label("添加网站", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("首页“常用网站”按这里的顺序显示。左滑删除，点右上角“编辑”可拖动排序；图标从系统 SF Symbols 中选择。")
            }
        }
        .navigationTitle("常用网站")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $isAdding) {
            ShortcutEditorView(shortcut: nil)
                .environmentObject(coordinator)
        }
        .sheet(item: $editingShortcut) { shortcut in
            ShortcutEditorView(shortcut: shortcut)
                .environmentObject(coordinator)
        }
    }
}

private struct ShortcutEditorView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    let shortcut: StartPageShortcut?

    @State private var title: String
    @State private var urlString: String
    @State private var systemImage: String

    init(shortcut: StartPageShortcut?) {
        self.shortcut = shortcut
        _title = State(initialValue: shortcut?.title ?? "")
        _urlString = State(initialValue: shortcut?.urlString ?? "")
        _systemImage = State(initialValue: shortcut?.systemImage ?? ShortcutIconCatalog.fallback)
    }

    private var normalizedURL: String? {
        StartPageShortcutStore.normalizedURLString(urlString)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizedURL != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("例如 GitHub", text: $title)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    TextField("https://example.com", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("网址")
                } footer: {
                    if urlString.isEmpty {
                        Text("不写 https:// 时会自动补全。")
                    } else if normalizedURL == nil {
                        Text("请输入有效的 http/https 网址。")
                            .foregroundStyle(.red)
                    } else {
                        Text("将打开 \(normalizedURL ?? "")")
                    }
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(ShortcutIconCatalog.options, id: \.self) { icon in
                            Button {
                                systemImage = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(systemImage == icon ? Color.white : Color.primary)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        systemImage == icon
                                            ? Color.accentColor
                                            : Color.primary.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon)
                            .accessibilityAddTraits(systemImage == icon ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("图标")
                } footer: {
                    Text("从系统 SF Symbols 中选择一个。")
                }

                Section("预览") {
                    HStack(spacing: 12) {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title.isEmpty ? "名称" : title)
                                .font(.subheadline.weight(.medium))
                            Text(normalizedURL ?? "网址")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle(shortcut == nil ? "添加网站" : "编辑网站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let normalizedURL else { return }
        if let shortcut {
            _ = coordinator.shortcuts.update(
                id: shortcut.id,
                title: title,
                urlString: normalizedURL,
                systemImage: systemImage
            )
        } else {
            coordinator.shortcuts.add(
                title: title,
                urlString: normalizedURL,
                systemImage: systemImage
            )
        }
        dismiss()
    }
}
