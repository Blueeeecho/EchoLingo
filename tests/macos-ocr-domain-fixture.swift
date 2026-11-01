// Synthetic coordinator tests only: no Vision, screenshot, clipboard or TCC.
import Foundation

private struct FixtureFailure: Error { let message: String }
private func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw FixtureFailure(message: message) }
}
private func reached(_ gate: DispatchSemaphore) throws {
    try require(gate.wait(timeout: .now() + 3) == .success, "Worker did not reach injected stage")
}
private func idle(_ domain: NativeOCRDomain) throws {
    let until = ProcessInfo.processInfo.systemUptime + 3
    while domain.snapshot()["state"] as? String != "idle" {
        if ProcessInfo.processInfo.systemUptime > until { throw FixtureFailure(message: "Slot did not drain") }
        Thread.sleep(forTimeInterval: 0.002)
    }
}
private func busy(_ domain: NativeOCRDomain) throws {
    for _ in 0..<100 {
        do {
            let unexpected = try domain.reserve(); unexpected.releaseReservation()
            throw FixtureFailure(message: "A blocked worker admitted another image")
        } catch NativeOCRWorkError.busy { }
    }
}
private func stopped(_ job: NativeOCRJob, deadline: Bool = false) throws {
    let start = ProcessInfo.processInfo.systemUptime
    do { _ = try job.wait(); throw FixtureFailure(message: "Stopped work published a result") }
    catch NativeOCRWorkError.cancelled { try require(!deadline, "Deadline became cancellation") }
    catch NativeOCRWorkError.timedOut { try require(deadline, "Cancellation became timeout") }
    try require(ProcessInfo.processInfo.systemUptime - start < 1, "Caller waited for blocked Vision/cancel")
}
private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
private final class Lifetime: @unchecked Sendable { }
private final class FixtureClock: @unchecked Sendable {
    private let lock = NSLock(); private var value: TimeInterval = 100
    func now() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ duration: TimeInterval) { lock.lock(); value += duration; lock.unlock() }
}

@main
private enum OCRDomainFixture {
    static func main() throws {
        // Reservation failures and cancellation before handoff never consume a worker.
        let domain = NativeOCRDomain()
        let abandoned = try domain.reserve(); abandoned.cancel(); abandoned.releaseReservation()
        try idle(domain)
        let beforeStart = try domain.reserve(); beforeStart.cancel()
        do { try beforeStart.start { _ in throw FixtureFailure(message: "Cancelled work ran") }
            throw FixtureFailure(message: "Cancelled start accepted") }
        catch NativeOCRWorkError.cancelled { }
        beforeStart.releaseReservation(); try idle(domain)

        let success = try domain.reserve()
        try success.start { _ in "fixture success" }
        let successfulText = try success.wait()
        try require(successfulText == "fixture success", "Successful result lost")
        try idle(domain)
        // End-native-capture cleanup must not enqueue cancellation after success.
        success.cancel()
        try require(success.snapshot()["cancelScheduled"] as? Bool == false, "Late cleanup cancelled completed work")

        // Work ignores cancellation. Caller still returns, one slot remains busy,
        // late output is discarded, and owned image is released before reuse.
        let entered = DispatchSemaphore(value: 0), releaseWork = DispatchSemaphore(value: 0)
        let work = try domain.reserve()
        var image: Lifetime? = Lifetime(); weak var imageProbe = image
        try work.start { [ownedImage = image!] _ in
            withExtendedLifetime(ownedImage) {
                entered.signal(); releaseWork.wait(); return "late fixture output"
            }
        }
        image = nil
        defer { releaseWork.signal() }
        try reached(entered)
        work.cancel(); try stopped(work); try busy(domain)
        try require(imageProbe != nil, "Image disappeared while request was running")
        releaseWork.signal(); try idle(domain)
        try require(imageProbe == nil, "Image retained after worker slot released")
        try stopped(work)

        // Cancellation is remembered before the request exists. A blocking
        // cancel call cannot hold the caller or free the slot when work ends.
        let binding = DispatchSemaphore(value: 0), allowBinding = DispatchSemaphore(value: 0)
        let cancelling = DispatchSemaphore(value: 0), releaseCancel = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0), cancels = Counter()
        var requestOwner: Lifetime? = Lifetime(); weak var requestProbe = requestOwner
        var transfer: (() -> Void)? = { [ownedRequest = requestOwner!] in
            withExtendedLifetime(ownedRequest) {
                cancels.increment(); cancelling.signal(); releaseCancel.wait()
            }
        }
        // The work closure transfers ownership of this simulated request into
        // cancellation; the outer fixture must release its own reference too.
        requestOwner = nil
        let prebind = try domain.reserve()
        try prebind.start { [cancelBody = transfer!] job in
            binding.signal(); allowBinding.wait()
            job.bindCancellation(cancelBody)
            defer { job.clearCancellation(); finished.signal() }
            try job.checkStopped()
            throw FixtureFailure(message: "Perform ran after pre-bind cancellation")
        }
        transfer = nil
        defer { allowBinding.signal(); releaseCancel.signal() }
        try reached(binding); prebind.cancel(); try stopped(prebind)
        allowBinding.signal(); try reached(cancelling); try reached(finished)
        for _ in 0..<100 { prebind.cancel() }
        try busy(domain)
        try require(cancels.count == 1, "Cancellation queued more than once")
        try require(requestProbe != nil, "Cancel request released while cancel was running")
        releaseCancel.signal(); try idle(domain); try stopped(prebind)
        try require(requestProbe == nil, "Cancel closure retained request after slot reuse")

