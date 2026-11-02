// Explicit isolated-runner probe linked to the production native screenshot API.
// Own AppKit events are NOT a physical/global F1 or packaged-editor test.
// No TCC grants/prompts, general clipboard, arbitrary source-window capture, or
// captured image bytes. The hosted-CI visibility oracle reads only the bounded
// generated-source ROI in memory; capture gestures remain own-AppKit events.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit

private func fixtureNeed(_ value: Bool, _ reason: String) throws {
    if !value { throw NativeError("FIXTURE: " + reason) }
}
private func fixtureJSON(_ fields: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data("{}".utf8)
}
private final class FixtureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
private final class FixtureColorView: NSView {
    var phase = 1
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: phase == 1 ? 0 : 1, green: phase == 1 ? 1 : 0, blue: 0, alpha: 1).setFill()
        bounds.fill()
        // Spatial fiducials disambiguate a wrong crop, shift or output scaling.
        NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).setFill()
        CGRect(x: 8, y: 8, width: 16, height: 16).fill()
        CGRect(x: 8, y: 296, width: 16, height: 16).fill()
        NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1).setFill()
        CGRect(x: 488, y: 8, width: 16, height: 16).fill()
        CGRect(x: 488, y: 296, width: 16, height: 16).fill()
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).setFill()
        CGRect(x: 248, y: 152, width: 16, height: 16).fill()
    }
}

private func sourceMain() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    guard let screen = NSScreen.screens.first, screen.visibleFrame.width >= 700, screen.visibleFrame.height >= 500 else {
        FileHandle.standardOutput.write(fixtureJSON(["ok": false, "reason": "generated-display-unavailable"]) + Data([10]))
        exit(2)
    }
    let original = NSEvent.mouseLocation
    let originalQuartz = CGPoint(x: original.x, y: CGDisplayBounds(CGMainDisplayID()).height - original.y)
    let frame = CGRect(x: floor(screen.visibleFrame.midX - 256), y: floor(screen.visibleFrame.midY - 160), width: 512, height: 320)
    let window = FixtureWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.level = .normal
    window.hasShadow = false
    window.isOpaque = true
    window.sharingType = .readOnly
    window.animationBehavior = .none
    let view = FixtureColorView(frame: CGRect(origin: .zero, size: frame.size))
    window.contentView = view
    func stop() -> Never {
        // Restore from the same generated foreground source which moved it.
        let restored = CGWarpMouseCursorPosition(originalQuartz) == .success
        window.close()
        exit(restored ? 0 : 1)
    }
    func reply(_ phase: Int) {
        FileHandle.standardOutput.write(fixtureJSON([
            "ok": true, "phase": phase, "pid": ProcessInfo.processInfo.processIdentifier,
            "windowId": window.windowNumber, "x": window.frame.minX, "y": window.frame.minY,
            "width": window.frame.width, "height": window.frame.height,
            "scale": screen.backingScaleFactor,
            "applicationActive": app.isActive, "windowKey": window.isKeyWindow,
            "windowVisible": window.isVisible, "windowOnActiveSpace": window.isOnActiveSpace,
            "applicationFinishedLaunching": NSRunningApplication.current.isFinishedLaunching,
            "runningApplicationActive": NSRunningApplication.current.isActive,
            "frontmostIsSource": NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        ]) + Data([10]))
    }
    DispatchQueue.main.async {
        app.activate(ignoringOtherApps: true) // only this generated source process
        window.makeKeyAndOrderFront(nil)
        // These two fixture processes cooperate. Bring only the generated
        // normal-layer source ahead of other applications at that same level;
        // never hide/close a foreign window or raise the production selector.
        window.orderFrontRegardless()
        window.displayIfNeeded()
        let point = CGPoint(x: frame.minX + 80, y: CGDisplayBounds(CGMainDisplayID()).height - frame.minY - 80)
        guard CGWarpMouseCursorPosition(point) == .success else {
            FileHandle.standardOutput.write(fixtureJSON(["ok": false, "reason": "generated-pointer-positioning-failed"]) + Data([10]))
            stop()
        }
        reply(1)
    }
    DispatchQueue.global(qos: .utility).async {
        while let line = readLine() {
            if line == "phase2" {
                DispatchQueue.main.async {
                    view.phase = 2; view.needsDisplay = true
                    window.displayIfNeeded(); reply(2)
                }
            } else if line == "stop" {
                DispatchQueue.main.async { stop() }
                return
            }
        }
        DispatchQueue.main.async { stop() }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 100) { stop() }
    withExtendedLifetime(window) { app.run() }
}

private final class ScreenshotProbe {
    let reportURL: URL
    let directory: URL
    var report: [String: Any] = [
        "schema": "echolingo-macos-screenshot-native-v1", "ok": false,
        "status": "running", "permissionRequested": false, "securitySettingsChanged": false,
        "generalClipboardTouched": false, "userContentCaptured": false,
        "physicalF1Tested": false, "packagedEditorTested": false, "rustClipboardBackendTested": false,
        "ownAppKitEventsOnly": true, "captureGesturesOwnAppKitOnly": true,
        "globalSystemUISetupEventDispatched": false, "globalSystemUISetupEscapePairs": 0,
        "productionNativeEntryPoint": "capture-screenshot",
        "deferredProductionNativeEntryPoints": ["select-screenshot", "capture-selected-region"],
        "physicalMultiDisplayTested": false, "monitorGapRuntimeTested": false
    ]
    var cases: [[String: Any]] = []
    var source: Process?
    var sourceInput: FileHandle?
    var sourceOutput: FileHandle?
    var target: CaptureWindowTarget?
    var sourceScale: CGFloat = 1
    var sourcePhase = 1
    var preCasePixelProof: String?
    var activeSelectorFrames: [Int: CGRect] = [:]
    var selectorRetirementObservations = 0
    var operation: String?
    var activeCase: String?
    var caseStarted = Date()
    var caseDriven = false
    var adjustmentVerified = false
    var adjustmentMoveResizeVerified = false
    var timer: Timer?
    var finished = false
    var oracleAttempted = false
    var oracleToken: UUID?
    var pinProofWindows: [NSWindow] = []
    var oracleOccluder: NSWindow?
    var owner: NSWindow?
    var savePanel: NSSavePanel?
    let modes = ["window-phase1", "rectangle-phase1", "escape-cancel", "request-cancel", "window-phase2",
        "deferred-window-phase2", "deferred-rectangle-phase2", "deferred-escape-cancel", "deferred-cancel-after-selection"]
    var index = 0

    init(reportURL: URL, directory: URL) { self.reportURL = reportURL; self.directory = directory }

    func finish(_ status: String, reason: String? = nil) {
        guard !finished else { return }; finished = true
        timer?.invalidate(); timer = nil
        pinProofWindows.forEach { $0.close() }; pinProofWindows.removeAll()
        oracleToken = nil; oracleOccluder?.close(); oracleOccluder = nil
        if let operation = operation {
            _ = nativeResponse(mode: "--cancel-native-capture", input: Data(operation.utf8))
            _ = nativeResponse(mode: "--end-native-capture", input: Data(operation.utf8))
        }
        savePanel?.cancel(nil); savePanel?.orderOut(nil); owner?.close()
        if let sourceInput = sourceInput { try? sourceInput.write(contentsOf: Data("stop\n".utf8)); try? sourceInput.close() }
        // Preserve cleanup evidence in the report itself, not just the exit code.
        DispatchQueue.global(qos: .utility).async {
            var sourceClean = true
            if let source = self.source {
                let until = Date().addingTimeInterval(2)
                while source.isRunning && Date() < until { Thread.sleep(forTimeInterval: 0.02) }
                if source.isRunning {
                    sourceClean = false; source.terminate()
                    let terminateUntil = Date().addingTimeInterval(1)
                    while source.isRunning && Date() < terminateUntil { Thread.sleep(forTimeInterval: 0.02) }
                }
                if source.isRunning || source.terminationStatus != 0 { sourceClean = false }
            }
            DispatchQueue.main.async {
                let result = sourceClean ? status : "failed"
                self.report["status"] = result; self.report["ok"] = result == "passed"
                if let finalReason = sourceClean ? reason : "owned-source-cleanup-or-cursor-restore-failed" {
                    self.report["reason"] = finalReason
                }
                if !sourceClean, let reason = reason { self.report["initialReason"] = reason }
                self.report["cases"] = self.cases
                self.report["captureCasesPassed"] = result == "passed" && self.cases.count == self.modes.count
                self.report["capturePermissionBlocked"] = status == "blocked"
                self.report["ownedSourceCleanupConfirmed"] = sourceClean
                let data = fixtureJSON(self.report)
                try? data.write(to: self.reportURL, options: .atomic)
                FileHandle.standardOutput.write(data + Data([10]))
                exit(result == "passed" ? 0 : result == "blocked" ? 2 : 1)
            }
        }
    }

