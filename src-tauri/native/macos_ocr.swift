import Foundation

// Foundation-only coordination: no AppKit/clipboard/screenshot operations or
// borrowed C-ABI buffers run here. An admitted closure owns its immutable image
// and request. At most one work call and one cancel call can be outstanding.
enum NativeOCRPhase: String {
    case workerAdmitted, workerStarted, callerWaiting, handlerCreationStarted, handlerCreated
    case requestCreationStarted, requestCreated
    case languageQueryStarted, languageQueryReturned, recognitionConfigured
    case performStarted, visionCompletionDelivered, performReturned, layoutCompleted
    case callerCancelled, deadlineFired, visionCancelQueued, visionCancelStarted, visionCancelReturned
    case workerFinished, workerReleased
}

enum NativeOCRStop: String { case cancelled, deadline }
enum NativeOCRWorkError: Error { case busy, cancelled, timedOut }

private final class NativeOCRWorkBody: @unchecked Sendable {
    private var action: ((NativeOCRJob) throws -> String)?
    init(_ action: @escaping (NativeOCRJob) throws -> String) { self.action = action }
    func run(_ job: NativeOCRJob) -> Result<String, Error> {
        let work = action; action = nil
        do { try job.checkStopped(); return .success(try work!(job)) }
        catch { return .failure(error) }
    }
}

private final class NativeOCRCancelBody: @unchecked Sendable {
    private var action: (() -> Void)?
    init(_ action: @escaping () -> Void) { self.action = action }
    func run() { let cancel = action; action = nil; cancel?() }
}

final class NativeOCRDomain: @unchecked Sendable {
    static let shared = NativeOCRDomain()
    private let lock = NSLock()
    private let workQueue = DispatchQueue(label: "EchoLingo.Vision.work", qos: .userInitiated)
    private let cancelQueue = DispatchQueue(label: "EchoLingo.Vision.cancel", qos: .utility)
    private var active: NativeOCRJob?
    private var sequence: UInt64 = 0
    private var lastDrained: [String: Any]?
    private let clock: () -> TimeInterval

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    // Reserve BEFORE displaying another selector. Repeated shortcuts do not
    // enqueue images or threads behind an unresponsive Vision request.
    func reserve(observer: @escaping (NativeOCRPhase) -> Void = { _ in }) throws -> NativeOCRJob {
        lock.lock()
        guard active == nil else { lock.unlock(); throw NativeOCRWorkError.busy }
        sequence &+= 1
        let job = NativeOCRJob(id: sequence, clock: clock, workQueue: workQueue, cancelQueue: cancelQueue,
                               observer: observer, drained: { [weak self] job in self?.release(job) })
        active = job
        lock.unlock()
        job.observe(.workerAdmitted)
        return job
    }

    private func release(_ job: NativeOCRJob) {
        job.observe(.workerReleased)
        let snapshot = job.snapshot()
        lock.lock()
        if active === job { active = nil; lastDrained = snapshot }
        lock.unlock()
    }

    func snapshot() -> [String: Any] {
        lock.lock(); let job = active; let previous = lastDrained; lock.unlock()
        if let job { return job.snapshot() }
        return ["state": "idle", "lastDrained": previous ?? [:]]
    }
}

final class NativeOCRJob: @unchecked Sendable {
    private let condition = NSLock()
    private let wake = DispatchSemaphore(value: 0)
    private let workQueue: DispatchQueue
    private let cancelQueue: DispatchQueue
    private let observer: (NativeOCRPhase) -> Void
    private let drained: (NativeOCRJob) -> Void
    private var started = false
    private var workFinished = false
    private var released = false
    private var stop: NativeOCRStop?
    private var result: Result<String, Error>?
    private var cancelAction: (() -> Void)?
    private var cancelScheduled = false
    private var cancelReturned = false
    private let id: UInt64
    private let admittedAtUnixMs = UInt64(Date().timeIntervalSince1970 * 1000)
    private let clock: () -> TimeInterval
    private let admittedAt: TimeInterval
    private var startedAt: TimeInterval?
    private var deadline: TimeInterval?
    private var events: [[String: Any]] = []
    private var configuration: [String: Any] = [:]
    private var latestPhase = NativeOCRPhase.workerAdmitted

