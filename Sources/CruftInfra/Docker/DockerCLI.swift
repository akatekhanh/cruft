import Foundation

/// Thin wrapper around the `docker` CLI. Scanning issues read-only commands
/// (`version`, `system df`); removal commands take exactly one object per call and
/// never pass `--force` for anything that could hold data, so Docker's own safety
/// checks (e.g. "volume is in use") still apply.
public struct DockerCLI: Sendable {
    public let binaryPath: String

    /// Fails (returns nil) when no docker binary exists on this machine.
    /// GUI apps don't inherit the shell PATH, so we probe the usual homes.
    public init?(binaryPath: String? = nil) {
        if let binaryPath {
            self.binaryPath = binaryPath
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            home + "/.docker/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/usr/bin/docker",
        ]
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }
        self.binaryPath = found
    }

    public struct CommandError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Runs `docker <args>`, returns stdout. Throws with docker's stderr on a
    /// non-zero exit. A watchdog terminates the process after `timeout` seconds
    /// (a hung daemon otherwise blocks the scan forever).
    @discardableResult
    public func run(_ args: [String], timeout: TimeInterval = 60) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        // Drain pipes before waiting — a full pipe buffer deadlocks waitUntilExit.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        guard process.terminationStatus == 0 else {
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw CommandError(message: message.isEmpty
                ? "docker exited with status \(process.terminationStatus)" : message)
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }

    /// True when the Docker daemon answers (Docker Desktop running).
    public func isDaemonReachable() -> Bool {
        (try? run(["version", "--format", "{{.Server.Version}}"], timeout: 6)) != nil
    }

    /// Full disk-usage inventory as one JSON document. `system df -v` walks
    /// container filesystems, so give it a generous timeout.
    public func systemDF() throws -> String {
        try run(["system", "df", "-v", "--format", "{{json .}}"], timeout: 120)
    }

    public func removeImage(_ ref: String) throws { try run(["rmi", ref]) }
    public func removeContainer(_ id: String) throws { try run(["rm", id]) }
    public func removeVolume(_ name: String) throws { try run(["volume", "rm", name]) }
    public func pruneBuildCache() throws { try run(["builder", "prune", "-f"], timeout: 300) }
}
