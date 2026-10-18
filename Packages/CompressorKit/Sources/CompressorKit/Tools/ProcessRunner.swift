import Foundation

/// Output of one finished external process.
public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }

    /// Returns `self` when the process exited with status 0, otherwise throws `nonZeroExit`.
    public func checked() throws -> ProcessResult {
        guard exitCode == 0 else {
            throw ProcessRunnerError.nonZeroExit(code: exitCode, stderr: stderrString)
        }
        return self
    }
}

public enum ProcessRunnerError: Error, Equatable, CustomStringConvertible {
    case launchFailed(executable: String, reason: String)
    case timedOut(executable: String)
    case nonZeroExit(code: Int32, stderr: String)

    public var description: String {
        switch self {
        case let .launchFailed(executable, reason): "Could not launch \(executable): \(reason)"
        case let .timedOut(executable): "\(executable) did not finish in time and was stopped"
        case let .nonZeroExit(code, stderr): "Process exited with status \(code): \(stderr)"
        }
    }
}

/// Runs external tools without a shell: the executable is an absolute URL and
/// arguments are passed as an array, so shell aliases and quoting never apply.
public struct ProcessRunner: Sendable {
    /// Time between SIGTERM and SIGKILL when a process is stopped.
    public var terminationGracePeriod: Duration

    public init(terminationGracePeriod: Duration = .seconds(2)) {
        self.terminationGracePeriod = terminationGracePeriod
    }

    /// Runs the process to completion. A non-zero exit status is returned, not thrown;
    /// call `checked()` on the result when failure should throw.
    ///
    /// Task cancellation and `timeout` stop the process (SIGTERM, then SIGKILL).
    public func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: Duration? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let handle = RunningProcess(process, gracePeriod: terminationGracePeriod)
        let timeoutTask = timeout.map { limit in
            Task {
                try await Task.sleep(for: limit)
                handle.stop(reason: .timeout)
            }
        }
        defer { timeoutTask?.cancel() }

        let result = try await withTaskCancellationHandler {
            try await handle.launchAndWait(stdout: stdoutPipe, stderr: stderrPipe)
        } onCancel: {
            handle.stop(reason: .cancellation)
        }

        switch handle.stopReason {
        case .cancellation: throw CancellationError()
        case .timeout: throw ProcessRunnerError.timedOut(executable: executable.path)
        case nil: return result
        }
    }
}

/// Owns one `Process` and makes launching and stopping it safe from any thread.
private final class RunningProcess: @unchecked Sendable {
    enum StopReason { case cancellation, timeout }

    private let process: Process
    private let gracePeriod: Duration
    private let lock = NSLock()
    private var launched = false
    private var _stopReason: StopReason?

    init(_ process: Process, gracePeriod: Duration) {
        self.process = process
        self.gracePeriod = gracePeriod
    }

    var stopReason: StopReason? { lock.withLock { _stopReason } }

    func launchAndWait(stdout: Pipe, stderr: Pipe) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            // Drain both pipes as data arrives so a chatty process never blocks on a full pipe.
            let endOfStreams = DispatchGroup()
            let out = StreamCollector(stdout, group: endOfStreams)
            let err = StreamCollector(stderr, group: endOfStreams)

            let launchError: Error? = lock.withLock {
                // Stopped before launch: do not start the process at all.
                switch _stopReason {
                case .cancellation: return CancellationError()
                case .timeout:
                    return ProcessRunnerError.timedOut(executable: process.executableURL?.path ?? "?")
                case nil: break
                }
                do {
                    try process.run()
                    launched = true
                    return nil
                } catch {
                    return ProcessRunnerError.launchFailed(
                        executable: process.executableURL?.path ?? "?",
                        reason: error.localizedDescription)
                }
            }
            if let launchError {
                _ = out.finish()
                _ = err.finish()
                continuation.resume(throwing: launchError)
                return
            }

            DispatchQueue.global(qos: .utility).async { [process] in
                process.waitUntilExit()
                // The pipes normally close when the process exits. A grandchild it spawned may
                // still hold them open, so wait for end of stream only briefly.
                _ = endOfStreams.wait(timeout: .now() + .seconds(1))
                continuation.resume(
                    returning: ProcessResult(
                        exitCode: process.terminationStatus, stdout: out.finish(), stderr: err.finish()))
            }
        }
    }

    func stop(reason: StopReason) {
        let pid: pid_t? = lock.withLock {
            if _stopReason == nil { _stopReason = reason }
            return launched && process.isRunning ? process.processIdentifier : nil
        }
        guard let pid else { return }
        kill(pid, SIGTERM)
        let grace = gracePeriod
        Task.detached { [process] in
            try? await Task.sleep(for: grace)
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}

/// Collects one pipe's output; leaves `group` once at end of stream or on `finish()`.
private final class StreamCollector: @unchecked Sendable {
    private let handle: FileHandle
    private let group: DispatchGroup
    private let lock = NSLock()
    private var buffer = Data()
    private var finished = false

    init(_ pipe: Pipe, group: DispatchGroup) {
        handle = pipe.fileHandleForReading
        self.group = group
        group.enter()
        handle.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
    }

    private func consume(_ chunk: Data) {
        lock.withLock {
            guard !finished else { return }
            if chunk.isEmpty {
                close()
            } else {
                buffer.append(chunk)
            }
        }
    }

    /// Stops reading and returns everything collected so far.
    func finish() -> Data {
        lock.withLock {
            if !finished { close() }
            return buffer
        }
    }

    /// Caller holds `lock`.
    private func close() {
        finished = true
        handle.readabilityHandler = nil
        group.leave()
    }
}
