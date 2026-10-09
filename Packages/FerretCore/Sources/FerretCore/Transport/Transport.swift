import Foundation

public protocol FSearchTransport: AnyObject, Sendable {
    func connect() async throws
    /// Sends one JSON object. The transport appends the trailing newline.
    func send(line: Data) async throws
    var lines: AsyncThrowingStream<Data, Error> { get }
    func close()
}

struct LineBuffer {
    private var pending = Data()

    mutating func append(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = Data(pending.prefix(upTo: newline))
            pending.removeSubrange(..<pending.index(after: newline))
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}

enum OffMain {
    static func precondition() {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
    }
}
