import Darwin
import Foundation

public struct LocalBridgeDescriptor: Codable, Equatable, Sendable {
    public let version: Int
    public let socketPath: String
    public let sessionToken: String
    public let pid: Int32

    public init(version: Int, socketPath: String, sessionToken: String, pid: Int32) {
        self.version = version
        self.socketPath = socketPath
        self.sessionToken = sessionToken
        self.pid = pid
    }
}

public enum LocalBridgePaths {
    public static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexInnerIDE", isDirectory: true)
    }

    public static var socketURL: URL {
        directoryURL.appendingPathComponent("bridge-v1.sock")
    }

    public static var descriptorURL: URL {
        directoryURL.appendingPathComponent("bridge-v1.json")
    }
}

public final class LocalBridgeServer: @unchecked Sendable {
    public typealias Handler = @Sendable (BridgeRequest) async -> BridgeResponse
    public static let maximumFrameBytes = 1_048_576

    private let sessionToken: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.local.codex-inner-ide.local-bridge", qos: .userInitiated)
    private let lock = NSLock()
    private var listenerFD: Int32 = -1
    private var stopped = false

    public init(sessionToken: String, handler: @escaping Handler) {
        self.sessionToken = sessionToken
        self.handler = handler
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listenerFD < 0 else { return }
        stopped = false

        let directory = LocalBridgePaths.directoryURL
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        unlink(LocalBridgePaths.socketURL.path)
        try? FileManager.default.removeItem(at: LocalBridgePaths.descriptorURL)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
        do {
            var address = try unixAddress(path: LocalBridgePaths.socketURL.path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, unixAddressLength(path: LocalBridgePaths.socketURL.path))
                }
            }
            guard result == 0 else { throw posixError("bind") }
            guard Darwin.chmod(LocalBridgePaths.socketURL.path, 0o600) == 0 else {
                throw posixError("chmod")
            }
            guard Darwin.listen(fd, 8) == 0 else { throw posixError("listen") }
            listenerFD = fd
            try writeDescriptor()
        } catch {
            Darwin.close(fd)
            unlink(LocalBridgePaths.socketURL.path)
            throw error
        }

        queue.async { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        lock.lock()
        stopped = true
        let fd = listenerFD
        listenerFD = -1
        lock.unlock()
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        unlink(LocalBridgePaths.socketURL.path)
        try? FileManager.default.removeItem(at: LocalBridgePaths.descriptorURL)
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let fd = listenerFD
            let shouldStop = stopped
            lock.unlock()
            guard !shouldStop, fd >= 0 else { return }
            let client = Darwin.accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var peerUID: uid_t = 0
            var peerGID: gid_t = 0
            guard getpeereid(client, &peerUID, &peerGID) == 0, peerUID == geteuid() else {
                Darwin.close(client)
                continue
            }
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
            Task { [weak self] in await self?.serve(client) }
        }
    }

    private func serve(_ fd: Int32) async {
        defer { Darwin.close(fd) }
        do {
            let data = try SocketFrame.read(from: fd, maximumBytes: Self.maximumFrameBytes)
            let request = try JSONDecoder().decode(BridgeRequest.self, from: data)
            guard request.version == 1, request.sessionToken == sessionToken else {
                throw InnerIDEError.bridgeRejected("invalid local bridge session")
            }
            let response = await handler(request)
            try SocketFrame.write(JSONEncoder().encode(response), to: fd, maximumBytes: Self.maximumFrameBytes)
        } catch {
            let response = BridgeResponse.failure("invalid-request", error: error)
            if let data = try? JSONEncoder().encode(response) {
                try? SocketFrame.write(data, to: fd, maximumBytes: Self.maximumFrameBytes)
            }
        }
    }

    private func writeDescriptor() throws {
        let value = LocalBridgeDescriptor(
            version: 1,
            socketPath: LocalBridgePaths.socketURL.path,
            sessionToken: sessionToken,
            pid: getpid()
        )
        try JSONEncoder().encode(value).write(to: LocalBridgePaths.descriptorURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: LocalBridgePaths.descriptorURL.path
        )
    }
}

