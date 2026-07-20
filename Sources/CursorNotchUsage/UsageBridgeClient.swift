import Foundation

enum UsageBridgeError: LocalizedError {
    case bridgeMissing
    case badResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .bridgeMissing:
            "Usage bridge not found. Run npm install in bridge/ first."
        case .badResponse:
            "Unexpected response from usage bridge."
        case .server(let message):
            message
        }
    }
}

actor UsageBridgeClient {
    private static let port = 4318
    private static let requiredAPIVersion = 1
    private var process: Process?

    private nonisolated var baseURL: URL {
        URL(string: "http://127.0.0.1:\(Self.port)")!
    }

    func ensureRunning() async throws {
        if try await healthOK() { return }
        stop()
        if try await healthOK() { return }
        if await isPortInUse() {
            throw UsageBridgeError.server(
                "Port \(Self.port) is already in use. Stop the other process first."
            )
        }

        let bridgeDir = try resolveBridgeDirectory()
        let entry = bridgeDir.appendingPathComponent("dist/index.js")
        let fallback = bridgeDir.appendingPathComponent("src/index.ts")

        let process = Process()
        process.currentDirectoryURL = bridgeDir
        var environment = ProcessInfo.processInfo.environment
        if let nodeBin = Self.resolveNodeBinDirectory() {
            let path = environment["PATH"] ?? "/usr/bin:/bin"
            environment["PATH"] = "\(nodeBin):\(path)"
        }
        process.environment = environment

        guard let node = Self.resolveNodeExecutable() else {
            throw UsageBridgeError.server("Node.js not found. Install Node 22.13+.")
        }

        let nodeQuiet = ["--disable-warning=ExperimentalWarning"]
        if FileManager.default.fileExists(atPath: entry.path) {
            process.executableURL = URL(fileURLWithPath: node)
            process.arguments = nodeQuiet + [entry.path]
        } else if FileManager.default.fileExists(atPath: fallback.path) {
            let tsx = bridgeDir.appendingPathComponent("node_modules/tsx/dist/cli.mjs").path
            guard FileManager.default.fileExists(atPath: tsx) else {
                throw UsageBridgeError.bridgeMissing
            }
            process.executableURL = URL(fileURLWithPath: node)
            process.arguments = nodeQuiet + [tsx, fallback.path]
        } else {
            throw UsageBridgeError.bridgeMissing
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        self.process = process

        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(150))
            if try await healthOK() { return }
            if !process.isRunning {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let log = String(data: data, encoding: .utf8) ?? "Bridge exited"
                throw UsageBridgeError.server(log)
            }
        }

        throw UsageBridgeError.server("Bridge did not become ready in time")
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    func listSnapshot() async throws -> BridgeSnapshot {
        var request = URLRequest(url: baseURL.appendingPathComponent("usage"))
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 1.2
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UsageBridgeError.badResponse
        }
        return try Self.decodeSnapshot(data)
    }

    func streamSnapshots() -> AsyncThrowingStream<BridgeSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    do {
                        var request = URLRequest(url: baseURL.appendingPathComponent("events"))
                        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                        request.timeoutInterval = 60 * 60
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            throw UsageBridgeError.badResponse
                        }

                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            guard line.hasPrefix("data: ") else { continue }
                            let payload = String(line.dropFirst(6))
                            guard let data = payload.data(using: .utf8) else { continue }
                            continuation.yield(try Self.decodeSnapshot(data))
                        }
                    } catch {
                        if Task.isCancelled { break }
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func isPortInUse() async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-iTCP:\(Self.port)", "-sTCP:LISTEN"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func healthOK() async throws -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 0.4
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let version = (json?["apiVersion"] as? NSNumber)?.intValue
                ?? (json?["apiVersion"] as? Int)
                ?? 0
            return version >= Self.requiredAPIVersion
        } catch {
            return false
        }
    }

    private func resolveBridgeDirectory() throws -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var candidates = [
            cwd.appendingPathComponent("bridge"),
            cwd.appendingPathComponent("../bridge"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/bridge"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("bridge"),
        ]
        if let resourceBridge = Bundle.main.resourceURL?.appendingPathComponent("bridge") {
            candidates.insert(resourceBridge, at: 0)
        }

        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("package.json").path) {
                return candidate.standardizedFileURL
            }
        }

        let fileURL = URL(fileURLWithPath: #filePath)
        var dir = fileURL.deletingLastPathComponent()
        for _ in 0..<6 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("bridge/package.json").path) {
                return dir.appendingPathComponent("bridge").standardizedFileURL
            }
            dir = dir.deletingLastPathComponent()
        }

        throw UsageBridgeError.bridgeMissing
    }

    private nonisolated static func resolveNodeExecutable() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["NODE_BINARY"],
            "/usr/local/bin/node",
            "/opt/homebrew/bin/node",
        ].compactMap { $0 }
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        if let bin = resolveNodeBinDirectory() {
            let nested = bin + "/node"
            if FileManager.default.isExecutableFile(atPath: nested) { return nested }
        }
        return nil
    }

    private nonisolated static func resolveNodeBinDirectory() -> String? {
        let nvmRoot = NSHomeDirectory() + "/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) else {
            return nil
        }
        let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
        for version in sorted {
            let bin = "\(nvmRoot)/\(version)/bin"
            if FileManager.default.isExecutableFile(atPath: bin + "/node") { return bin }
        }
        return nil
    }

    private nonisolated static func decodeSnapshot(_ data: Data) throws -> BridgeSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageBridgeError.badResponse
        }
        return BridgeSnapshot(usage: Self.decodeUsage(json["usage"] as? [String: Any]))
    }

    private nonisolated static func decodeUsage(_ json: [String: Any]?) -> CursorUsageSummary? {
        guard let json else { return nil }
        let label = json["label"] as? String ?? ""
        guard !label.isEmpty else { return nil }
        return CursorUsageSummary(
            membership: json["membership"] as? String ?? "",
            totalPercentUsed: number(json["totalPercentUsed"]) ?? 0,
            autoPercentUsed: number(json["autoPercentUsed"]) ?? 0,
            apiPercentUsed: number(json["apiPercentUsed"]) ?? 0,
            includedSpendCents: Int(number(json["includedSpendCents"]) ?? 0),
            limitCents: Int(number(json["limitCents"]) ?? 0),
            remainingCents: Int(number(json["remainingCents"]) ?? 0),
            cycleRemainingLabel: json["cycleRemainingLabel"] as? String ?? "",
            label: label
        )
    }

    private nonisolated static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }
}
