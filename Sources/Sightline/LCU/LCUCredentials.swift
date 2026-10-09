import Foundation

/// Port + password for the League Client's local REST API (the "LCU API").
struct LCUCredentials: Equatable, Sendable {
    let port: Int
    let password: String

    var authorizationHeader: String {
        "Basic " + Data("riot:\(password)".utf8).base64EncodedString()
    }
}

enum LCUCredentialsLocator {
    static let defaultInstallPath = "/Applications/League of Legends.app"

    /// Finds a running client. The lockfile is a cheap file read, so it's tried first; scanning
    /// the process list (which spawns `ps`) is only done when asked, as a fallback for a client
    /// installed somewhere other than /Applications. A stale lockfile just fails to connect.
    static func locate(scanProcesses: Bool) -> LCUCredentials? {
        if let credentials = fromLockfile() { return credentials }
        return scanProcesses ? fromRunningProcess() : nil
    }

    static func fromRunningProcess() -> LCUCredentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-ww", "-o", "args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)

        for line in output.split(separator: "\n") where line.contains("LeagueClientUx") {
            if let port = argument("--app-port=", in: line).flatMap(Int.init),
               let token = argument("--remoting-auth-token=", in: line) {
                return LCUCredentials(port: port, password: token)
            }
        }
        return nil
    }

    /// Lockfile format: `name:pid:port:password:protocol`
    static func fromLockfile(installPath: String = defaultInstallPath) -> LCUCredentials? {
        let path = installPath + "/Contents/LoL/lockfile"
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let parts = contents.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count >= 5, let port = Int(parts[2]) else { return nil }
        return LCUCredentials(port: port, password: String(parts[3]))
    }

    private static func argument(_ flag: String, in line: Substring) -> String? {
        guard let range = line.range(of: flag) else { return nil }
        let value = line[range.upperBound...].prefix { !$0.isWhitespace && $0 != "\"" }
        return value.isEmpty ? nil : String(value)
    }
}
