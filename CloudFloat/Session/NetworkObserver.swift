import Foundation
import Network

enum NetworkStatus: String, Equatable, Codable {
    case unknown
    case wifi
    case cellular
    case other
    case unavailable

    var isAvailable: Bool {
        switch self {
        case .wifi, .cellular, .other: return true
        case .unknown, .unavailable: return false
        }
    }

    var displayName: String {
        switch self {
        case .unknown: return "未知"
        case .wifi: return "Wi-Fi"
        case .cellular: return "蜂窝网络"
        case .other: return "其他网络"
        case .unavailable: return "无网络"
        }
    }
}

/// Thin NWPathMonitor wrapper. Reports interface class only; no addresses are collected.
@MainActor
final class NetworkObserver: ObservableObject {
    @Published private(set) var status: NetworkStatus = .unknown
    @Published private(set) var changeCount: Int = 0

    var onChange: ((NetworkStatus) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cloudfloat.network-monitor")
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let mapped = NetworkObserver.map(path)
            Task { @MainActor in
                guard let self else { return }
                if mapped != self.status {
                    self.status = mapped
                    self.changeCount += 1
                    self.onChange?(mapped)
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard started else { return }
        monitor.cancel()
        started = false
    }

    nonisolated static func map(_ path: NWPath) -> NetworkStatus {
        guard path.status == .satisfied else { return .unavailable }
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .other }
        return .other
    }
}
