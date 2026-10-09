import CryptoKit
import Foundation

/// Client for OP.GG's public MCP endpoint (JSON-RPC over HTTP), the source of popular builds,
/// runes, counters and champion stats. Responses are cached in memory and on disk
/// for a few hours since the aggregates only change between patches.
actor OPGGClient {
    static let shared = OPGGClient()

    enum OPGGError: LocalizedError {
        case server(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .server(let message): "OP.GG: \(message)"
            case .badResponse: "OP.GG returned an unexpected response"
            }
        }
    }

    private let endpoint = URL(string: "https://mcp-api.op.gg/mcp")!
    private let ttl: TimeInterval = 6 * 3600
    private var memory: [String: (date: Date, data: Data)] = [:]
    private var inFlight: [String: Task<Data, Error>] = [:]
    private var requestID = 0

    /// Calls a tool and returns its payload as JSON data. OP.GG answers some tools in a compact
    /// "class notation" instead of JSON; that's converted so callers can always use Codable.
    func call(tool: String, arguments: [String: String], fields: [String] = []) async throws -> Data {
        let key = Self.cacheKey(tool: tool, arguments: arguments, fields: fields)
        if let hit = memory[key], Date().timeIntervalSince(hit.date) < ttl { return hit.data }
        if let disk = DiskCache.read(key: key, maxAge: ttl) {
            memory[key] = (Date(), disk)
            return disk
        }
        if let running = inFlight[key] { return try await running.value }

        requestID += 1
        let id = requestID
        let task = Task { try await Self.perform(endpoint: endpoint, id: id, tool: tool, arguments: arguments, fields: fields) }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let data = try await task.value
        memory[key] = (Date(), data)
        DiskCache.write(key: key, data: data)
        return data
    }

    private static func perform(endpoint: URL, id: Int, tool: String, arguments: [String: String], fields: [String]) async throws -> Data {
        var args: [String: Any] = arguments
        if !fields.isEmpty { args["desired_output_fields"] = fields }
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": "tools/call",
            "params": ["name": tool, "arguments": args],
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var (data, _) = try await URLSession.shared.data(for: request)
        // Streamable-HTTP servers may answer as server-sent events; take the `data:` line.
        if let text = String(data: data, encoding: .utf8), text.hasPrefix("event:") || text.hasPrefix("data:") {
            let line = text.split(separator: "\n").first { $0.hasPrefix("data:") }
            data = Data((line?.dropFirst(5) ?? "").utf8)
        }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if let error = envelope.error { throw OPGGError.server(error.message) }
        guard let text = envelope.result?.content?.first?.text else { throw OPGGError.badResponse }
        if envelope.result?.isError == true { throw OPGGError.server(String(text.prefix(200))) }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return Data(trimmed.utf8)
        }
        let object = try ClassNotationParser.parse(trimmed)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private static func cacheKey(tool: String, arguments: [String: String], fields: [String]) -> String {
        let raw = tool + "|" + arguments.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            + "|" + fields.joined(separator: ",")
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct Envelope: Decodable {
        var result: Result?
        var error: RPCError?
        struct Result: Decodable {
            var content: [Content]?
            var isError: Bool?
        }
        struct Content: Decodable {
            var text: String?
        }
        struct RPCError: Decodable {
            var message: String
        }
    }
}

enum DiskCache {
    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Recall/opgg", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func read(key: String, maxAge: TimeInterval) -> Data? {
        guard let url = directory?.appendingPathComponent(key + ".json"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge else { return nil }
        return try? Data(contentsOf: url)
    }