        // Reverse order: cancel returns, but uncooperative perform still owns slot.
        let performing = DispatchSemaphore(value: 0), finishPerform = DispatchSemaphore(value: 0)
        let cancelDone = DispatchSemaphore(value: 0)
        let postbind = try domain.reserve()
        try postbind.start { job in
            job.bindCancellation { cancelDone.signal() }
            defer { job.clearCancellation() }
            performing.signal(); finishPerform.wait(); return "ignored"
        }
        defer { finishPerform.signal() }
        try reached(performing); postbind.cancel(); try stopped(postbind); try reached(cancelDone)
        try busy(domain); finishPerform.signal(); try idle(domain)

        // Cancellation wakes an already-admitted waiting caller while work
        // remains blocked. Signaling before semaphore wait also covers the
        // lost-wake boundary: semaphore permits must survive that race.
        let waiterReady = DispatchSemaphore(value: 0), waiterDone = DispatchSemaphore(value: 0)
        let awakeWork = DispatchSemaphore(value: 0), releaseAwakeWork = DispatchSemaphore(value: 0)
        let waiterFailures = Counter()
        let waking = try domain.reserve { phase in if phase == .callerWaiting { waiterReady.signal() } }
        try waking.start { _ in awakeWork.signal(); releaseAwakeWork.wait(); return "late" }
        defer { releaseAwakeWork.signal() }
        try reached(awakeWork)
        DispatchQueue(label: "OCR.fixture.waiter").async {
            do { _ = try waking.wait(); waiterFailures.increment() }
            catch NativeOCRWorkError.cancelled { }
            catch { waiterFailures.increment() }
            waiterDone.signal()
        }
        try reached(waiterReady); waking.cancel(); try reached(waiterDone)
        try require(waiterFailures.count == 0, "Waiting caller did not observe cancellation")
        try busy(domain); releaseAwakeWork.signal(); try idle(domain)

        // Deadline starts before handler/language lookup, not just perform.
        // No cancel request is bound yet; a blocked language query is isolated.
        let querying = DispatchSemaphore(value: 0), finishQuery = DispatchSemaphore(value: 0)
        let clock = FixtureClock()
        let deadlineDomain = NativeOCRDomain(clock: { clock.now() })
        let timed = try deadlineDomain.reserve()
        try timed.start(timeout: 30) { job in
            job.observe(.languageQueryStarted); querying.signal(); finishQuery.wait()
            job.observe(.languageQueryReturned); return "too late"
        }
        defer { finishQuery.signal() }
        try reached(querying); clock.advance(31)
        try stopped(timed, deadline: true); try busy(deadlineDomain)
        finishQuery.signal(); try idle(deadlineDomain); try stopped(timed, deadline: true)

        // Finishing late cannot win merely because the caller hasn't called wait.
        let delayed = try deadlineDomain.reserve()
        try delayed.start(timeout: 30) { _ in clock.advance(31); return "expired" }
        try idle(deadlineDomain); try stopped(delayed, deadline: true)
        let next = try domain.reserve(); try next.start { _ in "next" }
        let nextText = try next.wait(); try require(nextText == "next", "Old result changed new job")
        try idle(domain)
        let snapshot = domain.snapshot()
        try require(snapshot["lastDrained"] != nil, "Lost post-cancel stage timings")
        let cache = NativeOCRCapabilities()
        try require(!cache.snapshot().observed, "Diagnostics manufactured a language query")
        cache.record(["en-US"])
        try require(cache.snapshot().observed && cache.snapshot().languages == ["en-US"], "Observed capabilities lost")
        print("Bounded OCR coordinator fixtures passed; Apple Vision and interactive capture were not invoked.")
    }
}