    fileprivate init(id: UInt64, clock: @escaping () -> TimeInterval, workQueue: DispatchQueue, cancelQueue: DispatchQueue,
                     observer: @escaping (NativeOCRPhase) -> Void,
                     drained: @escaping (NativeOCRJob) -> Void) {
        self.id = id; self.clock = clock; self.admittedAt = clock()
        self.workQueue = workQueue; self.cancelQueue = cancelQueue
        self.observer = observer; self.drained = drained
    }

    func observe(_ phase: NativeOCRPhase) {
        condition.lock()
        latestPhase = phase
        if events.count == 48 { events.removeFirst() }
        events.append(["phase": phase.rawValue,
                       "elapsedMs": (clock() - admittedAt) * 1000,
                       "mainThread": Thread.isMainThread])
        condition.unlock()
        observer(phase)
    }

    var isStopped: Bool { condition.lock(); defer { condition.unlock() }; return stop != nil }
    func checkStopped() throws {
        condition.lock()
        let expired = deadline.map { clock() >= $0 } ?? false
        condition.unlock()
        if expired { cancel(.deadline) }
        condition.lock(); let reason = stop; condition.unlock()
        if let reason { throw reason == .deadline ? NativeOCRWorkError.timedOut : NativeOCRWorkError.cancelled }
    }

    // Capture failure/cancellation before hand-off returns the reserved slot.
    // Once started, only actual worker + cancellation completion can release it.
    func releaseReservation() {
        condition.lock()
        guard !started, !released else { condition.unlock(); return }
        workFinished = true
        let release = releaseIfDrainedLocked()
        condition.unlock()
        if release { drained(self) }
    }

    func start(timeout: TimeInterval = 30, _ work: @escaping (NativeOCRJob) throws -> String) throws {
        condition.lock()
        guard !started, !released else { condition.unlock(); throw NativeOCRWorkError.busy }
        if let reason = stop {
            condition.unlock()
            throw reason == .deadline ? NativeOCRWorkError.timedOut : NativeOCRWorkError.cancelled
        }
        started = true
        // Keep the 30-second budget, but start it after screenshot cleanup
        // BEFORE any Vision work. Unlike the old cancel-only timer, this also
        // bounds caller waiting during handler/request construction and queries.
        startedAt = clock()
        deadline = startedAt! + timeout
        condition.unlock()
        let body = NativeOCRWorkBody(work)
        workQueue.async {
            self.observe(.workerStarted)
            // run() releases the captured image/work closure before finish()
            // can make the slot available to another request.
            let outcome = body.run(self)
            self.finish(outcome)
        }
    }

    // Binding after a cancellation remembers that intent. The worker checks
    // it before perform, and the actual cancel call is never made on a caller,
    // watcher, UI thread, or while holding a capture/clipboard lock.
    func bindCancellation(_ action: @escaping () -> Void) {
        condition.lock()
        guard !workFinished else { condition.unlock(); return }
        cancelAction = action
        let pending = scheduleCancellationLocked()
        condition.unlock()
        if let pending { dispatchCancellation(pending) }
    }

    func clearCancellation() {
        condition.lock(); cancelAction = nil; condition.unlock()
    }

    func cancel(_ reason: NativeOCRStop = .cancelled) {
        condition.lock()
        // Normal end-native-capture cleanup after a completed job must not
        // enqueue a late cancel call against a request that has already ended.
        guard !workFinished, stop == nil else { condition.unlock(); return }
        stop = reason
        result = nil
        let pending = scheduleCancellationLocked()
        wake.signal()
        condition.unlock()
        observe(reason == .deadline ? .deadlineFired : .callerCancelled)
        if let pending { dispatchCancellation(pending) }
    }

    private func scheduleCancellationLocked() -> (() -> Void)? {
        guard stop != nil, !cancelScheduled, let action = cancelAction else { return nil }
        cancelScheduled = true
        return action
    }

