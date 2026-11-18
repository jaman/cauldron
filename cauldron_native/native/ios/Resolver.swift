import Foundation
#if !os(macOS)
import Network

enum Resolver {
    private static let monitor = NWPathMonitor()

    static func prepare(data: String) {
        let path = data + "/inetrc"
        let lines = ["{lookup, [file, dns]}.", "{host, {127,0,0,1}, [\"localhost\"]}."] +
            servers().compactMap(erlangAddress).map { "{nameserver, \($0)}." }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        setenv("ERL_INETRC", path, 1)
    }

    static func watch() {
        monitor.pathUpdateHandler = { _ in report() }
        monitor.start(queue: DispatchQueue(label: "cauldron.resolver"))
    }

    private static func report() {
        let quoted = servers().map { "\"\($0)\"" }.joined(separator: ",")
        let data = Data("{\"nameservers\":[\(quoted)]}".utf8)
        data.withUnsafeBytes { bytes in
            cn_network(bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
        }
    }

    static func servers() -> [String] {
        let state = UnsafeMutablePointer<__res_9_state>.allocate(capacity: 1)
        memset(state, 0, MemoryLayout<__res_9_state>.size)
        defer { state.deallocate() }
        guard res_9_ninit(state) == 0 else { return [] }
        defer { res_9_ndestroy(state) }
        var found = [res_9_sockaddr_union](repeating: res_9_sockaddr_union(), count: Int(MAXNS))
        let count = Int(res_9_getservers(state, &found, Int32(MAXNS)))
        return found.prefix(max(count, 0)).compactMap(numeric)
    }

    private static func numeric(_ server: res_9_sockaddr_union) -> String? {
        var server = server
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(server.sin.sin_family == UInt8(AF_INET6) ? MemoryLayout<sockaddr_in6>.size : MemoryLayout<sockaddr_in>.size)
        let result = withUnsafePointer(to: &server) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            }
        }
        guard result == 0 else { return nil }
        return String(cString: host).components(separatedBy: "%").first
    }

    private static func erlangAddress(_ text: String) -> String? {
        if text.contains(":") {
            var address = in6_addr()
            guard inet_pton(AF_INET6, text, &address) == 1 else { return nil }
            let bytes = withUnsafeBytes(of: address) { Array($0) }
            let parts = stride(from: 0, to: 16, by: 2).map { String(Int(bytes[$0]) << 8 | Int(bytes[$0 + 1])) }
            return "{" + parts.joined(separator: ",") + "}"
        }
        let parts = text.split(separator: ".")
        return parts.count == 4 ? "{" + parts.joined(separator: ",") + "}" : nil
    }
}
#endif
