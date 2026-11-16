import Foundation
import Network

/// Minimal loopback-only static file server used by the developer test lab and integration
/// tests. It serves only files inside `TestPages` (no directory listing, no path traversal),
/// supports HTTP Range for video seeking, and never binds to a non-loopback interface.
final class LocalHTTPServer {
    enum ServerError: LocalizedError {
        case failedToStart(String)
        case testPagesMissing

        var errorDescription: String? {
            switch self {
            case .failedToStart(let message): return "本地测试服务器启动失败：\(message)"
            case .testPagesMissing: return "App Bundle 中缺少 TestPages 资源"
            }
        }
    }

    private(set) var port: UInt16?
    private let rootDirectory: URL
    private let queue = DispatchQueue(label: "com.cloudfloat.local-http", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var isStopped = true

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    static func testPagesDirectory(bundle: Bundle = .main) -> URL? {
        if let directory = bundle.url(forResource: "TestPages", withExtension: nil) {
            return directory
        }
        // XcodeGen folder references normally keep the directory, but support a flattened
        // bundle as a fallback for local experiments.
        if bundle.url(forResource: "native-video", withExtension: "html") != nil {
            return bundle.bundleURL
        }
        return nil
    }

    /// Starts a listener bound to 127.0.0.1 on an ephemeral port.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any
        )

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw ServerError.failedToStart(error.localizedDescription)
        }
        self.listener = listener
        isStopped = false

        return try await withCheckedThrowingContinuation { continuation in
            let gate = ResumeGate()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard gate.tryResume() else { return }
                    guard let port = listener.port?.rawValue, port != 0 else {
                        continuation.resume(
                            throwing: ServerError.failedToStart("未能分配本地端口")
                        )
                        return
                    }
                    self?.port = port
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard gate.tryResume() else { return }
                    continuation.resume(
                        throwing: ServerError.failedToStart(error.localizedDescription)
                    )
                case .cancelled:
                    guard gate.tryResume() else { return }
                    continuation.resume(
                        throwing: ServerError.failedToStart("监听器被取消")
                    )
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: self.queue)
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
        }
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections.removeValue(forKey: ObjectIdentifier(connection))
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if buffer.count > 32_768 {
                self.sendError(status: 431, reason: "Request Header Fields Too Large", on: connection)
                return
            }
            if let terminator = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<terminator.lowerBound)
                self.respond(to: headerData, on: connection)
                return
            }
            if isComplete || error != nil {
                self.sendError(status: 400, reason: "Bad Request", on: connection)
                return
            }
            self.receiveRequest(on: connection, buffer: buffer)
        }
    }

    private func respond(to headerData: Data, on connection: NWConnection) {
        guard let header = String(data: headerData, encoding: .utf8) else {
            sendError(status: 400, reason: "Bad Request", on: connection)
            return
        }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendError(status: 400, reason: "Bad Request", on: connection)
            return
        }
        let parts = requestLine.split(separator: " ").map(String.init)
        guard parts.count >= 2 else {
            sendError(status: 400, reason: "Bad Request", on: connection)
            return
        }
        let method = parts[0].uppercased()
        guard method == "GET" || method == "HEAD" else {
            sendError(status: 405, reason: "Method Not Allowed", on: connection)
            return
        }

        var headerMap: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            headerMap[key] = value
        }

        var target = parts[1]
        if target.lowercased().hasPrefix("http://") || target.lowercased().hasPrefix("https://") {
            if let url = URL(string: target) {
                target = url.path
            }
        }
        let pathOnly = target.components(separatedBy: "?").first ?? target
        let decoded = pathOnly.removingPercentEncoding ?? pathOnly
        guard decoded.hasPrefix("/") else {
            sendError(status: 400, reason: "Bad Request", on: connection)
            return
        }
        let relative = String(decoded.dropFirst())
        guard !relative.contains(".."), !relative.hasPrefix("."), !relative.contains("\\") else {
            sendError(status: 403, reason: "Forbidden", on: connection)
            return
        }

        let filename = relative.isEmpty ? "index.html" : relative
        let fileURL = rootDirectory.appendingPathComponent(filename).standardizedFileURL
        let rootPath = rootDirectory.path.hasSuffix("/") ? rootDirectory.path : rootDirectory.path + "/"
        guard fileURL.path.hasPrefix(rootPath) else {
            sendError(status: 403, reason: "Forbidden", on: connection)
            return
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            sendError(status: 404, reason: "Not Found", on: connection)
            return
        }

        var headers: [String: String] = [
            "Content-Type": Self.mimeType(forExtension: fileURL.pathExtension),
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*",
            "Accept-Ranges": "bytes",
            "Connection": "close"
        ]

        if let rangeHeader = headerMap["range"],
           let range = Self.parseRange(rangeHeader, totalLength: data.count) {
            let chunk = data.subdata(in: range)
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)"
            send(
                status: 206,
                reason: "Partial Content",
                headers: headers,
                body: method == "HEAD" ? Data() : chunk,
                contentLength: chunk.count,
                on: connection
            )
        } else {
            send(
                status: 200,
                reason: "OK",
                headers: headers,
                body: method == "HEAD" ? Data() : data,
                contentLength: data.count,
                on: connection
            )
        }
    }

    private func sendError(status: Int, reason: String, on connection: NWConnection) {
        let body = Data("\(status) \(reason)".utf8)
        let headers = [
            "Content-Type": "text/plain; charset=utf-8",
            "Cache-Control": "no-store",
            "Connection": "close"
        ]
        send(
            status: status,
            reason: reason,
            headers: headers,
            body: body,
            contentLength: body.count,
            on: connection
        )
    }

    private func send(
        status: Int,
        reason: String,
        headers: [String: String],
        body: Data,
        contentLength: Int,
        on connection: NWConnection
    ) {
        var response = "HTTP/1.1 \(status) \(reason)\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = String(contentLength)
        allHeaders["Date"] = Self.httpDate()
        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"
        var payload = Data(response.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static func parseRange(_ header: String, totalLength: Int) -> Range<Int>? {
        let lowered = header.lowercased()
        guard lowered.hasPrefix("bytes="), totalLength >= 0 else { return nil }
        let spec = String(header.dropFirst(6)).split(separator: ",").first.map(String.init) ?? ""
        let pieces = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 2 else { return nil }

        if pieces[0].isEmpty {
            guard let suffixLength = Int(pieces[1]), suffixLength > 0 else { return nil }
            let start = max(totalLength - suffixLength, 0)
            return start..<totalLength
        }
        guard let start = Int(pieces[0]), start >= 0, start < totalLength else { return nil }
        let requestedEnd = pieces[1].isEmpty ? totalLength - 1 : (Int(pieces[1]) ?? totalLength - 1)
        let end = min(max(requestedEnd, start), totalLength - 1)
        return start..<(end + 1)
    }

    static func mimeType(forExtension pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "webm": return "video/webm"
        default: return "application/octet-stream"
        }
    }

    private static func httpDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}
