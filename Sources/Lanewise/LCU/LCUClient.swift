import Foundation

enum LocalAPIError: LocalizedError {
    case badURL
    case http(Int, String)
    case noData
    case notConnected

    var errorDescription: String? {
        switch self {
        case .badURL: "Invalid request URL"
        case .http(let status, let body): "HTTP \(status): \(body)"
        case .noData: "The client returned no data for this player"
        case .notConnected: "Not connected to the League client"
        }
    }
}

/// The League client (LCU) and the game (Live Client Data API) both serve HTTPS on
/// 127.0.0.1 with a certificate signed by Riot's private root CA. Trust is relaxed for
/// loopback only; every other host goes through normal validation.
final class LoopbackTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           space.host == "127.0.0.1",
           let trust = space.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

extension URLSession {
    static let loopback: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config, delegate: LoopbackTrustDelegate(), delegateQueue: nil)
    }()
}

/// Thin client for the League Client Update (LCU) REST API.
final class LCUClient: @unchecked Sendable {
    let credentials: LCUCredentials

    init(credentials: LCUCredentials) {
        self.credentials = credentials
    }

    func data(_ path: String, timeout: TimeInterval? = nil) async throws -> Data {
        guard let url = URL(string: "https://127.0.0.1:\(credentials.port)\(path)") else {
            throw LocalAPIError.badURL
        }
        var request = URLRequest(url: url)
        if let timeout { request.timeoutInterval = timeout }
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.loopback.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw LocalAPIError.http(status, String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }

    /// Writes to the client. Only used for the explicit, user-confirmed rune page apply.
    @discardableResult
    func send(_ method: String, _ path: String, json: Any? = nil) async throws -> Data {
        guard let url = URL(string: "https://127.0.0.1:\(credentials.port)\(path)") else {
            throw LocalAPIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed])
        }
        let (data, response) = try await URLSession.loopback.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw LocalAPIError.http(status, String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self, timeout: TimeInterval? = nil) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await data(path, timeout: timeout))
    }

    /// Like `get`, but returns nil on any failure. Used where an endpoint is best-effort.
    func fetch<T: Decodable>(_ path: String, as type: T.Type = T.self) async -> T? {
        try? await get(path, as: T.self)
    }

    static func queryEscape(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
