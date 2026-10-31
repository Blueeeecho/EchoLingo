// Explicit isolated-runner probe linked to the production native screenshot API.
// Own AppKit events are NOT a physical/global F1 or packaged-editor test.
// No TCC grants/prompts, AX access, global button/key injection, general clipboard
// access, arbitrary source-window capture, or captured image bytes in reports.
import AppKit
import CoreGraphics
import Foundation
import ImageIO

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
        "ownAppKitEventsOnly": true, "productionNativeEntryPoint": "capture-screenshot",
        "physicalMultiDisplayTested": false, "monitorGapRuntimeTested": false
    ]
    var cases: [[String: Any]] = []
    var source: Process?
    var sourceInput: FileHandle?
    var sourceOutput: FileHandle?
    var target: CaptureWindowTarget?
    var sourceScale: CGFloat = 1
    var operation: String?
    var activeCase: String?
    var caseStarted = Date()
    var caseDriven = false
    var timer: Timer?
    var finished = false
    var owner: NSWindow?
    var savePanel: NSSavePanel?
    let modes = ["window-phase1", "rectangle-phase1", "escape-cancel", "request-cancel", "window-phase2"]
    var index = 0

    init(reportURL: URL, directory: URL) { self.reportURL = reportURL; self.directory = directory }

    func finish(_ status: String, reason: String? = nil) {
        guard !finished else { return }; finished = true
        timer?.invalidate(); timer = nil
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
            self.target = target; self.sourceScale = scale
            var appKitState: [String: Any] = [:]
            for key in ["applicationActive", "windowKey", "windowVisible", "windowOnActiveSpace", "frontmostIsSource"] {
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
                try self.verifySourceVisible()
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
            beginCase()
        } catch {
            if Date() >= deadline { finish("failed", reason: String(describing: error)); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                self.awaitInitialSource(deadline: deadline, observations: observations + 1)
            }
        }
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
                                     ("layer", kCGWindowLayer), ("alpha", kCGWindowAlpha)] {
                    if let value = captureWindowNumber(record[key as String]) { occluder[label] = value }
                }
                report["sourceOccluderDiagnostic"] = occluder
            }
            try fixtureNeed(frame.intersection(target.frame).isEmpty, "foreign window overlaps generated source; capture refused")
        }
        try fixtureNeed(found, "source absent from visible z-order")
    }

    func beginCase() {
        guard !finished, index < modes.count else { if !finished { finish("passed") }; return }
        let mode = modes[index]
        let registered = nativeResponse(mode: "--begin-native-capture")
        guard registered["ok"] as? Bool == true, let id = registered["operationId"] as? String else {
            finish("failed", reason: "native-operation-registration"); return
        }
        operation = id; activeCase = mode; caseStarted = Date(); caseDriven = false
        timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in self?.driveCase() }
        if let timer = timer { RunLoop.main.add(timer, forMode: .common) }
        DispatchQueue.global(qos: .userInitiated).async {
            let response = nativeResponse(mode: "--capture-screenshot", input: Data(id.utf8))
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
            try verifySourceVisible(); caseDriven = true
            if mode == "request-cancel" {
                guard let operation = operation else { throw NativeError("FIXTURE: missing own token") }
                let cancelled = nativeResponse(mode: "--cancel-native-capture", input: Data(operation.utf8))
                try fixtureNeed(cancelled["ok"] as? Bool == true, "request cancellation was rejected")
            } else if mode == "escape-cancel" {
                guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else {
                    throw NativeError("FIXTURE: own Escape event creation failed")
                }
                NSApplication.shared.sendEvent(event)
            } else {
                try send(.leftMouseDown, point: point, panel: panel)
                let end = mode == "rectangle-phase1" ? CGPoint(x: point.x + 120, y: point.y + 80) : CGPoint(x: point.x + 1, y: point.y + 1)
                if mode == "rectangle-phase1" { try send(.leftMouseDragged, point: end, panel: panel) }
                try send(.leftMouseUp, point: end, panel: panel)
            }
        } catch { finish("failed", reason: String(describing: error)) }
    }

    func completeCase(_ mode: String, id: String, response: [String: Any]) {
        guard !finished, activeCase == mode, operation == id else { return }
        timer?.invalidate(); timer = nil
        _ = nativeResponse(mode: "--end-native-capture", input: Data(id.utf8)); operation = nil
        do {
            try fixtureNeed(caseDriven, "native screenshot completed before own gesture was dispatched")
            try fixtureNeed(!NSApplication.shared.windows.contains(where: { $0 is CaptureSelectionPanel && $0.isVisible }), "native selector left visible panels")
            try fixtureNeed(response["text"] == nil, "F1 unexpectedly invoked OCR")
            try verifySourceVisible()
            var record: [String: Any] = ["mode": mode, "ok": true, "hoverOutlineVerified": true, "visiblePanelsAfter": 0,
                                          "exactOwnedSourceRevalidated": true, "ownAppKitEventDispatched": mode != "request-cancel",
                                          "nativeCancellationEndpointDispatched": mode == "request-cancel"]
            if mode == "escape-cancel" || mode == "request-cancel" {
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
                let width = Int((mode == "rectangle-phase1" ? 120 : target.frame.width) * sourceScale)
                let height = Int((mode == "rectangle-phase1" ? 80 : target.frame.height) * sourceScale)
                try fixtureNeed(image.width == width && image.height == height, "real screenshot dimensions differ from exact source/drag frame")
                try verifyPixels(image, phase: mode == "window-phase2" ? 2 : 1)
                record["imageWidth"] = width; record["imageHeight"] = height
                record["generatedVisiblePixelsVerified"] = true; record["ownOverlayPixelsAbsent"] = true
            }
            cases.append(record); index += 1; activeCase = nil
            if index == modes.count { finish("passed") }
            else if modes[index] == "window-phase2" {
                try sourceInput?.write(contentsOf: Data("phase2\n".utf8))
                DispatchQueue.global(qos: .utility).async { self.readSource(phase: 2) }
            } else { beginCase() }
        } catch { finish("failed", reason: String(describing: error)) }
    }

    func verifyPixels(_ image: CGImage, phase: Int) throws {
        let row = image.width * 4
        var bytes = [UInt8](repeating: 0, count: row * image.height)
        let success = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: row, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        try fixtureNeed(success, "captured pixel normalization failed")
        let expected = phase == 1 ? [0, 255, 0] : [255, 0, 0]
        // Every pixel, including edges: blue outlines, loupe plates, frozen
        // phase-1 pixels, and accidental desktop pixels must fail the probe.
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            try fixtureNeed((0..<3).allSatisfy { abs(Int(bytes[offset + $0]) - expected[$0]) <= 5 }
                            && bytes[offset + 3] >= 250, "captured image is not solely current generated visible pixels")
        }
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
