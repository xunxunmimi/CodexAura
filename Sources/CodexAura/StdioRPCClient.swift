// Copyright © 2026 CC (@xunxunmimi). See LICENSE and NOTICE.
import Darwin
import Foundation

/// A bounded stdio connection. Raw server errors/stderr never reach the UI.
final class StdioRPCClient {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]
    private let deadline: TimeInterval
    private var closed = false
    private let maximumBuffer = 1_048_576

    init(executable: URL, environment: [String: String], timeout: TimeInterval = 12) throws {
        deadline = ProcessInfo.processInfo.systemUptime + timeout
        process.executableURL = executable
        process.arguments = ["app-server"] // Documented default stdio transport.
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() } catch { throw UsageError.launchFailed }
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        for handle in [output.fileHandleForReading, errors.fileHandleForReading] {
            let descriptor = handle.fileDescriptor
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        }
    }

    deinit { close() }

    func send(id: Int? = nil, method: String, params: Any = NSNull()) throws {
        var object: [String: Any] = ["method": method, "params": params]
        if let id { object["id"] = id }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw UsageError.disconnected }
    }

    func response(id: Int, method: String, timeout: TimeInterval = 4) throws -> [String: Any] {
        let requestDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + timeout)
        while true {
            if let object = responses.removeValue(forKey: id) {
                if let error = object["error"] as? [String: Any] {
                    throw UsageError.rpc(method: method, code: (error["code"] as? NSNumber)?.intValue ?? -1)
                }
                guard let result = object["result"] as? [String: Any] else { throw UsageError.malformedResponse }
                return result
            }
            guard ProcessInfo.processInfo.systemUptime < requestDeadline else { throw UsageError.timeout }
            try receive(timeout: min(requestDeadline - ProcessInfo.processInfo.systemUptime, 0.1))
        }
    }

    private func receive(timeout: TimeInterval) throws {
        var descriptors = [
            pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0),
            pollfd(fd: errors.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
        ]
        let status = descriptors.withUnsafeMutableBufferPointer {
            poll($0.baseAddress, nfds_t($0.count), Int32(max(timeout, 0) * 1_000))
        }
        if status < 0, errno != EINTR { throw UsageError.disconnected }
        for index in descriptors.indices where descriptors[index].revents != 0 {
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptors[index].fd, $0.baseAddress, $0.count) }
            if index == 1 { continue } // Drain stderr; discard potentially sensitive messages.
            if count == 0 { throw UsageError.disconnected }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                throw UsageError.disconnected
            }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= maximumBuffer else { throw UsageError.malformedResponse }
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = (object["id"] as? NSNumber)?.intValue,
                      (1...4).contains(id) else { continue }
                responses[id] = object
            }
        }
        if !process.isRunning, buffer.isEmpty, responses.isEmpty { throw UsageError.disconnected }
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let until = ProcessInfo.processInfo.systemUptime + 0.3
            while process.isRunning, ProcessInfo.processInfo.systemUptime < until { usleep(10_000) }
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
        }
        try? output.fileHandleForReading.close()
        try? errors.fileHandleForReading.close()
    }
}