    private func dispatchCancellation(_ action: @escaping () -> Void) {
        observe(.visionCancelQueued)
        let body = NativeOCRCancelBody(action)
        cancelQueue.async {
            self.observe(.visionCancelStarted)
            // Drop the request-retaining closure before releasing admission.
            body.run()
            self.observe(.visionCancelReturned)
            self.condition.lock()
            self.cancelReturned = true
            let release = self.releaseIfDrainedLocked()
            self.wake.signal()
            self.condition.unlock()
            if release { self.drained(self) }
        }
    }

    private func finish(_ outcome: Result<String, Error>) {
        observe(.workerFinished)
        condition.lock()
        workFinished = true
        cancelAction = nil
        // Finishing after the monotonic deadline cannot publish a late value,
        // even if the waiting caller has not yet been scheduled to run.
        let expired = stop == nil && deadline.map { clock() >= $0 } == true
        if expired { stop = .deadline }
        // Never retain a late recognized string after the caller abandoned it.
        if stop == nil { result = outcome }
        let release = releaseIfDrainedLocked()
        wake.signal()
        condition.unlock()
        if expired { observe(.deadlineFired) }
        if release { drained(self) }
    }

    private func releaseIfDrainedLocked() -> Bool {
        guard workFinished, (!cancelScheduled || cancelReturned), !released else { return false }
        released = true
        return true
    }

    func wait() throws -> String {
        var observedWaiting = false
        while true {
            condition.lock()
            guard let deadline else { condition.unlock(); throw NativeOCRWorkError.busy }
            if let reason = stop {
                condition.unlock()
                throw reason == .deadline ? NativeOCRWorkError.timedOut : NativeOCRWorkError.cancelled
            }
            if let outcome = result {
                result = nil
                condition.unlock()
                return try outcome.get()
            }
            let remaining = deadline - clock()
            if remaining <= 0 {
                // Commit abandonment under the same lock as worker finish, so
                // the winner of timeout/result can never change after return.
                stop = .deadline
                result = nil
                let pending = scheduleCancellationLocked()
                wake.signal()
                condition.unlock()
                observe(.deadlineFired)
                if let pending { dispatchCancellation(pending) }
                throw NativeOCRWorkError.timedOut
            }
            condition.unlock()
            if !observedWaiting { observe(.callerWaiting); observedWaiting = true }
            // DispatchTime is monotonic; wall-clock changes cannot extend it.
            _ = wake.wait(timeout: .now() + remaining)
        }
    }

    // Only fixed engine configuration, never recognized text or image data.
    func recordConfiguration(revision: Int, languages: [String], automatic: Bool) {
        let allowed: Set<String> = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        condition.lock()
        configuration = ["revision": revision, "languages": languages.filter { allowed.contains($0) },
                         "recognitionLevel": "accurate", "languageCorrection": true,
                         "automaticallyDetectsLanguage": automatic]
        condition.unlock()
    }

    func snapshot() -> [String: Any] {
        condition.lock(); defer { condition.unlock() }
        var value: [String: Any] = ["id": id, "admittedAtUnixMs": admittedAtUnixMs, "events": events, "configuration": configuration,
                                   "state": released ? "released" : stop != nil ? "draining" : started ? "running" : "reserved",
                                   "phase": latestPhase.rawValue, "workerFinished": workFinished,
                                   "cancelScheduled": cancelScheduled, "cancelReturned": cancelReturned]
        if let stop { value["stopReason"] = stop.rawValue }
        if let startedAt { value["elapsedMs"] = (clock() - startedAt) * 1000 }
        return value
    }
}

// A diagnostics read is observational: it must not start another Vision query
// beside an in-flight request, warm a cold model, or block behind the engine.
final class NativeOCRCapabilities: @unchecked Sendable {
    static let shared = NativeOCRCapabilities()
    private let lock = NSLock()
    private var languages: [String]?
    func record(_ values: [String]) { lock.lock(); languages = values; lock.unlock() }
    func snapshot() -> (languages: [String], observed: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (languages ?? [], languages != nil)
    }
}
