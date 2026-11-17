import SwiftUI

@main
struct AriunoApp: App {
    @StateObject private var coordinator: AppCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = AppSettings()
        let diagnostics = DiagnosticsStore()
        _coordinator = StateObject(
            wrappedValue: AppCoordinator(settings: settings, diagnostics: diagnostics)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.settings)
                .environmentObject(coordinator.diagnostics)
                .onChange(of: scenePhase) { _, newPhase in
                    coordinator.handleScenePhase(newPhase)
                }
                .tint(.accentColor)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        ZStack {
            // The game view is kept mounted once a session starts, even while the user is on
            // the home screen, so SwiftUI state changes never recreate the WKWebView.
            if coordinator.hasStartedBrowser {
                BrowserView()
                    .opacity(coordinator.route == .game ? 1 : 0)
                    .allowsHitTesting(coordinator.route == .game)
                    .accessibilityHidden(coordinator.route != .game)
            }
            if coordinator.route == .home {
                BrowserStartPageView()
                    .transition(.opacity)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .top) {
            if let toast = coordinator.toast {
                ToastBanner(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: coordinator.route)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: coordinator.toast)
        .sheet(item: $coordinator.debugPresentation) { presentation in
            switch presentation {
            case .testLab:
                NavigationStack {
                    TestPageLabView()
                }
            case .diagnostics:
                NavigationStack {
                    DiagnosticsView()
                }
            case .settings:
                NavigationStack {
                    SettingsView()
                }
            case .capability:
                PiPCapabilityView()
            }
        }
    }
}

private struct ToastBanner: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
            Text(toast.text)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var iconName: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var backgroundStyle: Color {
        switch toast.kind {
        case .info: return Color(red: 0.13, green: 0.16, blue: 0.22)
        case .warning: return Color(red: 0.55, green: 0.33, blue: 0.06)
        case .error: return Color(red: 0.55, green: 0.13, blue: 0.15)
        }
    }
}
