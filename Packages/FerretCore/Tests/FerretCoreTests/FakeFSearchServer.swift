import Darwin
import Foundation
@testable import FerretCore

final class FakeFSearchServer: @unchecked Sendable {
    enum Behavior: Sendable {
        case normal
        case reorderPairs
        case silent
        case staleBeforeReal
        case indexingStatus
    }

    let path: String
    private var listenFD: Int32 = -1
    private let lock = NSLock()
    private var clientFDs: [Int32] = []
    private var acceptedCount = 0
    private var recordedRequests: [Data] = []
    private var recordedResponseIDs: [Int] = []
    private var currentBehavior: Behavior = .normal
    private var contentDelaySeconds: TimeInterval = 0

    var behavior: Behavior {
        get { lock.lock(); defer { lock.unlock() }; return currentBehavior }
        set { lock.lock(); currentBehavior = newValue; lock.unlock() }
    }

    var contentDelay: TimeInterval {
        get { lock.lock(); defer { lock.unlock() }; return contentDelaySeconds }
        set { lock.lock(); contentDelaySeconds = newValue; lock.unlock() }
    }

    var accepted: Int {
        lock.lock()
        defer { lock.unlock() }
        return acceptedCount
    }

    var requests: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    var responseIDs: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recordedResponseIDs
    }

    init(path fixedPath: String? = nil) throws {
        let suffix = UUID().uuidString.prefix(8)
        path = fixedPath ?? "/tmp/fc-\(getpid())-\(suffix).sock"
        if fixedPath != nil { unlink(path) }
        let address = try UnixSocketAddress.make(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FakeServerError("socket errno \(errno)") }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let bound = UnixSocketAddress.withPointer(address) { pointer, length in
            Darwin.bind(fd, pointer, length)
        }
        guard bound == 0 else {
            Darwin.close(fd)
            throw FakeServerError("bind errno \(errno) path \(path)")
        }
        guard Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            throw FakeServerError("listen errno \(errno)")
        }
        listenFD = fd
        let thread = Thread {
            self.acceptLoop()
        }
        thread.name = "fake-fsearch-accept"
        thread.start()
    }

    deinit {
        stop()
    }

    func stop() {
        lock.lock()
        let listen = listenFD
        listenFD = -1
        let clients = clientFDs
        clientFDs.removeAll()
        lock.unlock()
        if listen >= 0 {
            Darwin.shutdown(listen, SHUT_RDWR)
            Darwin.close(listen)
        }
        for fd in clients {
            Darwin.shutdown(fd, SHUT_RDWR)
        }
        Darwin.unlink(path)
    }

    func dropClients() {
        lock.lock()
        let clients = clientFDs
        lock.unlock()
        for fd in clients {
            Darwin.shutdown(fd, SHUT_RDWR)
        }
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let listen = listenFD
            lock.unlock()
            if listen < 0 { return }
            let fd = Darwin.accept(listen, nil, nil)
            if fd < 0 { return }
            var noSigPipe: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            lock.lock()
            acceptedCount += 1
            clientFDs.append(fd)
            lock.unlock()
            Thread {
                self.serve(fd)
            }.start()
        }
    }

    private func serve(_ fd: Int32) {
        var buffer = Data()
        var pair: [Data] = []
        while let line = readLine(fd: fd, buffer: &buffer) {
            record(line)
            let behavior = behavior
            let delay = contentDelay
            if behavior == .silent {
                continue
            }
            if behavior == .reorderPairs {
                pair.append(line)
                if pair.count < 2 { continue }
                writeResponse(for: pair[1], fd: fd, stale: false, delay: delay)
                writeResponse(for: pair[0], fd: fd, stale: false, delay: 0)
                pair.removeAll()
                continue
            }
            if behavior == .staleBeforeReal {
                var nullID = Data(#"{"ok":true,"id":null,"took_us":1,"hits":[]}"#.utf8)
                nullID.append(0x0A)
                _ = writeAll(fd: fd, data: nullID)
                writeResponse(for: line, fd: fd, stale: true, delay: 0)
            }
            writeResponse(for: line, fd: fd, stale: false, delay: delay)
        }
        lock.lock()
        clientFDs.removeAll { $0 == fd }
        lock.unlock()
        Darwin.close(fd)
    }

    private func record(_ line: Data) {
        lock.lock()
        recordedRequests.append(line)
        lock.unlock()
    }

    private func writeResponse(for line: Data, fd: Int32, stale: Bool, delay: TimeInterval) {
        let text = String(data: line, encoding: .utf8) ?? ""
        let shouldDelay = delay > 0 && (text.contains("grep:") || text.contains("per_file"))
        if shouldDelay {
            Thread.sleep(forTimeInterval: delay)
        }
        guard let payload = responseData(for: line, stale: stale) else { return }
        if let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let id = object["id"] as? Int {
            lock.lock()
            recordedResponseIDs.append(id)
            lock.unlock()
        }
        var packet = payload
        packet.append(0x0A)
        _ = writeAll(fd: fd, data: packet)
    }

    private func responseData(for line: Data, stale: Bool) -> Data? {
        let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
        let id: Any = stale ? 999_999 : (object["id"] ?? NSNull())
        let op = object["op"] as? String
        let query = object["q"] as? String ?? ""
        let behavior = behavior
        let body: [String: Any]
        if stale {
            body = [
                "ok": true,
                "took_us": 1,
                "hits": [["path": "/stale", "kind": "file", "size": 1, "mtime": 1, "score": 1]],
                "id": id,
            ]
        } else if behavior == .indexingStatus && op == "status" {
            body = [
                "ok": false,
                "error": "indexing (first run scans the whole disk, ~20s)",
                "id": id,
            ]
        } else if op == "ping" {
            body = ["ok": true, "id": id]
        } else if op == "save" {
            body = ["ok": true, "scheduled": true, "id": id]
        } else if op == "status" {
            body = [
                "ok": true,
                "entries": 3,
                "dirs": 1,
                "overlay": 0,
                "removed": 0,
                "event_id": 9,
                "index_bytes": 10,
                "content_docs": 0,
                "content_segments": 0,
                "content_bytes": 0,
                "content_pending": 0,
                "full_disk_access": false,
                "owner": true,
                "id": id,
            ]
        } else if query.contains("grep:") {
            let match: [String: Any] = ["line": 4, "text": query]
            let file: [String: Any] = ["path": "/tmp/grep", "matches": [match]]
            body = [
                "ok": true,
                "took_us": 1000,
                "source": "scan",
                "candidates": 1,
                "read": 1,
                "complete": true,
                "indexing": 0,
                "files": [file],
                "id": id,
            ]
        } else {
            let hit: [String: Any] = [
                "path": "/result/\(query)",
                "kind": "file",
                "size": 1,
                "mtime": 1,
                "score": 1,
            ]
            body = ["ok": true, "took_us": 20, "hits": [hit], "id": id]
        }
        return try? JSONSerialization.data(withJSONObject: body)
    }

    private func readLine(fd: Int32, buffer: inout Data) -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer.prefix(upTo: newline))
                buffer.removeSubrange(..<buffer.index(after: newline))
                if line.isEmpty { continue }
                return line
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = chunk.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base, raw.count)
            }
            if count <= 0 { return nil }
            buffer.append(contentsOf: chunk.prefix(count))
        }
    }

    private func writeAll(fd: Int32, data: Data) -> Bool {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            if written == 0 { return false }
            offset += written
        }
        return true
    }
}

struct FakeServerError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

final class SocketPathFactory: FSearchTransportFactory, @unchecked Sendable {
    let path: String
    init(path: String) { self.path = path }
    func makeTransport(lane: FSearchClient.Lane) -> any FSearchTransport {
        SocketTransport(path: path)
    }
}
