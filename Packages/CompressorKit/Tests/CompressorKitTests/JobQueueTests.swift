import Foundation
import Testing

@testable import CompressorKit

/// A processor that sleeps instead of compressing and records how many jobs ran at once.
final class FakeProcessor: JobProcessing, @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var peak = 0
    private(set) var processed: [URL] = []
    let duration: Duration

    init(duration: Duration = .milliseconds(50)) { self.duration = duration }

    func process(_ request: JobRequest, progress: @escaping @Sendable (Double) -> Void) async -> JobOutcome {
        lock.withLock {
            current += 1
            peak = max(peak, current)
        }
        defer { lock.withLock { current -= 1 } }
        progress(0.5)
        do {
            try await Task.sleep(for: duration)
        } catch {
            return .cancelled(input: request.input)
        }
        lock.withLock { processed.append(request.input) }
        return .keptOriginal(input: request.input, copiedTo: nil)
    }
}

/// Subscribes once to a queue's events (an `AsyncStream` ends when its iterator goes away,
/// so tests must not start a second `for await`) and lets tests wait for a condition.
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [QueueEvent] = []
    private var task: Task<Void, Never>?

    init(_ queue: JobQueue) {
        task = Task { [weak self] in
            for await event in queue.events {
                guard let self else { return }
                self.lock.withLock { self.log.append(event) }
            }
        }
    }

    deinit { task?.cancel() }

    var events: [QueueEvent] { lock.withLock { log } }

    /// Polls until `condition` holds for the events so far, or the timeout passes.
    func wait(timeout: Duration = .seconds(15), until condition: ([QueueEvent]) -> Bool) async -> [QueueEvent] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let snapshot = events
            if condition(snapshot) { return snapshot }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return events
    }
}

/// Starts recording, enqueues, and waits until `stop` holds.
func collect(_ recorder: EventRecorder, until stop: ([QueueEvent]) -> Bool) async -> [QueueEvent] {
    await recorder.wait(until: stop)
}

func finishedCount(_ events: [QueueEvent]) -> Int {
    events.filter { if case .finished = $0 { true } else { false } }.count
}

func requests(_ count: Int) -> [JobRequest] {
    (0..<count).map { JobRequest(input: URL(filePath: "/tmp/file\($0).jpg")) }
}

@Suite("JobQueue")
struct JobQueueTests {
    @Test func runsAllJobsWithBoundedConcurrency() async {
        let processor = FakeProcessor()
        let queue = JobQueue(processor: processor, maxConcurrent: 2)
        let recorder = EventRecorder(queue)
        await queue.enqueue(requests(6))
        let events = await collect(recorder) { $0.contains(.idle) }
        #expect(finishedCount(events) == 6)
        #expect(processor.peak == 2)
        #expect(processor.processed.count == 6)
        #expect(events.contains { if case .progress(_, 0.5) = $0 { true } else { false } })
    }

    @Test func acceptsJobsWhileRunning() async {
        let processor = FakeProcessor(duration: .milliseconds(100))
        let queue = JobQueue(processor: processor, maxConcurrent: 1)
        let recorder = EventRecorder(queue)
        await queue.enqueue(requests(1))
        try? await Task.sleep(for: .milliseconds(20))
        await queue.enqueue(requests(2))
        _ = await collect(recorder) { finishedCount($0) == 3 }
        #expect(processor.processed.count == 3)
    }

    @Test func pauseAfterCurrentThenResume() async {
        let processor = FakeProcessor(duration: .milliseconds(100))
        let queue = JobQueue(processor: processor, maxConcurrent: 1)
        let recorder = EventRecorder(queue)
        await queue.enqueue(requests(3))
        await queue.pauseAfterCurrent()
        let paused = await collect(recorder) { $0.contains(.paused) }
        #expect(finishedCount(paused) == 1)
        #expect(await queue.pendingCount == 2)

        await queue.resume()
        let all = await collect(recorder) { finishedCount($0) == 3 }
        #expect(finishedCount(all) == 3)
        #expect(processor.processed.count == 3)
    }

    @Test func cancelAllStopsRunningAndDropsPending() async {
        let processor = FakeProcessor(duration: .seconds(30))
        let queue = JobQueue(processor: processor, maxConcurrent: 2)
        let recorder = EventRecorder(queue)
        await queue.enqueue(requests(5))
        _ = await collect(recorder) { events in
            events.filter { if case .started = $0 { true } else { false } }.count == 2
        }
        let started = ContinuousClock.now
        await queue.cancelAll()
        let events = await collect(recorder) { finishedCount($0) == 5 }
        let cancelled = events.filter { if case .finished(_, .cancelled) = $0 { true } else { false } }
        #expect(cancelled.count == 5)
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(processor.processed.isEmpty)
    }

    @Test func removesPendingJob() async {
        let queue = JobQueue(processor: FakeProcessor(duration: .milliseconds(100)), maxConcurrent: 1)
        let recorder = EventRecorder(queue)
        let ids = await queue.enqueue(requests(3))
        #expect(await queue.remove(ids[2]))
        #expect(await queue.remove(ids[0]) == false, "already running")
        let events = await collect(recorder) { finishedCount($0) == 3 }
        #expect(events.contains(.finished(ids[2], .cancelled(input: URL(filePath: "/tmp/file2.jpg")))))
    }
}
