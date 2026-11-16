import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var settings: AppSettings
    @State private var showCapability = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    continueCard
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

    private var continueCard: some View {
        Button {
            coordinator.continueGame()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 52, height: 52)
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("继续游戏")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(continueSubtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.45, blue: 0.95),
                        Color(red: 0.33, green: 0.22, blue: 0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.18, green: 0.30, blue: 0.80).opacity(0.32), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开官方云游戏网页；已有会话时直接返回游戏")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("非官方客户端")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("登录、游玩与云游戏会话均在官方网页内完成。CloudFloat 不保存账号密码或令牌，也不宣称已经验证后台挂机成功。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var continueSubtitle: String {
        if coordinator.hasStartedBrowser {
            if coordinator.session.pipVisible {
                return "画中画显示中，点击返回游戏页面"
            }
            return "\(coordinator.session.state.displayName) · 保留当前网页会话"
        }
        return "打开官方云游戏网页，登录后开始"
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