public struct LocalBridgeClient: Sendable {
    public static let maximumFrameBytes = LocalBridgeServer.maximumFrameBytes

    public init() {}

    public func request(method: String, params: JSONValue) throws -> JSONValue {
        let descriptor = try loadDescriptor()
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        defer { Darwin.close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
        var address = try unixAddress(path: descriptor.socketPath)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, unixAddressLength(path: descriptor.socketPath))
            }
        }
        guard connected == 0 else { throw posixError("connect") }
        let requestID = UUID().uuidString.lowercased()
        let request = BridgeRequest(
            version: 1,
            requestId: requestID,
            sessionToken: descriptor.sessionToken,
            method: method,
            params: params
        )
        try SocketFrame.write(
            JSONEncoder().encode(request),
            to: fd,
            maximumBytes: Self.maximumFrameBytes
        )
        let response = try JSONDecoder().decode(
            BridgeResponse.self,
            from: SocketFrame.read(from: fd, maximumBytes: Self.maximumFrameBytes)
        )
        guard response.requestId == requestID else {
            throw InnerIDEError.localBridgeUnavailable("response id did not match")
        }
        if response.ok { return response.data ?? .object([:]) }
        throw InnerIDEError.localBridgeUnavailable(response.error?.message ?? "request failed")
    }

    private func loadDescriptor() throws -> LocalBridgeDescriptor {
        let url = LocalBridgePaths.descriptorURL
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
              permissions & 0o077 == 0
        else { throw InnerIDEError.localBridgeUnavailable("session descriptor permissions are unsafe") }
        let descriptor = try JSONDecoder().decode(LocalBridgeDescriptor.self, from: Data(contentsOf: url))
        guard descriptor.version == 1,
              descriptor.socketPath == LocalBridgePaths.socketURL.path,
              descriptor.pid > 0,
              kill(descriptor.pid, 0) == 0
        else { throw InnerIDEError.localBridgeUnavailable("session descriptor is stale") }
        return descriptor
    }
}

private enum SocketFrame {
    static func read(from fd: Int32, maximumBytes: Int) throws -> Data {
        let header = try readExactly(fd: fd, count: 4)
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        guard length > 0, length <= maximumBytes else {
            throw InnerIDEError.localBridgeUnavailable("invalid frame length")
        }
        return try readExactly(fd: fd, count: Int(length))
    }

    static func write(_ data: Data, to fd: Int32, maximumBytes: Int) throws {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw InnerIDEError.localBridgeUnavailable("frame is too large")
        }
        var length = UInt32(data.count).bigEndian
        try withUnsafeBytes(of: &length) { try writeExactly(fd: fd, bytes: $0) }
        try data.withUnsafeBytes { try writeExactly(fd: fd, bytes: $0) }
    }

    private static func readExactly(fd: Int32, count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < count {
                let value = Darwin.read(fd, base.advanced(by: offset), count - offset)
                if value < 0, errno == EINTR { continue }
                guard value > 0 else { throw posixError("read") }
                offset += value
            }
        }
        return data
    }

    private static func writeExactly(fd: Int32, bytes: UnsafeRawBufferPointer) throws {
        guard let base = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let value = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
            if value < 0, errno == EINTR { continue }
            guard value > 0 else { throw posixError("write") }
            offset += value
        }
    }
}

private func unixAddress(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard path.utf8.count + 1 <= capacity else {
        throw InnerIDEError.localBridgeUnavailable("socket path is too long")
    }
    _ = path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                strncpy(destination, source, capacity - 1)
            }
        }
    }
    return address
}

private func unixAddressLength(path: String) -> socklen_t {
    let offset = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path) ?? 0
    return socklen_t(offset + path.utf8.count + 1)
}

private func unlink(_ path: String) {
    path.withCString { _ = Darwin.unlink($0) }
}

private func posixError(_ operation: String) -> InnerIDEError {
    InnerIDEError.localBridgeUnavailable("\(operation) failed: \(String(cString: strerror(errno)))")
}
