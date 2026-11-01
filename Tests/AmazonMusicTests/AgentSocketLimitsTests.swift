import Darwin
import Foundation
import Testing
@testable import AmazonMusic

struct AgentSocketLimitsTests {
    @Test func limiterRespectsCapAndReleases() {
        let limiter = ConnectionLimiter(limit: 3)
        #expect((0..<3).allSatisfy { _ in limiter.acquire() })
        #expect(!limiter.acquire())
        #expect(limiter.active == 3)
        limiter.release()
        #expect(limiter.acquire())
        for _ in 0..<10 { limiter.release() }
        #expect(limiter.active == 0)
    }

    @Test func limiterIsThreadSafe() async {
        let limiter = ConnectionLimiter(limit: 5)
        let granted = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 { group.addTask { limiter.acquire() } }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        #expect(granted == 5)
    }

    @Test func deadlineExpires() async throws {
        let deadline = Deadline(after: 0.2)
        let first = deadline.remaining
        #expect(!deadline.isExpired)
        try await Task.sleep(for: .milliseconds(50))
        #expect(deadline.remaining < first)
        try await Task.sleep(for: .milliseconds(250))
        #expect(deadline.isExpired)
        #expect(deadline.remaining == .zero)
        #expect(Deadline(after: 0).isExpired)
    }

    // MARK: Server

    private func startServer(_ limits: AgentSocket.Limits) throws -> (path: String, fd: Int32) {
        let path = "/tmp/amz-\(UInt32.random(in: 0..<UInt32.max)).sock"
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(bound == 0 && listen(fd, 64) == 0)
        Thread.detachNewThread {
            AgentSocket.acceptLoop(fd, limits: limits) { _ in Data(#"{"ok":true}"#.utf8) }
        }
        return (path, fd)
    }

    private func connectTo(_ path: String) -> Int32 {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        return fd
    }

    /// Reads until EOF or `seconds` pass. Returns (bytes, closed).
    private func drain(_ fd: Int32, seconds: Double) -> (String, Bool) {
        var out = Data()
        let end = Date().addingTimeInterval(seconds)
        var buf = [UInt8](repeating: 0, count: 512)
        while Date() < end {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            if poll(&p, 1, 50) > 0 {
                let n = read(fd, &buf, buf.count)
                if n <= 0 { return (String(decoding: out, as: UTF8.self), true) }
                out.append(buf, count: n)
            }
        }
        return (String(decoding: out, as: UTF8.self), false)
    }

    @Test func extraIdleConnectionsAreRejectedPromptly() throws {
        let limits = AgentSocket.Limits(maxConnections: 4, readDeadline: 3, writeDeadline: 3)
        let (path, server) = try startServer(limits)
        defer { close(server); unlink(path) }
        let clients = (0..<8).map { _ in connectTo(path) }
        defer { clients.forEach { close($0) } }
        var busy = 0
        for fd in clients {
            let (text, closed) = drain(fd, seconds: 0.5)
            if closed, text.contains("\"busy\"") { busy += 1 }
        }
        #expect(busy == 4)
        // Idle ones are dropped after the read deadline.
        for fd in clients {
            let (_, closed) = drain(fd, seconds: 4)
            #expect(closed)
        }
    }

    @Test func slowTrickleIsDroppedAtTotalDeadline() throws {
        let limits = AgentSocket.Limits(maxConnections: 4, readDeadline: 2, writeDeadline: 2)
        let (path, server) = try startServer(limits)
        defer { close(server); unlink(path) }
        let fd = connectTo(path)
        defer { close(fd) }
        let start = Date()
        var dropped = false
        while Date().timeIntervalSince(start) < 6 {
            if write(fd, "x", 1) < 0 { dropped = true; break }
            let (_, closed) = drain(fd, seconds: 0.5)
            if closed { dropped = true; break }
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(dropped)
        #expect(elapsed >= 1.8 && elapsed < 4.5)
    }

    @Test func normalRequestStillAnswered() throws {
        let (path, server) = try startServer(AgentSocket.Limits())
        defer { close(server); unlink(path) }
        let fd = connectTo(path)
        defer { close(fd) }
        _ = write(fd, "{\"command\":\"x\"}\n", 16)
        let (text, _) = drain(fd, seconds: 2)
        #expect(text.contains("\"ok\":true"))
    }
}
