import CompressorKit
import Foundation
import Testing

@Suite("ProcessRunner")
struct ProcessRunnerTests {
    let runner = ProcessRunner(terminationGracePeriod: .milliseconds(500))
    let sh = URL(filePath: "/bin/sh")

    @Test func capturesStdoutAndExitCode() async throws {
        let result = try await runner.run(URL(filePath: "/bin/echo"), arguments: ["hello", "world"])
        #expect(result.exitCode == 0)
        #expect(result.stdoutString == "hello world\n")
        #expect(result.stderr.isEmpty)
    }

    @Test func passesArgumentsWithoutShellInterpretation() async throws {
        let tricky = "$HOME; rm -rf / | `id`"
        let result = try await runner.run(URL(filePath: "/bin/echo"), arguments: [tricky])
        #expect(result.stdoutString == tricky + "\n")
    }

    @Test func capturesStderrSeparately() async throws {
        let result = try await runner.run(sh, arguments: ["-c", "echo out; echo err >&2; exit 3"])
        #expect(result.exitCode == 3)
        #expect(result.stdoutString == "out\n")
        #expect(result.stderrString == "err\n")
    }

    @Test func deliversStdoutLinesAsTheyArrive() async throws {
        final class Lines: @unchecked Sendable {
            let lock = NSLock()
            var all: [String] = []
        }
        let lines = Lines()
        let result = try await runner.run(sh, arguments: ["-c", "printf 'one\\ntwo\\n'; sleep 0.1; printf 'three'"]) {
            line in lines.lock.withLock { lines.all.append(line) }
        }
        #expect(lines.lock.withLock { lines.all } == ["one", "two", "three"])
        #expect(result.stdoutString == "one\ntwo\nthree")
    }

    @Test func checkedThrowsOnNonZeroExit() async throws {
        let result = try await runner.run(URL(filePath: "/usr/bin/false"))
        #expect(throws: ProcessRunnerError.nonZeroExit(code: 1, stderr: "")) {
            try result.checked()
        }
    }

    @Test func drainsLargeOutputWithoutDeadlock() async throws {
        // Far more than a pipe buffer on both streams at once.
        let script = "head -c 2000000 /dev/zero; head -c 2000000 /dev/zero >&2"
        let result = try await runner.run(sh, arguments: ["-c", script], timeout: .seconds(20))
        #expect(result.stdout.count == 2_000_000)
        #expect(result.stderr.count == 2_000_000)
    }

    @Test func timeoutStopsProcess() async throws {
        let started = ContinuousClock.now
        await #expect(throws: ProcessRunnerError.timedOut(executable: "/bin/sleep")) {
            _ = try await runner.run(URL(filePath: "/bin/sleep"), arguments: ["30"], timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func cancellationStopsProcess() async throws {
        let started = ContinuousClock.now
        let task = Task {
            try await runner.run(URL(filePath: "/bin/sleep"), arguments: ["30"])
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func sigtermIgnoringProcessIsKilledAfterGracePeriod() async throws {
        let started = ContinuousClock.now
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await runner.run(sh, arguments: ["-c", "trap '' TERM; sleep 30"], timeout: .milliseconds(200))
        }
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    @Test func missingExecutableFailsToLaunch() async throws {
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await runner.run(URL(filePath: "/nonexistent/tool"))
        }
    }

    @Test func usesWorkingDirectoryAndEnvironment() async throws {
        let directory = FileManager.default.temporaryDirectory
        // `pwd -P` prints the physical path (/private/var/…), so compare against realpath.
        let physical = try #require(realpath(directory.path, nil))
        defer { free(physical) }
        let result = try await runner.run(
            sh, arguments: ["-c", "pwd -P; echo $GREETING"], environment: ["GREETING": "hi"],
            currentDirectory: directory)
        #expect(result.stdoutString == "\(String(cString: physical))\nhi\n")
    }

    @Test func grandchildHoldingPipesDoesNotHangTheResult() async throws {
        // The shell exits at once, but its background child keeps stdout open for 30 s.
        let started = ContinuousClock.now
        let result = try await runner.run(sh, arguments: ["-c", "echo done; sleep 30 &"])
        #expect(result.exitCode == 0)
        #expect(result.stdoutString == "done\n")
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}
