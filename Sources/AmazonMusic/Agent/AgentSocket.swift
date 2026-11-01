import Darwin
import Foundation
import OSLog
import os

/// A Unix domain socket that only this Mac user can open. The app listens; the CLI connects,
/// sends one JSON line (at most 64 KB) and reads one JSON line back.
///   ~/Library/Application Support/AmazonMusic/agent.sock   the real app (directory 0700, socket 0600)
///   APP_AGENT_SOCKET=<path>                                any other place (tests)
/// Security: socket created under umask 0177 then chmod 0600; the server checks the peer's uid
/// with getpeereid and refuses anyone but the current user; request bodies are never logged.
nonisolated enum AgentSocket {
    static let maxRequestBytes = 64 * 1024
    static let maxReplyBytes = 4 * 1024 * 1024
    private static let log = Logger(subsystem: "com.khalidabuhakmeh.amazonmusic", category: "agent")

    static var isOverridden: Bool {
        let env = ProcessInfo.processInfo.environment
        return !(env["APP_AGENT_SOCKET"] ?? "").isEmpty || !(env["APP_STORE"] ?? "").isEmpty
    }

    static var path: String {
        let env = ProcessInfo.processInfo.environment
        if let path = env["APP_AGENT_SOCKET"], !path.isEmpty { return path }
        if let store = env["APP_STORE"], !store.isEmpty { return store + ".sock" }
        return defaultDirectory.appending(path: "agent.sock").path
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "AmazonMusic", directoryHint: .isDirectory)
    }

    private static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw AgentError.invalid("socket path is too long (over 103 bytes). Set APP_AGENT_SOCKET to a shorter path")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    private static func connectClient(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = try? address(path) else { if fd >= 0 { close(fd) }; return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return nil }
        return fd
    }

    private static func peerIsCurrentUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    // MARK: App side

    /// Removes a leftover socket file only if it is a socket we own and nothing is listening on it.
    /// Returns false when the path must not be used.
    static func clearStale(_ path: String) -> Bool {
        var info = stat()
        if lstat(path, &info) != 0 { return errno == ENOENT }
        guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid() else {
            log.error("agent socket path exists and is not our socket; not touching it")
            return false
        }
        if let live = connectClient(path) {
            close(live)
            log.notice("another instance is already listening on the agent socket")
            return false
        }
        return unlink(path) == 0
    }

    /// Starts listening. `handle` runs on the main actor for each request.
    static func listen(handle: @escaping @MainActor @Sendable (Data) async -> Data) {
        let path = self.path
        if !isOverridden {
            let dir = defaultDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            chmod(dir.path, 0o700)
        }
        guard clearStale(path), var addr = try? address(path) else { return }
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0 else { return }
        let previous = umask(0o177) // so the socket is never created group/world accessible
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(previous)
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(server, 16) == 0 else {
            log.error("could not listen on agent socket: \(String(cString: strerror(errno)), privacy: .public)")
            close(server)
            unlink(path)
            return
        }
        let limits = Limits.standard
        Thread.detachNewThread { acceptLoop(server, limits: limits, handle: handle) }
    }

    /// Limits for the server side. Tests pass smaller ones.
    struct Limits: Sendable {
        var maxConnections = 8
        var readDeadline: TimeInterval = 10
        var writeDeadline: TimeInterval = 10
        static let standard = Limits()
    }

    /// Accepts forever. Over the cap, the new connection gets a one-line "busy" error and is closed;
    /// no thread is created for it.
    static func acceptLoop(_ server: Int32, limits: Limits, handle: @escaping @MainActor @Sendable (Data) async -> Data) {
        let limiter = ConnectionLimiter(limit: limits.maxConnections)
        while true {
            let client = accept(server, nil, nil)
            if client < 0 {
                if errno == EBADF || errno == EINVAL { return }
                if errno == EINTR || errno == ECONNABORTED { continue }
                usleep(100_000)
                continue
            }
            guard limiter.acquire() else {
                rejectBusy(client)
                continue
            }
            Thread.detachNewThread {
                defer { limiter.release() }
                serve(client, limits: limits, handle: handle)
            }
        }
    }

    private static func rejectBusy(_ client: Int32) {
        defer { close(client) }
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) | O_NONBLOCK)
        let line = JSON.data(AgentError(code: "busy", message: "the app has too many open agent connections. Try again in a moment", exit: 1).json) + Data("\n".utf8)
        line.withUnsafeBytes { _ = Darwin.write(client, $0.baseAddress!, $0.count) } // best effort, never blocks
    }

    private final class ReplyBox: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var data: Data?
        func set(_ value: Data) { lock.lock(); data = value; lock.unlock(); semaphore.signal() }
        func wait(seconds: Int) -> Data? {
            guard semaphore.wait(timeout: .now() + .seconds(seconds)) == .success else { return nil }
            lock.lock(); defer { lock.unlock() }
            return data
        }
    }

    private static func serve(_ client: Int32, limits: Limits, handle: @escaping @MainActor @Sendable (Data) async -> Data) {
        defer { close(client) }
        guard peerIsCurrentUser(client) else {
            log.error("rejected a connection from another user")
            return
        }
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) | O_NONBLOCK)
        guard let request = readLine(client, limit: maxRequestBytes, deadline: Deadline(after: limits.readDeadline)), !request.isEmpty else {
            write(client, JSON.data(AgentError.usage("request must be one JSON line of at most 64 KB").json) + Data("\n".utf8), deadline: Deadline(after: min(limits.writeDeadline, 2)))
            return
        }
        let box = ReplyBox()
        Task { @MainActor in box.set(await handle(request)) }
        let reply = box.wait(seconds: 30) ?? JSON.data(AgentError.invalid("the app did not answer in time").json)
        write(client, reply + Data("\n".utf8), deadline: Deadline(after: limits.writeDeadline))
    }

    // MARK: CLI side

    /// Sends one request and returns the reply. Starts the app when it is not running, unless `launch` is false.
    static func send(_ request: Data, launch: Bool) throws -> Data {
        guard request.count <= maxRequestBytes else { throw AgentError.usage("request is larger than 64 KB") }
        if let reply = try exchange(request) { return reply }
        guard launch else { throw AgentError.unavailable("Amazon Music is not running. Open it, or leave out --no-launch") }
        try startApp()
        for _ in 0..<50 {
            Thread.sleep(forTimeInterval: 0.2)
            if let reply = try exchange(request) { return reply }
        }
        throw AgentError.unavailable("Amazon Music did not answer within 10 seconds on \(path)")
    }

    /// nil when nobody is listening.
    private static func exchange(_ request: Data) throws -> Data? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        guard (info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid == getuid() else {
            throw AgentError.unavailable("\(path) is not a socket owned by you; refusing to connect")
        }
        guard let client = connectClient(path) else { return nil }
        defer { close(client) }
        guard peerIsCurrentUser(client) else { throw AgentError.unavailable("the socket is served by another user; refusing to talk to it") }
        write(client, request + Data("\n".utf8))
        var timeout = timeval(tv_sec: 35, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard let reply = readLine(client, limit: maxReplyBytes), !reply.isEmpty else { throw AgentError.invalid("the app sent no answer") }
        return reply
    }

    /// Opens the app in the background, with this process's environment for tests.
    private static func startApp() throws {
        let executable = AgentBinary.url
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        guard bundle.pathExtension == "app" else {
            throw AgentError.unavailable("Amazon Music is not running and this binary is not inside an .app. Open the app first")
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var arguments = ["-g", bundle.path]
        if let override = ProcessInfo.processInfo.environment["APP_AGENT_SOCKET"], !override.isEmpty {
            // A test run: its own copy, with its own socket.
            arguments = ["-g", "-n", "--env", "APP_AGENT_SOCKET=\(override)", bundle.path]
        }
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw AgentError.unavailable("could not start Amazon Music: \(error.localizedDescription)") }
    }

    // MARK: Bytes

    /// One line, without the newline. nil when more than `limit` bytes arrive.
    static func readLine(_ socket: Int32, limit: Int) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = read(socket, &buffer, buffer.count)
            if count <= 0 { break }
            if let newline = buffer[0..<count].firstIndex(of: UInt8(ascii: "\n")) {
                data.append(buffer, count: newline)
                break
            }
            data.append(buffer, count: count)
            if data.count > limit { return nil }
        }
        return data.count > limit ? nil : data
    }

    /// Writes everything or gives up. With a deadline the socket must be non-blocking.
    private static func write(_ socket: Int32, _ data: Data, deadline: Deadline? = nil) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let sent = Darwin.write(socket, raw.baseAddress! + offset, raw.count - offset)
                if sent > 0 { offset += sent; continue }
                guard let deadline, sent < 0, errno == EAGAIN || errno == EINTR else { return }
                if errno == EAGAIN, !deadline.wait(socket, events: Int16(POLLOUT)) { return }
                if deadline.isExpired { return }
            }
        }
    }

    /// Like `readLine`, but the whole line must arrive before `deadline`, however slowly it trickles.
    /// The socket must be non-blocking. nil when too long or too slow.
    static func readLine(_ socket: Int32, limit: Int, deadline: Deadline) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = read(socket, &buffer, buffer.count)
            if count < 0, errno == EAGAIN || errno == EINTR {
                if deadline.isExpired || (errno == EAGAIN && !deadline.wait(socket, events: Int16(POLLIN))) { return nil }
                continue
            }
            if count <= 0 { break }
            if let newline = buffer[0..<count].firstIndex(of: UInt8(ascii: "\n")) {
                data.append(buffer, count: newline)
                break
            }
            data.append(buffer, count: count)
            if data.count > limit { return nil }
            if deadline.isExpired { return nil }
        }
        return data.count > limit ? nil : data
    }
}


