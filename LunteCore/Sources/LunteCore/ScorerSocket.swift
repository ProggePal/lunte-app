// The hook hands a prompt to the app's model over a local socket (contract §2). Prompt text never touches disk.
import Foundation

public enum ScorerSocket {
    /// Next to the log: ~/Library/Application Support/Lunte/scorer.sock, or beside $LUNTE_LOG.
    public static var url: URL { EventLog.defaultURL.deletingLastPathComponent().appendingPathComponent("scorer.sock") }

    /// One JSON line {"ts", "text"} to the app, if it's listening. Never waits: false when nobody is there.
    public static func send(ts: Double, text: String, to url: URL = url) -> Bool {
        guard var addr = address(url),
              let body = try? JSONSerialization.data(withJSONObject: ["ts": ts, "text": String(text.prefix(4000))]) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return false }
        let line = body + Data("\n".utf8)
        return line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == line.count
    }

    /// A listening socket for the app, readable only by you. Returns the fd, or -1.
    public static func listen(at url: URL = url) -> Int32 {
        guard var addr = address(url) else { return -1 }
        unlink(url.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(url.path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else { close(fd); return -1 }
        return fd
    }

    static func address(_ url: URL) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(url.path.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil } // macOS caps it at 104 bytes
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in path.withUnsafeBytes { dst.copyMemory(from: $0) } }
        return addr
    }
}
