import Foundation

struct UsageQuota {
    let percentRemaining: Double
    let label: String
    let resetTime: String?
}

struct UsageSnapshot {
    let quotas: [UsageQuota]
    let activeModelName: String?
}

class AntigravityUsageProbe {
    static let shared = AntigravityUsageProbe()
    private let timeout: TimeInterval = 8.0

    func probe() async throws -> UsageSnapshot {
        // 1. Detect process
        let pgrepResult = try runCommand("/usr/bin/pgrep", args: ["-lf", "language_server"])
        let lines = pgrepResult.split(separator: "\n").map(String.init)
        
        var pid: Int?
        var csrfToken: String?
        var httpPort: Int?
        
        for line in lines {
            if line.contains("language_server_macos") || line.contains("language_server") {
                if let p = extractPID(from: line) { pid = p }
                if let c = extractFlag("--csrf_token", from: line) { csrfToken = c }
                if let hp = extractFlag("--extension_server_port", from: line).flatMap(Int.init) { httpPort = hp }
                if pid != nil && csrfToken != nil { break }
            }
        }
        
        guard let validPid = pid, let validCsrf = csrfToken else {
            throw NSError(domain: "ProbeError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Process or CSRF not found"])
        }
        
        // 2. Discover ports
        let lsofResult = try runCommand("/usr/sbin/lsof", args: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(validPid)])
        let ports = parseListeningPorts(from: lsofResult)
        
        // 3. Fetch
        var responseData: Data?
        for port in ports {
            if let data = try? await makeRequest(scheme: "https", port: port, path: "/exa.language_server_pb.LanguageServerService/GetUserStatus", csrfToken: validCsrf) {
                responseData = data
                break
            }
        }
        
        if responseData == nil, let hp = httpPort {
            if let data = try? await makeRequest(scheme: "http", port: hp, path: "/exa.language_server_pb.LanguageServerService/GetUserStatus", csrfToken: validCsrf) {
                responseData = data
            }
        }
        
        guard let data = responseData else {
            throw NSError(domain: "ProbeError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to API"])
        }
        
        // 4. Parse JSON
        return try parseResponse(data)
    }
    
    private func parseResponse(_ data: Data) throws -> UsageSnapshot {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        var quotas = [UsageQuota]()
        
        if let userStatus = json?["userStatus"] as? [String: Any],
           let cascadeModelConfigData = userStatus["cascadeModelConfigData"] as? [String: Any],
           let clientModelConfigs = cascadeModelConfigData["clientModelConfigs"] as? [[String: Any]] {
           
            for config in clientModelConfigs {
                if let label = config["label"] as? String,
                   let quotaInfo = config["quotaInfo"] as? [String: Any] {
                   
                    let remaining = (quotaInfo["remainingFraction"] as? Double) ?? 0.0
                    let reset = quotaInfo["resetTime"] as? String
                    
                    quotas.append(UsageQuota(percentRemaining: remaining * 100.0, label: label, resetTime: reset))
                }
            }
        }
        
        return UsageSnapshot(quotas: quotas, activeModelName: nil)
    }

    private func makeRequest(scheme: String, port: Int, path: String, csrfToken: String) async throws -> Data {
        let urlStr = "\(scheme)://127.0.0.1:\(port)\(path)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        
        let body: [String: Any] = [
            "metadata": [
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "ideVersion": "unknown",
                "locale": "en"
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        // We use a custom URLSession to bypass SSL cert errors on localhost
        let session = URLSession(configuration: .ephemeral, delegate: InsecureDelegate(), delegateQueue: nil)
        let (data, response) = try await session.data(for: request)
        
        guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
    
    private func runCommand(_ executable: String, args: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func extractPID(from line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if let first = parts.first { return Int(first) }
        return nil
    }
    
    private func extractFlag(_ flag: String, from command: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: flag))[=\\s]+([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = regex.firstMatch(in: command, options: [], range: range),
              let tokenRange = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[tokenRange])
    }
    
    private func parseListeningPorts(from output: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var SetPorts: Set<Int> = []
        regex.enumerateMatches(in: output, options: [], range: range) { match, _, _ in
            if let match = match,
               let r = Range(match.range(at: 1), in: output),
               let val = Int(output[r]) {
                SetPorts.insert(val)
            }
        }
        return SetPorts.sorted()
    }
}

class InsecureDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
