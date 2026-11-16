import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @State private var addressText = ""
    @State private var showCapability = false
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    addressCard
                    VStack(spacing: 12) {
                        Button {
                            showCapability = true
                        } label: {
                            HomeActionCard(
                                title: "画中画能力检测",
                                subtitle: capabilitySubtitle,
                                systemImage: "pip",
                                tint: .blue,
                                badge: capabilityBadge
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            HomeActionCard(
                                title: "诊断",
                                subtitle: "会话状态、媒体事件与隐私化日志",
                                systemImage: "waveform.path.ecg",
                                tint: .teal,
                                badge: coordinator.session.state.displayName
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SettingsView()
                        } label: {
                            HomeActionCard(
                                title: "设置",
                                subtitle: "工具栏、PiP 控件、音频与网站数据",
                                systemImage: "gearshape",
                                tint: .indigo,
                                badge: nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showCapability) {
            PiPCapabilityView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CloudFloat")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("云游戏画中画浏览器")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.pip.platformSupportsPiP ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(coordinator.pip.platformSupportsPiP ? "系统支持画中画" : "当前环境不支持系统画中画")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if coordinator.hasStartedBrowser {
                    Text(coordinator.session.state.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(.top, 2)
        }
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
                TextField("搜索或输入网址", text: $addressText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($addressFieldFocused)
                    .font(.system(size: 15, weight: .medium))
                    .onSubmit(openAddress)
                Button {
                    openAddress()
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .disabled(addressText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                coordinator.continueBrowsing()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(coordinator.hasStartedBrowser ? "继续浏览" : "开始浏览")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if coordinator.session.pipVisible {
                        Label("PiP", systemImage: "pip.fill")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if !coordinator.bookmarks.bookmarks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("书签")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(coordinator.bookmarks.bookmarks.prefix(5)) { bookmark in
                        Button {
                            if let url = bookmark.url {
                                coordinator.openURL(url)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(bookmark.urlString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("非官方浏览器")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("任何网页都可浏览；云游戏画中画是可选能力，需由网页视频自身支持。CloudFloat 不保存账号密码或令牌，也不宣称已经验证后台挂机成功。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var capabilityBadge: String? {
        if !coordinator.pip.platformSupportsPiP {
            return "不支持"
        }
        if coordinator.media.lastSnapshotReceivedAt == nil {
            return "待检测"
        }
        return coordinator.pip.availability.isAvailable ? "可用" : "不可用"
    }

    private var capabilitySubtitle: String {
        if !coordinator.pip.platformSupportsPiP {
            return "此设备/模拟器不支持 PiP，检测仍会展示媒体结构"
        }
        return "平台、WebView 与网页视频三层能力检查"
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                Color(uiColor: .secondarySystemBackground).opacity(0.7),
                Color.accentColor.opacity(0.06)
            ],
            startPoint: .top,
            endPoint: .bottomTrailing
        )
    }

    private func openAddress() {
        addressFieldFocused = false
        coordinator.openAddressText(addressText)
    }
}

private struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let badge: String?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.10), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