/// A wall-clock limit on a monotonic clock.
nonisolated struct Deadline: Sendable {
    let end: ContinuousClock.Instant
    init(after seconds: TimeInterval) { end = .now + .milliseconds(Int(max(0, seconds) * 1000)) }

    var remaining: Duration { max(.zero, end - .now) }
    var isExpired: Bool { ContinuousClock.now >= end }

    /// Waits until `events` are ready on `fd` or the deadline passes. false on timeout.
    func wait(_ fd: Int32, events: Int16) -> Bool {
        let left = remaining
        let ms = Int32(min(Int64(1000), left.components.seconds * 1000 + left.components.attoseconds / 1_000_000_000_000_000))
        guard ms > 0 || !isExpired else { return false }
        var item = pollfd(fd: fd, events: events, revents: 0)
        _ = poll(&item, 1, max(1, ms))
        return !isExpired || item.revents != 0
    }
}

/// Counts open connections and refuses new ones over the limit.
nonisolated final class ConnectionLimiter: Sendable {
    let limit: Int
    private let count = OSAllocatedUnfairLock(initialState: 0)
    init(limit: Int) { self.limit = limit }

    func acquire() -> Bool {
        count.withLock { value in
            guard value < limit else { return false }
            value += 1
            return true
        }
    }
    func release() { count.withLock { $0 = max(0, $0 - 1) } }
    var active: Int { count.withLock { $0 } }
}