    static func write(key: String, data: Data) {
        guard let url = directory?.appendingPathComponent(key + ".json") else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Parses OP.GG's compact responses, which declare field names once and then use positional
/// constructors:
///
///     class Data: damage_type,boots
///     class Boots: ids,pick_rate
///
///     Root(Data("AP",Boots([3020],0.58)))
///
/// into JSON-compatible dictionaries/arrays keyed by the declared field names.
struct ClassNotationParser {
    enum ParseError: Error { case unexpected(String) }

    private var schemas: [String: [String]] = [:]
    private let bytes: [UInt8]
    private var index = 0

    static func parse(_ text: String) throws -> Any {
        var schemas: [String: [String]] = [:]
        var body: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("class "), let colon = line.firstIndex(of: ":") {
                let name = line[line.index(line.startIndex, offsetBy: 6)..<colon].trimmingCharacters(in: .whitespaces)
                let fields = line[line.index(after: colon)...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                schemas[name] = fields
            } else {
                body.append(line)
            }
        }
        var parser = ClassNotationParser(schemas: schemas, bytes: Array(body.joined(separator: "\n").utf8))
        let value = try parser.parseValue()
        return value
    }

    private init(schemas: [String: [String]], bytes: [UInt8]) {
        self.schemas = schemas
        self.bytes = bytes
    }

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func skipWhitespace() {
        while let c = current, c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 { index += 1 }
    }

    private mutating func parseValue() throws -> Any {
        skipWhitespace()
        guard let c = current else { throw ParseError.unexpected("end of input") }
        switch c {
        case UInt8(ascii: "\""): return try parseString()
        case UInt8(ascii: "["): return try parseList()
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return parseNumber()
        default: return try parseIdentifier()
        }
    }

    private mutating func parseString() throws -> Any {
        let start = index
        index += 1
        while let c = current, c != UInt8(ascii: "\"") {
            index += c == UInt8(ascii: "\\") ? 2 : 1
        }
        index += 1
        let raw = Data(bytes[start..<min(index, bytes.count)])
        if let decoded = try? JSONSerialization.jsonObject(with: raw, options: .fragmentsAllowed) as? String {
            return decoded
        }
        return String(decoding: raw.dropFirst().dropLast(), as: UTF8.self)
    }

    private mutating func parseList() throws -> Any {
        index += 1
        var values: [Any] = []
        skipWhitespace()
        if current == UInt8(ascii: "]") {
            index += 1
            return values
        }
        while true {
            values.append(try parseValue())
            skipWhitespace()
            guard let c = current else { throw ParseError.unexpected("unterminated list") }
            index += 1
            if c == UInt8(ascii: "]") { return values }
            if c != UInt8(ascii: ",") { throw ParseError.unexpected("in list") }
        }
    }

    private mutating func parseNumber() -> Any {
        let start = index
        while let c = current, (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9"))
                || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".")
                || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") {
            index += 1
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        if let int = Int(text) { return int }
        return Double(text) ?? 0
    }

    private mutating func parseIdentifier() throws -> Any {
        let start = index
        while let c = current, (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
                || (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
                || (c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9")) || c == UInt8(ascii: "_") {
            index += 1
        }
        let name = String(decoding: bytes[start..<index], as: UTF8.self)
        guard !name.isEmpty else { throw ParseError.unexpected("character at \(index)") }
        skipWhitespace()

        guard current == UInt8(ascii: "(") else {
            switch name {
            case "None", "null", "nil": return NSNull()
            case "True", "true": return true
            case "False", "false": return false
            default: return name
            }
        }

        index += 1
        var args: [Any] = []
        skipWhitespace()
        if current == UInt8(ascii: ")") {
            index += 1
        } else {
            while true {
                args.append(try parseValue())
                skipWhitespace()
                guard let c = current else { throw ParseError.unexpected("unterminated \(name)") }
                index += 1
                if c == UInt8(ascii: ")") { break }
                if c != UInt8(ascii: ",") { throw ParseError.unexpected("in \(name)") }
            }
        }

        let fields = schemas[name] ?? []
        var object: [String: Any] = [:]
        for (i, value) in args.enumerated() where i < fields.count {
            object[fields[i]] = value
        }
        return object
    }
}
