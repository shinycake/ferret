import Darwin
import Foundation

enum UnixSocketAddress {
    static func make(_ path: String) throws -> sockaddr_un {
        guard path.utf8.count < 104 else {
            throw FSearchError.socketPathTooLong
        }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
            for (index, byte) in bytes.enumerated() {
                destination[index] = byte
            }
        }
        return address
    }

    static func withPointer<T>(_ address: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var address = address
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                body(socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}

public final class SocketTransport: FSearchTransport, @unchecked Sendable {
    private let path: String
    private let writeQueue = DispatchQueue(label: "com.shinycake.ferret.socket.write")
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var finished = false
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    public let lines: AsyncThrowingStream<Data, Error>

    public init(path: String) {
        self.path = path
        var captured: AsyncThrowingStream<Data, Error>.Continuation!
        self.lines = AsyncThrowingStream(bufferingPolicy: .unbounded) { captured = $0 }
        self.continuation = captured
    }

    deinit {
        close()
    }

    public func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.openSocket()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func send(line: Data) async throws {
        let fd = currentFD()
        guard fd >= 0 else { throw FSearchError.notConnected }
        var payload = line
        payload.append(0x0A)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writeQueue.async {
                OffMain.precondition()
                do {
                    try Self.writeAll(fd: fd, data: payload)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func close() {
        let fd = takeFD()
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        finish(nil)
    }

    private func openSocket() throws {
        OffMain.precondition()
        let address = try UnixSocketAddress.make(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FSearchError.notConnected }
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let connected = UnixSocketAddress.withPointer(address) { pointer, length in
            Darwin.connect(fd, pointer, length)
        }
        guard connected == 0 else {
            Darwin.close(fd)
            throw FSearchError.notConnected
        }
        lock.lock()
        self.fd = fd
        lock.unlock()
        let thread = Thread { [weak self] in
            self?.readLoop(fd: fd)
        }
        thread.name = "com.shinycake.ferret.socket.read"
        thread.start()
    }

    private func readLoop(fd: Int32) {
        OffMain.precondition()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var lines = LineBuffer()
        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fd, base, raw.count)
            }
            if count == 0 {
                finish(nil)
                return
            }
            if count < 0 {
                if errno == EINTR { continue }
                finish(FSearchError.transportClosed)
                return
            }
            for line in lines.append(Data(buffer.prefix(count))) {
                continuation.yield(line)
            }
        }
    }

    private func currentFD() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return fd
    }

    private func takeFD() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let current = fd
        fd = -1
        return current
    }

    private func finish(_ error: Error?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw FSearchError.transportClosed
            }
            if written == 0 {
                throw FSearchError.transportClosed
            }
            offset += written
        }
    }
}
