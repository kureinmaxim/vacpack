import Foundation

public struct Job: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let request: JobRequest

    /// Callers may create the ID themselves so they can map events to their own items
    /// before the first event arrives.
    public init(id: UUID = UUID(), request: JobRequest) {
        self.id = id
        self.request = request
    }
}

public enum QueueEvent: Sendable, Hashable {
    case queued(Job)
    case started(Job.ID)
    case progress(Job.ID, Double)
    case finished(Job.ID, JobOutcome)
    /// Pausing was requested and the last running job finished.
    case paused
    /// Nothing is pending or running.
    case idle
}

/// Runs jobs with bounded concurrency (SPEC §2 CPU limit, §8 queue).
///
/// Jobs can be added while others run. `pauseAfterCurrent()` lets running jobs finish and
/// starts no new ones until `resume()`. `cancelAll()` drops pending jobs and cancels running ones.
public actor JobQueue {
    public nonisolated let events: AsyncStream<QueueEvent>
    private let continuation: AsyncStream<QueueEvent>.Continuation
    private let processor: any JobProcessing
    private var maxConcurrent: Int
    private var pending: [Job] = []
    private var running: [Job.ID: Task<Void, Never>] = [:]
    private var isPaused = false

    public init(processor: any JobProcessing, maxConcurrent: Int = JobQueue.defaultConcurrency) {
        self.processor = processor
        self.maxConcurrent = max(1, maxConcurrent)
        (events, continuation) = AsyncStream.makeStream(of: QueueEvent.self, bufferingPolicy: .unbounded)
    }

    /// Half the cores, between 1 and 4: image encoders are themselves multi-threaded.
    public static var defaultConcurrency: Int {
        min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    public var pendingCount: Int { pending.count }
    public var runningCount: Int { running.count }
    public var paused: Bool { isPaused }

    @discardableResult
    public func enqueue(_ requests: [JobRequest]) -> [Job.ID] {
        let jobs = requests.map { Job(request: $0) }
        enqueue(jobs)
        return jobs.map(\.id)
    }

    public func enqueue(_ jobs: [Job]) {
        for job in jobs {
            pending.append(job)
            continuation.yield(.queued(job))
        }
        dispatch()
    }

    public func setMaxConcurrent(_ value: Int) {
        maxConcurrent = max(1, value)
        dispatch()
    }

    public func pauseAfterCurrent() {
        guard !isPaused else { return }
        isPaused = true
        if running.isEmpty { continuation.yield(.paused) }
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        dispatch()
        reportIdleIfDone()
    }

    public func cancelAll() {
        let dropped = pending
        pending.removeAll()
        for job in dropped { continuation.yield(.finished(job.id, .cancelled(input: job.request.input))) }
        for task in running.values { task.cancel() }
        reportIdleIfDone()
    }

    /// Removes one pending job; returns false if it already started or finished.
    @discardableResult
    public func remove(_ id: Job.ID) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return false }
        let job = pending.remove(at: index)
        continuation.yield(.finished(job.id, .cancelled(input: job.request.input)))
        reportIdleIfDone()
        return true
    }

    private func dispatch() {
        while !isPaused, running.count < maxConcurrent, !pending.isEmpty {
            let job = pending.removeFirst()
            continuation.yield(.started(job.id))
            let processor = self.processor
            let continuation = self.continuation
            running[job.id] = Task {
                let outcome = await processor.process(job.request) { fraction in
                    continuation.yield(.progress(job.id, fraction))
                }
                // The task inherits the actor's isolation, so this runs on the actor.
                self.finish(job.id, outcome: outcome)
            }
        }
    }

    private func finish(_ id: Job.ID, outcome: JobOutcome) {
        running[id] = nil
        continuation.yield(.finished(id, outcome))
        if isPaused, running.isEmpty { continuation.yield(.paused) }
        dispatch()
        reportIdleIfDone()
    }

    private func reportIdleIfDone() {
        if running.isEmpty, pending.isEmpty { continuation.yield(.idle) }
    }
}