    func start() {
        do {
            try captureScreenshotSelfTest()
            report["authoritativeHitPolicyFixturePassed"] = true
            try imageSerializationProbe()
            dialogCancellationProbe()
        } catch { finish("failed", reason: String(describing: error)) }
    }

    func imageSerializationProbe() throws {
        guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw NativeError("FIXTURE: generated image allocation failed")
        }
        // Raw device-RGB samples avoid a dynamic/catalog NSColor conversion
        // which emits "Unrecognized colorspace number -1" on the CI host.
        var green = [0, 255, 0, 255]
        green.withUnsafeMutableBufferPointer { pixel in
            for y in 0..<24 { for x in 0..<32 { image.setPixel(pixel.baseAddress!, atX: x, y: y) } }
        }
        guard let png = image.representation(using: .png, properties: [:]),
              let jpeg = image.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
            throw NativeError("FIXTURE: native PNG/JPEG serialization failed")
        }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EchoLingoScreenshotFixture-" + UUID().uuidString))
        defer { pasteboard.clearContents(); pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        try fixtureNeed(pasteboard.setData(png, forType: .png), "private image pasteboard write failed")
        try fixtureNeed(pasteboard.data(forType: .png) == png, "private image pasteboard PNG roundtrip differs")
        guard let copied = NSImage(pasteboard: pasteboard), let tiff = copied.tiffRepresentation,
              let decoded = NSBitmapImageRep(data: tiff) else { throw NativeError("FIXTURE: private pasteboard image decode failed") }
        try fixtureNeed(decoded.pixelsWide == 32 && decoded.pixelsHigh == 24, "private pasteboard image dimensions differ")
        for (name, bytes) in [("generated.png", png), ("generated.jpg", jpeg)] {
            let url = directory.appendingPathComponent(name)
            try bytes.write(to: url, options: .withoutOverwriting)
            guard let restored = NSBitmapImageRep(data: try Data(contentsOf: url)) else { throw NativeError("FIXTURE: native saved image decode failed") }
            try fixtureNeed(restored.pixelsWide == 32 && restored.pixelsHigh == 24, "native saved image dimensions differ")
        }
        report["privatePasteboardImageRoundtripPassed"] = true
        report["nativePNGJPEGFileRoundtripPassed"] = true
    }

    func dialogCancellationProbe() {
        let window = FixtureWindow(contentRect: CGRect(x: 80, y: 80, width: 360, height: 180),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.title = "Generated screenshot dialog fixture"
        window.makeKeyAndOrderFront(nil); owner = window
        let panel = NSSavePanel(); savePanel = panel
        panel.directoryURL = directory; panel.nameFieldStringValue = "must-not-exist.png"
        panel.canCreateDirectories = false; panel.allowsOtherFileTypes = false
        var sawVisible = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, !self.finished else { return }
            guard response == .cancel, sawVisible,
                  !FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("must-not-exist.png").path) else {
                self.finish("failed", reason: "native-save-panel-cancel-not-observed"); return
            }
            self.report["nativeSavePanelCancelPassed"] = true
            // AppKit documents that the completion can run while the sheet is
            // still onscreen. Dismiss it explicitly, then observe closure before
            // launching the generated source (including any XPC panel animation).
            panel.orderOut(nil); window.orderOut(nil); window.close()
            self.awaitDialogHidden(panel, owner: window, deadline: Date().addingTimeInterval(2))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { sawVisible = panel.isVisible; panel.cancel(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.savePanel != nil { self?.finish("failed", reason: "native-save-panel-cancel-timeout") }
        }
    }

    func awaitDialogHidden(_ panel: NSSavePanel, owner: NSWindow, deadline: Date) {
        guard !finished else { return }
        if !panel.isVisible && !owner.isVisible && owner.attachedSheet == nil {
            report["nativeSavePanelHiddenBeforeCapture"] = true
            savePanel = nil; self.owner = nil
            startCaptureProbe()
        } else if Date() >= deadline {
            finish("failed", reason: "native-save-panel-not-hidden-before-capture")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                self.awaitDialogHidden(panel, owner: owner, deadline: deadline)
            }
        }
    }

    func startCaptureProbe() {
        let permission = CGPreflightScreenCaptureAccess()
        report["screenCapturePreflightGranted"] = permission
        guard permission else { finish("blocked", reason: "screen-recording-preflight-false"); return }
        do {
            let process = Process(); let input = Pipe(); let output = Pipe()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--source", "--isolated-test-session"]
            process.standardInput = input; process.standardOutput = output
            process.standardError = FileHandle.standardError
            try process.run()
            source = process; sourceInput = input.fileHandleForWriting; sourceOutput = output.fileHandleForReading
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.readSource(phase: 1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                if self?.target == nil { self?.finish("failed", reason: "generated-source-ready-timeout") }
            }
        } catch { finish("failed", reason: "generated-source-launch-failed") }
    }

    func readSource(phase: Int) {
        guard let output = sourceOutput else { return }
        var bytes = Data()
        while bytes.count < 4096 {
            guard let next = try? output.read(upToCount: 1), !next.isEmpty else { break }
            if next[0] == 10 { break }; bytes.append(next)
        }
        guard let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            DispatchQueue.main.async { self.finish("failed", reason: "generated-source-protocol") }; return
        }
        DispatchQueue.main.async {
            guard !self.finished, let source = self.source,
                  object["ok"] as? Bool == true, object["phase"] as? Int == phase,
                  object["pid"] as? Int32 == source.processIdentifier,
                  let number = object["windowId"] as? UInt32, number > 0,
                  let x = object["x"] as? Double, let y = object["y"] as? Double,
                  let width = object["width"] as? Double, let height = object["height"] as? Double,
                  let scale = object["scale"] as? Double, scale > 0 && scale <= 4 else {
                self.finish("failed", reason: "generated-source-identity"); return
            }
            let target = CaptureWindowTarget(id: number, pid: source.processIdentifier,
                                             frame: CGRect(x: x, y: y, width: width, height: height))
            if phase == 2 && self.target != target { self.finish("failed", reason: "generated-source-frame-changed"); return }
            self.target = target; self.sourceScale = scale; self.sourcePhase = phase
            self.report["sourcePhaseAcknowledged"] = phase
            var appKitState: [String: Any] = [:]
            for key in ["applicationActive", "windowKey", "windowVisible", "windowOnActiveSpace", "frontmostIsSource",
                        "applicationFinishedLaunching", "runningApplicationActive"] {
                if let value = object[key] as? Bool { appKitState[key] = value }
            }
            self.report["sourceAppKitState"] = appKitState
            if phase == 1 {
                // AppKit ordering/display calls are not a WindowServer-ready
                // handshake. No event or capture starts until the exact public
                // PID/ID/frame/sharing/z-order predicate has become true.
                self.awaitInitialSource(deadline: Date().addingTimeInterval(2), observations: 0)
                return
            }
            do {
                try self.verifyCaseSource()
                // Only the generated source repositions the cursor, while it
                // is foreground; all button/key events stay in this probe app.
                let expected = CGPoint(x: target.frame.minX + 80, y: target.frame.minY + 80)
                let actual = NSEvent.mouseLocation
                try fixtureNeed(abs(actual.x - expected.x) <= 1 && abs(actual.y - expected.y) <= 1,
                                "generated pointer position was not retained")
                self.beginCase()
            } catch { self.finish("failed", reason: String(describing: error)) }
        }
    }

    func awaitInitialSource(deadline: Date, observations: Int) {
        guard !finished else { return }
        report["sourceReadinessObservations"] = observations + 1
        do {
            try verifySourceVisible()
            guard let target = target else { throw NativeError("FIXTURE: missing owned source") }
            let point = CGPoint(x: target.frame.minX + 80, y: target.frame.minY + 80)
            let actual = NSEvent.mouseLocation
            try fixtureNeed(abs(actual.x - point.x) <= 1 && abs(actual.y - point.y) <= 1,
                            "generated pointer position was not retained")
            report["sourceWindowServerReady"] = true
            report["sourceWindowServerReadinessMethod"] = "exact-geometric-metadata"
            beginCase()
        } catch {
            if Date() >= deadline {
                if !oracleAttempted {
                    oracleAttempted = true
                    report["geometricVisibilityFailure"] = String(describing: error)
                    beginVisibilityOracle()
                    return
                }
                finish("failed", reason: String(describing: error)); return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                self.awaitInitialSource(deadline: deadline, observations: observations + 1)
            }
        }
    }

    func oracleSourceIdentity(_ expected: CaptureWindowTarget) throws -> NSScreen {
        report["visibilityOracleOverlaySharingGuardVerified"] = false
        try fixtureNeed(CGPreflightScreenCaptureAccess(), "visibility oracle permission is not preapproved")
        guard let source = source, source.isRunning, source.processIdentifier == expected.pid,
              target == expected, expected.frame.width == 512, expected.frame.height == 320,
              let records = captureCurrentWindows(),
              captureWindowIsCurrent(expected, records: records, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height,
                                     excludingPID: ProcessInfo.processInfo.processIdentifier),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(expected.frame) }),
              screen.backingScaleFactor == sourceScale else { throw NativeError("FIXTURE: oracle source identity/display changed") }
        // A no-exclusion API still honors OS content protection. Never treat a
        // protected/unknown sharing overlay omitted by the OS as transparency.
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        var sharedOverlays = 0
        for record in records {
            if captureWindowNumber(record[kCGWindowNumber as String]) == Double(expected.id) { break }
            if captureWindowNumber(record[kCGWindowAlpha as String]) == 0 { continue }
            guard let dictionary = record[kCGWindowBounds as String] as? [String: Any],
                  let quartz = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  [quartz.minX, quartz.minY, quartz.width, quartz.height].allSatisfy({ $0.isFinite }) else {
                throw NativeError("FIXTURE: oracle overlay metadata is unavailable")
            }
            let frame = CGRect(x: quartz.minX, y: primary - quartz.maxY, width: quartz.width, height: quartz.height)
            if !frame.intersection(expected.frame).isEmpty {
                let sharing = captureWindowNumber(record[kCGWindowSharingState as String])
                try fixtureNeed(sharing == 1 || sharing == 2, "oracle cannot prove pixels through a protected or unknown-sharing overlay")
                sharedOverlays += 1
            }
        }
        report["visibilityOracleOverlaySharingGuardVerified"] = true
        report["visibilityOracleIntersectingSharedOverlayCount"] = sharedOverlays
        return screen
    }

    func beginVisibilityOracle() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              #available(macOS 14.0, *), let target = target, cases.isEmpty, operation == nil,
              report["nativeSavePanelHiddenBeforeCapture"] as? Bool == true,
              !NSApplication.shared.windows.contains(where: { $0 is CaptureSelectionPanel && $0.isVisible }) else {
            finish("failed", reason: "bounded-visible-pixel-oracle-unavailable"); return
        }
        report["visibilityOracleHostedRunnerVerified"] = true
        report["visibilityOracleExcludedWindowCount"] = 0
        report["visibilityOraclePixelBytesRetained"] = false
        report["visibilityOracleRegion"] = "exact-generated-source-512x320"
        // First prove the entire live source with no window exclusions. Then
        // add our own normal-level occluder and prove both its exact pixels and
        // rejection by the unobstructed-source oracle. Finally remove it and
        // independently prove the full original source again.
        captureVisibilityOracle(target, stage: "unobstructed", occluded: false) {
            let rectangle = CGRect(x: target.frame.minX + 224, y: target.frame.minY + 128, width: 64, height: 64)
            let window = FixtureWindow(contentRect: rectangle, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.level = .normal; window.hasShadow = false
            window.isOpaque = true; window.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
            window.sharingType = .readOnly; window.animationBehavior = .none
            self.oracleOccluder = window; window.orderFrontRegardless(); window.displayIfNeeded()
            DispatchQueue.main.async {
                self.captureVisibilityOracle(target, stage: "generated-occlusion", occluded: true) {
                    window.orderOut(nil); window.close()
                    guard !window.isVisible else { self.finish("failed", reason: "owned-oracle-occluder-remained-visible"); return }
                    self.report["visibilityOracleOwnedOccluderHidden"] = true
                    self.oracleOccluder = nil
                    DispatchQueue.main.async {
                        self.captureVisibilityOracle(target, stage: "restored", occluded: false) {
                            self.report["visibilityOraclePassed"] = true
                            let point = CGPoint(x: target.frame.minX + 80, y: target.frame.minY + 80)
                            let hit = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
                            let candidate = captureCurrentWindows().flatMap {
                                captureHoverWindow($0, at: point, primaryHeight: CGDisplayBounds(CGMainDisplayID()).height,
                                                   excludingPID: ProcessInfo.processInfo.processIdentifier)
                            }
                            let diagnostic: [String: Any] = ["osMouseDownWindowID": hit,
                                "osMouseDownMatchesSource": hit == Int(target.id),
                                "productionCandidatePresent": candidate != nil,
                                "productionCandidateMatchesSource": candidate == target,
                                "productionCandidateWindowID": candidate.map { Int($0.id) } ?? 0]
                            self.report["visibilityOracleHitDiagnostic"] = diagnostic
                            // A proof is not a forced picker target or a capture
                            // pass. Start the actual unmodified native API; it
                            // must still produce all five normal case outcomes.
                            self.report["sourceWindowServerReady"] = true
                            self.report["sourceWindowServerReadinessMethod"] = "independent-composited-pixels"
                            self.report["nativePickerStartedAfterVisibilityOracle"] = true
                            self.beginCase()
                        }
                    }
                }
            }
        }
    }

    // Only the generated, process-owned oracle window is described. Never
    // serialize foreign-window records, titles, contents or arbitrary strings.
    func recordOwnedOracleWindow(_ window: NSWindow, records: [[String: Any]]?, expectedFrame: CGRect) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let id = window.windowNumber
        let own = (records ?? []).filter {
            captureWindowNumber($0[kCGWindowNumber as String]) == Double(id)
                && captureWindowNumber($0[kCGWindowOwnerPID as String]) == Double(pid)
        }
        var value: [String: Any] = ["expectedPID": pid, "expectedWindowID": id,
            "expectedFrame": [expectedFrame.minX, expectedFrame.minY, expectedFrame.width, expectedFrame.height],
            "appKitFrame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height],
            "appKitVisible": window.isVisible, "appKitSharing": window.sharingType.rawValue,
            "appKitLevel": window.level.rawValue, "recordsAvailable": records != nil,
            "ownMatchingRecordCount": own.count]
        if own.count == 1, let record = own.first {
            for (name, key) in [("observedPID", kCGWindowOwnerPID), ("observedWindowID", kCGWindowNumber),
                                ("observedLayer", kCGWindowLayer), ("observedSharing", kCGWindowSharingState),
                                ("observedAlpha", kCGWindowAlpha)] {
                value[name] = captureWindowNumber(record[key as String]) as Any? ?? NSNull()
            }
            value["observedOnScreen"] = record[kCGWindowIsOnscreen as String] as? Bool as Any? ?? NSNull()
            if let bounds = record[kCGWindowBounds as String] as? [String: Any],
               let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) {
                value["observedQuartzFrame"] = [frame.minX, frame.minY, frame.width, frame.height]
                value["observedAppKitFrame"] = [frame.minX, CGDisplayBounds(CGMainDisplayID()).height - frame.maxY,
                                                frame.width, frame.height]
            }
        }
        report["ownedOracleWindowDiagnostic"] = value
    }

    @available(macOS 14.0, *)
    func captureVisibilityOracle(_ expected: CaptureWindowTarget, stage: String, occluded: Bool, phase: Int = 1,
                                 readinessDeadline: Date? = nil, priorPhaseObservations: Int = 0,
                                 completion: @escaping () -> Void) {
        guard !finished else { return }
        let deadline = readinessDeadline ?? Date().addingTimeInterval(8)
        report["visibilityOracleStage"] = stage
        do {
            try fixtureNeed(Date() <= deadline, "visibility oracle exceeded its absolute deadline")
            let screen = try oracleSourceIdentity(expected)
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                throw NativeError("FIXTURE: oracle display ID is unavailable")
            }
            let displayID = CGDirectDisplayID(number.uint32Value), displayFrame = screen.frame
            let roi = CGRect(x: expected.frame.minX - displayFrame.minX, y: displayFrame.maxY - expected.frame.maxY,
                             width: expected.frame.width, height: expected.frame.height)
            func verifyOracleWindows() throws {
                let currentScreen = try self.oracleSourceIdentity(expected)
                try fixtureNeed(currentScreen.frame == displayFrame
                    && (currentScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID,
                    "oracle display identity/frame changed")
                if occluded {
                    guard let window = self.oracleOccluder else { throw NativeError("FIXTURE: owned oracle occluder changed") }
                    let expectedFrame = CGRect(x: expected.frame.minX + 224, y: expected.frame.minY + 128, width: 64, height: 64)
                    let observedRecords = captureCurrentWindows()
                    self.recordOwnedOracleWindow(window, records: observedRecords, expectedFrame: expectedFrame)
                    guard window.isVisible, window.windowNumber > 0, window.frame == expectedFrame,
                          let records = observedRecords else { throw NativeError("FIXTURE: owned oracle occluder changed") }
                    let identity = CaptureWindowTarget(id: CGWindowID(window.windowNumber),
                        pid: ProcessInfo.processInfo.processIdentifier, frame: window.frame)
                    try fixtureNeed(captureWindowIsCurrent(identity, records: records,
                        primaryHeight: CGDisplayBounds(CGMainDisplayID()).height, excludingPID: expected.pid),
                        "owned oracle occluder identity/frame/sharing changed")
                }
            }
            try verifyOracleWindows()
            let token = UUID(); oracleToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow)) {
                if !self.finished && self.oracleToken == token { self.finish("failed", reason: "visible-pixel-oracle-timeout") }
            }
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
                DispatchQueue.main.async {
                    guard !self.finished, self.oracleToken == token else { return }
                    do {
                        try fixtureNeed(Date() <= deadline, "visibility oracle exceeded its absolute deadline")
                        try verifyOracleWindows()
                        guard let display = content?.displays.first(where: { $0.displayID == displayID }) else {
                            throw NativeError("FIXTURE: oracle display content is unavailable")
                        }
                        // Independent visible DISPLAY composition, excluding
                        // NOTHING. Never an isolated/backing-window capture.
                        let filter = SCContentFilter(display: display, excludingWindows: [])
                        if #available(macOS 14.2, *) { filter.includeMenuBar = true }
                        let configuration = SCStreamConfiguration()
                        configuration.sourceRect = roi
                        configuration.width = Int(expected.frame.width * self.sourceScale)
                        configuration.height = Int(expected.frame.height * self.sourceScale)
                        configuration.scalesToFit = false; configuration.showsCursor = false
                        SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, _ in
                            DispatchQueue.main.async {
                                guard !self.finished, self.oracleToken == token else { return }
                                self.oracleToken = nil
                                do {
                                    try fixtureNeed(Date() <= deadline, "visibility oracle exceeded its absolute deadline")
                                    try verifyOracleWindows()
                                    guard let image = image else { throw NativeError("FIXTURE: oracle display image is unavailable") }
                                    try fixtureNeed(image.width == Int(512 * self.sourceScale) && image.height == Int(320 * self.sourceScale),
                                                    "oracle exact ROI dimensions differ")
                                    do { try self.verifyPixels(image, phase: phase, occluder: occluded) }
                                    catch {
                                        // Only phase2's PRECONDITION can observe a
                                        // still-composited, exact known phase1.
                                        // Never retry a real picker/capture, an
                                        // arbitrary mismatch, or an unknown cover.
                                        if stage == "pre-case-window-phase2", phase == 2, !occluded,
                                           self.sourcePhase == 2, self.cases.count == 4, self.index == 4,
                                           self.operation == nil, self.activeCase == nil {
                                            var priorMatched = false
                                            do { try self.verifyPixels(image, phase: 1) ; priorMatched = true } catch {}
                                            self.report["phase2ReadinessObservations"] = priorPhaseObservations + 1
                                            self.report["phase2KnownPriorPhaseObservations"] = priorPhaseObservations + (priorMatched ? 1 : 0)
                                            self.report["phase2ReadinessMismatchCategory"] = priorMatched ? 1 : 2
                                            self.report["phase2CurrentCompositeVerified"] = false
                                            if priorMatched && Date() < deadline {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                                                    self.captureVisibilityOracle(expected, stage: stage, occluded: false, phase: 2,
                                                        readinessDeadline: deadline, priorPhaseObservations: priorPhaseObservations + 1,
                                                        completion: completion)
                                                }
                                                return
                                            }
                                        }
                                        throw error
                                    }
                                    if stage == "pre-case-window-phase2" {
                                        self.report["phase2ReadinessObservations"] = priorPhaseObservations + 1
                                        self.report["phase2KnownPriorPhaseObservations"] = priorPhaseObservations
                                        self.report["phase2ReadinessMismatchCategory"] = 0
                                        self.report["phase2CurrentCompositeVerified"] = true
                                        self.report["phase2ReadinessUsedSingleDeadline"] = true
                                    }
                                    if occluded {
                                        var rejected = false
                                        do { try self.verifyPixels(image, phase: phase) } catch { rejected = true }
                                        try fixtureNeed(rejected, "unobstructed oracle accepted generated occlusion")
                                        self.report["visibilityOracleGeneratedOccluderRejected"] = true
                                    }
                                    // Only scalar results survive this closure;
                                    // the CGImage and normalized pixel buffer do not.
                                    try fixtureNeed(Date() <= deadline, "visibility oracle exceeded its absolute deadline")
                                    completion()
                                } catch { self.finish("failed", reason: String(describing: error)) }
                            }
                        }
                    } catch { self.finish("failed", reason: String(describing: error)) }
                }
            }
        } catch { finish("failed", reason: String(describing: error)) }
    }

    func sourceIdentityDiagnostic(_ target: CaptureWindowTarget, records: [[String: Any]],
                                  primary: CGFloat, excludingPID: Int32) -> [String: Any] {
        // Only project this generated process's exact window. Do not retain
        // foreign metadata, titles, record descriptions, or image bytes.
        var result: [String: Any] = ["windowPresent": false,
            "expectedPID": target.pid, "expectedWindowID": target.id,
            "expectedFrame": [target.frame.minX, target.frame.minY, target.frame.width, target.frame.height],
            "primaryHeight": primary]
        guard let record = records.first(where: {
            captureWindowNumber($0[kCGWindowOwnerPID as String]) == Double(target.pid)
                && captureWindowNumber($0[kCGWindowNumber as String]) == Double(target.id)
        }) else { return result }
        result["windowPresent"] = true
        for (label, key) in [("layer", kCGWindowLayer), ("alpha", kCGWindowAlpha), ("sharing", kCGWindowSharingState)] {
            if let value = record[key as String] as? NSNumber {
                result[label + "IsBoolean"] = CFGetTypeID(value) == CFBooleanGetTypeID()
                if value.doubleValue.isFinite { result[label] = value.doubleValue }
            }
        }
        if let value = record[kCGWindowIsOnscreen as String] as? Bool { result["onScreen"] = value }
        if let dictionary = record[kCGWindowBounds as String] as? [String: Any],
           let quartz = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
           [quartz.minX, quartz.minY, quartz.width, quartz.height].allSatisfy({ $0.isFinite }) {
            result["quartzFrame"] = [quartz.minX, quartz.minY, quartz.width, quartz.height]
            result["appKitFrame"] = [quartz.minX, primary - quartz.maxY, quartz.width, quartz.height]
        }
        let projected = captureWindowTarget(record, primaryHeight: primary, excludingPID: excludingPID)
        result["productionProjectionAccepted"] = projected != nil
        result["exactProductionTargetMatches"] = projected == target
        return result
    }

    func verifySourceVisible() throws {
        guard let target = target, let source = source, source.isRunning,
              target.pid == source.processIdentifier,
              let records = captureCurrentWindows() else { throw NativeError("FIXTURE: owned source is unavailable") }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        report["sourceIdentityDiagnostic"] = sourceIdentityDiagnostic(target, records: records, primary: primary, excludingPID: ownPID)
        try fixtureNeed(captureWindowIsCurrent(target, records: records, primaryHeight: primary, excludingPID: ownPID), "owned source identity/frame/sharing changed")
        // Before any pixels are captured, prove no foreign window covers any
        // part of this exact generated source. Never capture arbitrary desktop.
        report.removeValue(forKey: "sourceOccluderDiagnostic")
        var found = false
        for record in records {
            if captureWindowNumber(record[kCGWindowOwnerPID as String]) == Double(ownPID) { continue }
            if captureWindowNumber(record[kCGWindowNumber as String]) == Double(target.id) {
                try fixtureNeed(captureWindowNumber(record[kCGWindowOwnerPID as String]) == Double(target.pid), "source ID owner changed")
                found = true; break
            }
            if captureWindowNumber(record[kCGWindowAlpha as String]) == 0 { continue }
            guard let dictionary = record[kCGWindowBounds as String] as? [String: Any],
                  let quartz = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  [quartz.minX, quartz.minY, quartz.width, quartz.height].allSatisfy({ $0.isFinite }) else {
                throw NativeError("FIXTURE: occlusion metadata is unavailable")
            }
            let frame = CGRect(x: quartz.minX, y: primary - quartz.maxY, width: quartz.width, height: quartz.height)
            if !frame.intersection(target.frame).isEmpty {
                // Numeric metadata only; no names, descriptions, or pixels.
                // This diagnoses an obstruction but does not exempt it.
                var occluder: [String: Any] = ["appKitFrame": [frame.minX, frame.minY, frame.width, frame.height],
                    "quartzFrame": [quartz.minX, quartz.minY, quartz.width, quartz.height],
                    "sameGeneratedSourceProcess": captureWindowNumber(record[kCGWindowOwnerPID as String]) == Double(target.pid)]
                for (label, key) in [("pid", kCGWindowOwnerPID), ("windowID", kCGWindowNumber),
                                     ("layer", kCGWindowLayer), ("alpha", kCGWindowAlpha), ("sharing", kCGWindowSharingState)] {
                    if let value = captureWindowNumber(record[key as String]) { occluder[label] = value }
                }
                // Read-only identity of this single obstructing PID, requested
                // to distinguish a system/security shield from fixture setup.
                // Never enumerate other applications or read window titles,
                // command-line arguments, environment, or image contents.
                if let pid = captureWindowNumber(record[kCGWindowOwnerPID as String]),
                   pid > 0, pid <= Double(Int32.max), pid.rounded(.towardZero) == pid,
                   let application = NSRunningApplication(processIdentifier: Int32(pid)) {
                    occluder["ownerApplicationIdentityAvailable"] = true
                    if let identifier = application.bundleIdentifier {
                        occluder["ownerBundleIdentifier"] = String(identifier.prefix(256))
                    }
                    if let executable = application.executableURL {
                        occluder["ownerExecutablePath"] = String(executable.path.prefix(1024))
                    }
                } else { occluder["ownerApplicationIdentityAvailable"] = false }
                report["sourceOccluderDiagnostic"] = occluder
            }
            try fixtureNeed(frame.intersection(target.frame).isEmpty, "foreign window overlaps generated source; capture refused")
        }
        try fixtureNeed(found, "source absent from visible z-order")
    }

    func verifyCaseSource() throws {
        if report["visibilityOraclePassed"] as? Bool != true { try verifySourceVisible(); return }
        guard let target = target, let source = source, source.isRunning,
              source.processIdentifier == target.pid, let records = captureCurrentWindows() else {
            throw NativeError("FIXTURE: live case source is unavailable")
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        try fixtureNeed(captureWindowIsCurrent(target, records: records, primaryHeight: primary, excludingPID: ownPID),
                        "live case source identity/frame/sharing changed")
        let point = CGPoint(x: target.frame.minX + 80, y: target.frame.minY + 80)
        try fixtureNeed(captureHoverWindow(records, at: point, primaryHeight: primary, excludingPID: ownPID) == target,
                        "live case actual hit no longer resolves to the exact source")
        let selectorIDs = Set(NSApplication.shared.windows.filter { $0 is CaptureSelectionPanel && $0.isVisible }.map { $0.windowNumber })
        for record in records {
            if captureWindowNumber(record[kCGWindowNumber as String]) == Double(target.id) { break }
            if captureWindowNumber(record[kCGWindowAlpha as String]) == 0 { continue }
            guard let dictionary = record[kCGWindowBounds as String] as? [String: Any],
                  let quartz = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  [quartz.minX, quartz.minY, quartz.width, quartz.height].allSatisfy({ $0.isFinite }) else {
                throw NativeError("FIXTURE: live case overlay metadata is unavailable")
            }
            let frame = CGRect(x: quartz.minX, y: primary - quartz.maxY, width: quartz.width, height: quartz.height)
            if frame.intersection(target.frame).isEmpty { continue }
            if captureWindowNumber(record[kCGWindowOwnerPID as String]) == Double(ownPID) {
                guard let number = captureWindowNumber(record[kCGWindowNumber as String]),
                      selectorIDs.contains(where: { Double($0) == number }) else {
                    recordOwnWindowInventory(records)
                    throw NativeError("FIXTURE: unexpected own window overlaps the case source")
                }
                continue // only exact own selector panels; no foreign exemption
            }
            let sharing = captureWindowNumber(record[kCGWindowSharingState as String])
            try fixtureNeed(sharing == 1 || sharing == 2, "live case has a protected or unknown-sharing overlay")
        }
    }

    func recordOwnWindowInventory(_ records: [[String: Any]]) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        report["ownWindowInventoryPID"] = ownPID
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        report["ownAppKitWindowInventory"] = NSApplication.shared.windows.prefix(64).map { window -> [String: Any] in
            ["windowID": window.windowNumber, "selectorClass": window is CaptureSelectionPanel,
             "visible": window.isVisible, "key": window.isKeyWindow,
             "frame": [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height]]
        }
        report["ownOnscreenWindowInventory"] = records.filter {
            captureWindowNumber($0[kCGWindowOwnerPID as String]) == Double(ownPID)
        }.prefix(64).map { record -> [String: Any] in
            var value: [String: Any] = [:]
            for (label, key) in [("windowID", kCGWindowNumber), ("layer", kCGWindowLayer),
                                 ("alpha", kCGWindowAlpha), ("sharing", kCGWindowSharingState)] {
                if let number = captureWindowNumber(record[key as String]) { value[label] = number }
            }
            if let dictionary = record[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
               [rect.minX, rect.minY, rect.width, rect.height].allSatisfy({ $0.isFinite }) {
                value["frame"] = [rect.minX, primary - rect.maxY, rect.width, rect.height]
            }
            return value
        }
        report["activeCaseSelectorInventory"] = activeSelectorFrames.sorted { $0.key < $1.key }.map { id, frame -> [String: Any] in
            ["windowID": id, "frame": [frame.minX, frame.minY, frame.width, frame.height]]
        }
    }

    func beginCase() {
        guard !finished, index < modes.count else { if !finished { finish("passed") }; return }
        preCasePixelProof = nil
        let mode = modes[index]
        if report["visibilityOraclePassed"] as? Bool == true {
            guard #available(macOS 14.0, *), let target = target,
                  sourcePhase == (mode == "window-phase2" || mode.hasPrefix("deferred-") ? 2 : 1),
                  !NSApplication.shared.windows.contains(where: { $0 is CaptureSelectionPanel && $0.isVisible }) else {
                finish("failed", reason: "case-precondition-phase-or-selector-changed"); return
            }
            captureVisibilityOracle(target, stage: "pre-case-" + mode, occluded: false, phase: sourcePhase) {
                self.preCasePixelProof = mode
                self.beginNativeCase()
            }
        } else { beginNativeCase() }
    }

    func beginNativeCase() {
        guard !finished, index < modes.count else { if !finished { finish("passed") }; return }
        let mode = modes[index]
        activeSelectorFrames = [:]; selectorRetirementObservations = 0
        report["activeCaseMode"] = mode; report["activeCaseStage"] = "waiting-for-native-selector"
        let registered = nativeResponse(mode: "--begin-native-capture")
        guard registered["ok"] as? Bool == true, let id = registered["operationId"] as? String else {
            finish("failed", reason: "native-operation-registration"); return
        }
        operation = id; activeCase = mode; caseStarted = Date(); caseDriven = false
        adjustmentVerified = false; adjustmentMoveResizeVerified = false
        timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in self?.driveCase() }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
        DispatchQueue.global(qos: .userInitiated).async {
            let response = mode.hasPrefix("deferred-")
                ? nativeResponse(mode: "--select-screenshot", input: Data(id.utf8))
                : nativeResponse(mode: "--capture-screenshot", input: Data(id.utf8))
            DispatchQueue.main.async { self.completeCase(mode, id: id, response: response) }
        }
    }

    func send(_ type: NSEvent.EventType, point: CGPoint, panel: CaptureSelectionPanel) throws {
        let local = panel.convertPoint(fromScreen: point)
        guard let event = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else {
            throw NativeError("FIXTURE: own AppKit event creation failed")
        }
        NSApplication.shared.sendEvent(event)
    }

    func driveCase() {
        guard !finished, !caseDriven, let mode = activeCase, let target = target else { return }
        if Date().timeIntervalSince(caseStarted) > 6 { finish("failed", reason: "native-selector-or-hover-timeout"); return }
        let point = CGPoint(x: target.frame.minX + 80, y: target.frame.minY + 80)
        guard let panel = NSApplication.shared.windows.compactMap({ $0 as? CaptureSelectionPanel }).first(where: { $0.isVisible && $0.frame.contains(point) }),
              let view = panel.contentView as? CaptureSelectionView,
              let hovered = view.hoveredWindow,
              hovered.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY) == target.frame else { return }
        do {
            report["activeCaseStage"] = "pre-gesture-source-check"
            activeSelectorFrames = [:]
            for window in NSApplication.shared.windows where window is CaptureSelectionPanel && window.isVisible && window.windowNumber > 0 {
                try fixtureNeed(activeSelectorFrames[window.windowNumber] == nil, "current selector identity is duplicated")
                activeSelectorFrames[window.windowNumber] = window.frame
            }
            try verifyCaseSource(); caseDriven = true
            report["activeCaseStage"] = "dispatching-owned-gesture"
            if mode == "request-cancel" {
                guard let operation = operation else { throw NativeError("FIXTURE: missing own token") }
                let cancelled = nativeResponse(mode: "--cancel-native-capture", input: Data(operation.utf8))
                try fixtureNeed(cancelled["ok"] as? Bool == true, "request cancellation was rejected")
            } else if mode.hasSuffix("escape-cancel") {
                guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else {
                    throw NativeError("FIXTURE: own Escape event creation failed")
                }
                NSApplication.shared.sendEvent(event)
            } else {
                try send(.leftMouseDown, point: point, panel: panel)
                let end = mode.contains("rectangle") ? CGPoint(x: point.x + 120, y: point.y + 80) : CGPoint(x: point.x + 1, y: point.y + 1)
                if mode.contains("rectangle") { try send(.leftMouseDragged, point: end, panel: panel) }
                try send(.leftMouseUp, point: end, panel: panel)
                let expected = mode.contains("rectangle")
                    ? CGRect(x: point.x, y: point.y, width: 120, height: 80) : target.frame
                if mode.hasPrefix("deferred-") {
                    try fixtureNeed(view.handles.isEmpty && view.actionButtons.isEmpty,
                                    "geometry-only selection unexpectedly created native adjustment controls")
                    return
                }
                func assertAdjustment(_ frame: CGRect) throws {
                    try fixtureNeed(panel.isVisible && view.selection?.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY) == frame,
                                    "released screenshot did not retain exact adjustable region")
                    try fixtureNeed(view.handles.count == 8 && view.actionButtons.count == CaptureScreenshotAction.allCases.count,
                                    "native adjustment handles/actions are incomplete")
                }
                try assertAdjustment(expected)
                if mode.contains("rectangle") {
                    func drag(_ first: CGPoint, _ last: CGPoint, _ frame: CGRect) throws {
                        try send(.leftMouseDown, point: first, panel: panel)
                        try send(.leftMouseDragged, point: last, panel: panel)
                        try send(.leftMouseUp, point: last, panel: panel)
                        try assertAdjustment(frame)
                    }
                    let center = CGPoint(x: expected.midX, y: expected.midY)
                    let moved = CGPoint(x: center.x + 12, y: center.y + 8)
                    try drag(center, moved, expected.offsetBy(dx: 12, dy: 8))
                    try drag(moved, center, expected)
                    let corner = CGPoint(x: expected.maxX, y: expected.maxY)
                    let expanded = CGPoint(x: corner.x + 16, y: corner.y + 8)
                    try drag(corner, expanded, CGRect(x: expected.minX, y: expected.minY, width: 136, height: 88))
                    try drag(expanded, corner, expected)
                    adjustmentMoveResizeVerified = true
                }
                guard let action = view.actionButtons.first(where: { $0.0 == .select }) else {
                    throw NativeError("FIXTURE: native select action is missing")
                }
                let actionPoint = panel.convertPoint(toScreen: CGPoint(x: action.1.midX, y: action.1.midY))
                try fixtureNeed(panel.frame.contains(actionPoint), "native action escaped owned selector")
                adjustmentVerified = true
                report["activeCaseStage"] = "dispatching-owned-native-action"
                try send(.leftMouseDown, point: actionPoint, panel: panel)
                try send(.leftMouseUp, point: actionPoint, panel: panel)
            }
        } catch { finish("failed", reason: String(describing: error)) }
    }

    func completeCase(_ mode: String, id: String, response: [String: Any]) {
        guard !finished, activeCase == mode, operation == id else { return }
        timer?.invalidate(); timer = nil
        _ = nativeResponse(mode: "--end-native-capture", input: Data(id.utf8)); operation = nil
        report["activeCaseStage"] = "observing-exact-selector-retirement"
        // AppKit visibility changes before WindowServer necessarily publishes
        // the removal. Observe only this case's exact known selector IDs, never
        // blanket-exempt own windows or retry the gesture. Stay in its budget.
        awaitSelectorRetirement(mode, response: response,
                                deadline: min(Date().addingTimeInterval(1), caseStarted.addingTimeInterval(6)))
    }

    func awaitSelectorRetirement(_ mode: String, response: [String: Any], deadline: Date) {
        guard !finished, activeCase == mode, operation == nil else { return }
        do {
            try fixtureNeed(Date() <= deadline, "exact selector retirement exceeded its case deadline")
            try fixtureNeed(caseDriven && !activeSelectorFrames.isEmpty, "native response lacks exact dispatched selector identity")
            try fixtureNeed(!NSApplication.shared.windows.contains(where: { $0 is CaptureSelectionPanel && $0.isVisible }),
                            "native selector left visible panels")
            guard let records = captureCurrentWindows() else { throw NativeError("FIXTURE: selector retirement metadata unavailable") }
            selectorRetirementObservations += 1
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let primary = CGDisplayBounds(CGMainDisplayID()).height
            var remaining = false
            for record in records {
                guard let number = captureWindowNumber(record[kCGWindowNumber as String]) else { continue }
                guard let expected = activeSelectorFrames.first(where: { Double($0.key) == number })?.value else {
                    if captureWindowNumber(record[kCGWindowOwnerPID as String]) == Double(ownPID), let target = target {
                        guard let dictionary = record[kCGWindowBounds as String] as? [String: Any],
                              let quartz = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                              CGRect(x: quartz.minX, y: primary - quartz.maxY, width: quartz.width, height: quartz.height)
                                .intersection(target.frame).isEmpty else {
                            recordOwnWindowInventory(records)
                            throw NativeError("FIXTURE: unknown own window remains during selector retirement")
                        }
                    }
                    continue
                }
                guard captureWindowNumber(record[kCGWindowOwnerPID as String]) == Double(ownPID),
                      let dictionary = record[kCGWindowBounds as String] as? [String: Any],
                      let quartz = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                      CGRect(x: quartz.minX, y: primary - quartz.maxY, width: quartz.width, height: quartz.height) == expected else {
                    recordOwnWindowInventory(records)
                    throw NativeError("FIXTURE: retiring selector identity/frame changed")
                }
                remaining = true
            }
            if remaining {
                recordOwnWindowInventory(records)
                guard Date() < deadline else { throw NativeError("FIXTURE: exact selector on-screen retirement timed out") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                    self.awaitSelectorRetirement(mode, response: response, deadline: deadline)
                }
            } else {
                report["activeCaseStage"] = "post-response-source-check"
                acceptCaseResponse(mode, response: response)
            }
        } catch { finish("failed", reason: String(describing: error)) }
    }

    func acceptCaseResponse(_ mode: String, response: [String: Any]) {
        guard !finished, activeCase == mode else { return }
        do {
            try fixtureNeed(caseDriven, "native screenshot completed before own gesture was dispatched")
            try fixtureNeed(!NSApplication.shared.windows.contains(where: { $0 is CaptureSelectionPanel && $0.isVisible }), "native selector left visible panels")
            try fixtureNeed(response["text"] == nil, "F1 unexpectedly invoked OCR")
            try verifyCaseSource()
            if mode.hasPrefix("deferred-") && !mode.hasSuffix("escape-cancel")
                && response["deferredCaptureComplete"] as? Bool != true {
                try captureDeferredCase(mode, selection: response)
                return
            }
            var record: [String: Any] = ["mode": mode, "ok": true, "hoverOutlineVerified": true, "visiblePanelsAfter": 0,
                                          "exactSelectorRetirementVerified": true, "selectorRetirementObservations": selectorRetirementObservations,
                                          "exactOwnedSourceRevalidated": true, "ownAppKitEventDispatched": mode != "request-cancel",
                                          "nativeCancellationEndpointDispatched": mode == "request-cancel" || mode == "deferred-cancel-after-selection"]
            if mode.hasPrefix("deferred-") && !mode.hasSuffix("escape-cancel") {
                record["deferredGeometryOnlyVerified"] = true
                record["deferredCaptureDispatched"] = true
            }
            if mode.contains("cancel") {
                try fixtureNeed(response["ok"] as? Bool == false && response["imageBase64"] == nil,
                                "cancelled native screenshot returned pixels")
                try fixtureNeed((response["error"] as? String)?.hasPrefix("CANCELLED:") == true, "native cancellation had an unrelated error")
                record["nativeCancelled"] = true
            } else {
                guard response["ok"] as? Bool == true, let encoded = response["imageBase64"] as? String,
                      let bytes = Data(base64Encoded: encoded), let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let target = target else {
                    throw NativeError("FIXTURE: real native screenshot did not return a decodable PNG")
                }
                if !mode.hasPrefix("deferred-") {
                    try fixtureNeed(adjustmentVerified && response["initialAction"] as? String == "select",
                                    "native screenshot bypassed explicit adjustment action")
                    record["nativeAdjustmentVerified"] = true
                    record["nativeAction"] = "select"
                    record["nativeActionClickCount"] = 1
                    if mode.contains("rectangle") {
                        try fixtureNeed(adjustmentMoveResizeVerified, "native rectangle move/resize was not verified")
                        record["nativeAdjustmentMoveResizeRestored"] = true
                    }
                }
                let width = Int((mode.contains("rectangle") ? 120 : target.frame.width) * sourceScale)
                let height = Int((mode.contains("rectangle") ? 80 : target.frame.height) * sourceScale)
                try fixtureNeed(image.width == width && image.height == height, "real screenshot dimensions differ from exact source/drag frame")
                try verifyPixels(image, phase: mode == "window-phase2" || mode.hasPrefix("deferred-") ? 2 : 1, fullWindow: !mode.contains("rectangle"))
                record["imageWidth"] = width; record["imageHeight"] = height
                record["generatedVisiblePixelsVerified"] = true; record["ownOverlayPixelsAbsent"] = true
            }
            if report["visibilityOraclePassed"] as? Bool == true {
                try fixtureNeed(preCasePixelProof == mode, "case has no current full-composite precondition")
                guard #available(macOS 14.0, *), let target = target else { throw NativeError("FIXTURE: post-case oracle is unavailable") }
                record["preCaseFullCompositeVerified"] = true
                let accepted = record
                captureVisibilityOracle(target, stage: "post-case-" + mode, occluded: false, phase: sourcePhase) {
                    var checked = accepted; checked["postCaseFullCompositeVerified"] = true
                    self.recordCompletedCase(checked)
                }
            } else { recordCompletedCase(record) }
        } catch { finish("failed", reason: String(describing: error)) }
    }

    // Exercise the production metadata-only entry followed by its real deferred
    // pixel entry. Keep the original selector retirement and full pixel oracles.
    func captureDeferredCase(_ mode: String, selection: [String: Any]) throws {
        guard selection["ok"] as? Bool == true, selection["imageBase64"] == nil,
              selection["text"] == nil, selection["initialAction"] == nil,
              let geometry = selection["captureGeometry"] as? [String: Double],
              let plan = selection["selectionPlan"] as? [String: Any], let target = target else {
            throw NativeError("FIXTURE: selection entry did not return metadata-only geometry")
        }
        let rectangle = mode.contains("rectangle")
        let expected = rectangle ? CGRect(x: target.frame.minX + 80, y: target.frame.minY + 80,
                                          width: 120, height: 80) : target.frame
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        try fixtureNeed(geometry["x"] == Double(expected.minX)
                        && geometry["y"] == Double(primary - expected.maxY)
                        && geometry["width"] == Double(expected.width)
                        && geometry["height"] == Double(expected.height), "deferred selection geometry changed")
        let registered = nativeResponse(mode: "--begin-native-capture")
        guard registered["ok"] as? Bool == true, let id = registered["operationId"] as? String else {
            throw NativeError("FIXTURE: deferred operation registration failed")
        }
        operation = id
        let rect: [String: Double] = ["x": Double(expected.minX), "y": Double(primary - expected.maxY),
                                     "width": Double(expected.width), "height": Double(expected.height)]
        let input = try JSONSerialization.data(withJSONObject: ["operationId": id, "plan": plan, "rect": rect])
        if mode == "deferred-cancel-after-selection" {
            let cancelled = nativeResponse(mode: "--cancel-native-capture", input: Data(id.utf8))
            try fixtureNeed(cancelled["ok"] as? Bool == true, "deferred cancellation was rejected")
        }
        report["activeCaseStage"] = "production-deferred-region-capture"
        DispatchQueue.global(qos: .userInitiated).async {
            var response = nativeResponse(mode: "--capture-selected-region", input: input)
            _ = nativeResponse(mode: "--end-native-capture", input: Data(id.utf8))
            response["deferredCaptureComplete"] = true
            DispatchQueue.main.async {
                guard !self.finished, self.activeCase == mode, self.operation == id else { return }
                self.operation = nil
                self.acceptCaseResponse(mode, response: response)
            }
        }
    }

    func recordCompletedCase(_ record: [String: Any]) {
        guard !finished else { return }
        cases.append(record); index += 1; activeCase = nil; preCasePixelProof = nil
        if index == modes.count { verifyReadyPinCapture() }
        else if modes[index] == "window-phase2" {
            do {
                try sourceInput?.write(contentsOf: Data("phase2\n".utf8))
                DispatchQueue.global(qos: .utility).async { self.readSource(phase: 2) }
            } catch { finish("failed", reason: "generated-source-phase-command-failed") }
        } else { beginCase() }
    }

    // Reuse the already verified generated external source. This is real
    // production capture + Vision, not a user-desktop or packaged-pin claim.
    func verifyReadyPinCapture() {
        guard let target = target, let screen = NSScreen.screens.first(where: { $0.frame.contains(target.frame) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            finish("failed", reason: "pin-proof-generated-screen-missing"); return
        }
        let frame = CGRect(x: target.frame.minX + 20, y: target.frame.minY + 40, width: 460, height: 160)
        let pin = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        let helper = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        for window in [pin, helper] {
            window.isReleasedWhenClosed = false; window.hasShadow = false
            window.sharingType = .readOnly; window.backgroundColor = .magenta
        }
        pinProofWindows = [pin, helper]
        pin.contentView = GeneratedCapturePinView(frame: CGRect(origin: .zero, size: frame.size))
        pin.level = .floating; pin.orderFrontRegardless(); pin.displayIfNeeded()
        helper.level = .screenSaver; helper.orderFrontRegardless(); helper.displayIfNeeded()
        let pointer = Unmanaged.passUnretained(pin).toOpaque()
        guard echoLingoRegisterCapturePin(pointer) == 0 else {
            finish("failed", reason: "pin-proof-registration-failed"); return
        }
        let snapshot = captureReadyPinSnapshot()
        do {
            try fixtureNeed(snapshot.ids.contains(CGWindowID(pin.windowNumber))
                && !snapshot.ids.contains(CGWindowID(helper.windowNumber)), "only ready pin may be registered")
            let display = CaptureDisplayGeometry(id: number.uint32Value, frame: screen.frame, scale: screen.backingScaleFactor)
            let plan = try capturePlan(frame, displays: [display])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let image = try captureNativePlannedImage(plan, purpose: .region)
                    let text = try recognizeFixture(image)
                    try fixtureNeed(text.trimmingCharacters(in: .whitespacesAndNewlines) == "EchoLingo pin 97531",
                                    "ready pin text not captured or own helper was included")
                    DispatchQueue.main.async {
                        guard !self.finished else { return }
                        do {
                            guard self.pinProofWindows.count == 2 else { throw NativeError("FIXTURE: pin windows missing") }
                            let pin = self.pinProofWindows[0], helper = self.pinProofWindows[1]
                            pin.orderOut(nil)
                            try fixtureNeed(!captureReadyPinSnapshot().ids.contains(CGWindowID(pin.windowNumber)), "hidden pin still eligible")
                            var staleRejected = false
                            do { try captureValidateReadyPins(snapshot) } catch { staleRejected = true }
                            try fixtureNeed(staleRejected, "stale pin capture identity accepted")
                            pin.close(); helper.close(); self.pinProofWindows.removeAll()
                            try fixtureNeed(captureReadyPinSnapshot().windows.isEmpty, "closed pin registration remained")
                            self.report["readyPinCaptureOCRPassed"] = true
                            self.report["unregisteredOwnWindowExcludedPassed"] = true
                            self.report["readyPinLifecycleCleanupPassed"] = true
                            self.finish("passed")
                        } catch { self.finish("failed", reason: "pin-proof-lifecycle-failed") }
                    }
                } catch { DispatchQueue.main.async { self.finish("failed", reason: "pin-proof-capture-ocr-failed") } }
            }
        } catch { finish("failed", reason: "pin-proof-plan-failed") }
    }

    func verifyPixels(_ image: CGImage, phase: Int, fullWindow: Bool = true, occluder: Bool = false) throws {
        let row = image.width * 4
        var bytes = [UInt8](repeating: 0, count: row * image.height)
        let success = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: row, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        try fixtureNeed(success, "captured pixel normalization failed")
        // Every pixel, including edges: blue outlines, loupe plates, frozen
        // phase-1 pixels, and accidental desktop pixels must fail the probe.
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let x = CGFloat((offset / 4) % image.width) / sourceScale
            let y = CGFloat((offset / 4) / image.width) / sourceScale
            var expected = phase == 1 ? [0, 255, 0] : [255, 0, 0]
            if fullWindow {
                // Vertically symmetric markers make bitmap row conventions
                // irrelevant without allowing shifted/cropped/scaled regions.
                if (8..<24).contains(y) || (296..<312).contains(y) {
                    if (8..<24).contains(x) { expected = [0, 0, 255] }
                    if (488..<504).contains(x) { expected = [255, 255, 0] }
                }
                if (248..<264).contains(x) && (152..<168).contains(y) { expected = [255, 255, 255] }
                if occluder && (224..<288).contains(x) && (128..<192).contains(y) { expected = [255, 0, 255] }
            }
            try fixtureNeed((0..<3).allSatisfy { abs(Int(bytes[offset + $0]) - expected[$0]) <= 5 }
                            && bytes[offset + 3] >= 250, "captured image is not solely current generated visible pixels")
        }
    }
}

private final class GeneratedCapturePinView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSAttributedString(string: "EchoLingo pin 97531", attributes: [
            .font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black
        ]).draw(at: CGPoint(x: 16, y: 60))
    }
}

@main
private struct ScreenshotFixtureMain {
    static func main() {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--source"
            && CommandLine.arguments[2] == "--isolated-test-session" { sourceMain(); return }
        guard CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--isolated-test-session",
              CommandLine.arguments[2].hasPrefix("/"), CommandLine.arguments[3].hasPrefix("/") else {
            fputs("Expected --isolated-test-session /absolute/report.json /private/fixture-directory\n", stderr); exit(2)
        }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let probe = ScreenshotProbe(reportURL: URL(fileURLWithPath: CommandLine.arguments[2]),
                                    directory: URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true))
        DispatchQueue.main.async { probe.start() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 80) { probe.finish("failed", reason: "bounded-probe-timeout") }
        withExtendedLifetime(probe) { app.run() }
    }
}
