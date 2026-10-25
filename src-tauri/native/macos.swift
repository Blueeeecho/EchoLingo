import AppKit
import ApplicationServices
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Vision

// Production links this code into the EchoLingo process so Accessibility and
// screen-capture permissions belong to the app, not a changing cached helper.
// A CLI build remains available for noninteractive native CI self-tests.
// Capture/selection never activates EchoLingo; the source app stays foreground.
struct NativeError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

func emit(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

func requireAccessibility() throws {
    guard AXIsProcessTrusted() else {
        throw NativeError("PERMISSION: 请在 EchoLingo 设置中开启辅助功能权限后重试；也可以直接输入或粘贴文字。")
    }
}

func focusedElement() -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
          let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

func accessibilitySelection() throws -> String? {
    guard let element = focusedElement() else { return nil }
    var selected: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
       let text = selected as? String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Editors may copy the entire current line when Cmd+C has no
            // selection. An explicitly empty AX selection must not fall back.
            throw NativeError("NO_SELECTION: No text is selected in the source application.")
        }
        return text
    }
    return nil
}

struct SavedPasteboard {
    let items: [NSPasteboardItem]
    init(_ pasteboard: NSPasteboard) throws {
        // Materialize every representation before sending Cmd+C. Keeping the
        // original NSPasteboardItem alone would retain a lazy provider that can
        // become invalid as soon as the source application's clipboard changes.
        var copies = [NSPasteboardItem]()
        let originals = pasteboard.pasteboardItems ?? []
        if originals.isEmpty && !(pasteboard.types ?? []).isEmpty {
            throw NativeError("CLIPBOARD: Clipboard representations cannot be materialized safely. Use screenshot or clipboard translation instead.")
        }
        for original in originals {
            let copy = NSPasteboardItem()
            for type in original.types {
                guard let data = original.data(forType: type) else {
                    throw NativeError("CLIPBOARD: Cannot preserve clipboard format \(type.rawValue). Selection fallback was stopped before changing the clipboard; use screenshot or clipboard translation instead.")
                }
                guard copy.setData(data, forType: type) else {
                    throw NativeError("CLIPBOARD: Cannot snapshot clipboard format \(type.rawValue).")
                }
            }
            copies.append(copy)
        }
        items = copies
    }
    func restore(_ pasteboard: NSPasteboard) throws {
        pasteboard.clearContents()
        if !items.isEmpty && !pasteboard.writeObjects(items) {
            throw NativeError("CLIPBOARD_RESTORE_FAILED: The original clipboard could not be restored. The copied selection may still be on the clipboard.")
        }
    }
}

func selection() throws -> String {
    try requireAccessibility()
    if let text = try accessibilitySelection() { return text }
    let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    // The shortcut's modifiers must be released before a clean Cmd+C event.
    let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    let deadline = Date().addingTimeInterval(1.5)
    while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
        guard Date() < deadline else { throw NativeError("SELECTION: Release the shortcut keys and retry.") }
        Thread.sleep(forTimeInterval: 0.02)
    }
    guard foregroundPID == NSWorkspace.shared.frontmostApplication?.processIdentifier else {
        throw NativeError("SELECTION: The foreground application changed. Select text in the source application and retry.")
    }
    let pasteboard = NSPasteboard.general
    let initialCount = pasteboard.changeCount
    let saved = try SavedPasteboard(pasteboard)
    guard pasteboard.changeCount == initialCount else {
        throw NativeError("CLIPBOARD_CHANGED: The clipboard changed while its formats were being preserved. Retry.")
    }
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else {
        throw NativeError("SELECTION: Could not create the copy keyboard event.")
    }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    let copyDeadline = Date().addingTimeInterval(1.2)
    while pasteboard.changeCount == initialCount && Date() < copyDeadline {
        Thread.sleep(forTimeInterval: 0.02)
    }
    guard pasteboard.changeCount != initialCount else {
        throw NativeError("NO_SELECTION: The application did not copy any selection. Try screenshot OCR for text that cannot be selected.")
    }
    let copyCount = pasteboard.changeCount
    let text = pasteboard.string(forType: .string)
    guard pasteboard.changeCount == copyCount else {
        throw NativeError("CLIPBOARD_CHANGED: Another copy operation occurred during selection capture; the newer clipboard was preserved. Retry.")
    }
    try saved.restore(pasteboard)
    guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw NativeError("NO_SELECTION: The selection did not contain plain text. Try screenshot OCR.")
    }
    return text
}

struct OCRLayoutLine {
    let text: String
    // Top-left-origin geometry. Values may be normalized or pixels; only
    // dimensionless ratios are used, so no image-size/pixel threshold is needed.
    let bounds: CGRect
}

func validOCRBounds(_ bounds: CGRect) -> Bool {
    return bounds.minX.isFinite && bounds.minY.isFinite && bounds.width.isFinite &&
        bounds.height.isFinite && bounds.width > 0 && bounds.height > 0
}

func structuralOCRLine(_ text: String) -> Bool {
    if text.hasPrefix(" ") || text.hasPrefix("\t") || text.contains("\t") || text.contains("|") { return true }
    let pattern = #"^\s*(?:[-*+\u2022]\s|\d+[.)]\s|#{1,6}\s|>\s|```|~~~|//|/\*|\*/|[{}]|(?:if|for|while|def|class|import|return|const|let|var|function)\b|https?://|www\.)"#
    return text.range(of: pattern, options: .regularExpression) != nil
}

func joinOCRLines(_ lines: [OCRLayoutLine], allowGeometry: Bool = true) -> String {
    let heights = lines.filter { validOCRBounds($0.bounds) }.map { $0.bounds.height }.sorted()
    guard allowGeometry, !heights.isEmpty else { return lines.map { $0.text }.joined(separator: "\n") }
    let middle = heights.count / 2
    let median = heights.count.isMultiple(of: 2) ? (heights[middle - 1] + heights[middle]) / 2 : heights[middle]
    var result = ""
    var insideCodeFence = false
    for (index, line) in lines.enumerated() {
        let trimmed = line.text.trimmingCharacters(in: .whitespaces)
        let fence = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
        if index > 0 {
            let previous = lines[index - 1].bounds
            let current = line.bounds
            var paragraphBreak = false
            let structured = insideCodeFence || structuralOCRLine(lines[index - 1].text) || structuralOCRLine(line.text)
            if !structured && validOCRBounds(previous) && validOCRBounds(current) {
                let referenceHeight = max(median, min(previous.height, current.height))
                let verticalGap = current.minY - previous.maxY
                let overlap = max(0, min(previous.maxX, current.maxX) - max(previous.minX, current.minX))
                let columnReset = overlap <= 0.1 * min(previous.width, current.width) &&
                    current.minY < previous.minY - 0.9 * referenceHeight
                paragraphBreak = verticalGap >= 0.9 * referenceHeight || columnReset
            }
            result += paragraphBreak ? "\n\n" : "\n"
        }
        // No sorting, merging, trimming, indentation editing, or list/code
        // rewriting: the recognizer's original line order and text are retained.
        result += line.text
        if fence { insideCodeFence.toggle() }
    }
    return result
}

func paragraphGeometrySelfTest() throws {
    let lines = [
        OCRLayoutLine(text: "first line", bounds: CGRect(x: 0, y: 0, width: 100, height: 10)),
        OCRLayoutLine(text: "second line", bounds: CGRect(x: 0, y: 14, width: 100, height: 10)),
        OCRLayoutLine(text: "next paragraph", bounds: CGRect(x: 0, y: 38, width: 100, height: 10)),
        OCRLayoutLine(text: "continued paragraph", bounds: CGRect(x: 0, y: 52, width: 100, height: 10)),
        OCRLayoutLine(text: "column two", bounds: CGRect(x: 130, y: 0, width: 100, height: 10)),
        OCRLayoutLine(text: "still column two", bounds: CGRect(x: 130, y: 14, width: 100, height: 10))
    ]
    let expected = "first line\nsecond line\n\nnext paragraph\ncontinued paragraph\n\ncolumn two\nstill column two"
    let scaled = lines.map { OCRLayoutLine(text: $0.text, bounds: CGRect(x: $0.bounds.minX / 1000,
                                                                       y: $0.bounds.minY / 1000,
                                                                       width: $0.bounds.width / 1000,
                                                                       height: $0.bounds.height / 1000)) }
    guard joinOCRLines(lines) == expected, joinOCRLines(scaled) == expected,
          joinOCRLines(lines, allowGeometry: false) == lines.map({ $0.text }).joined(separator: "\n") else {
        throw NativeError("SELF_TEST: Paragraph geometry, scaling, rotation fallback, or original line order was not preserved.")
    }
    let structured = [
        OCRLayoutLine(text: "- first item", bounds: CGRect(x: 0, y: 0, width: 100, height: 10)),
        OCRLayoutLine(text: "  indented continuation", bounds: CGRect(x: 10, y: 80, width: 90, height: 10)),
        OCRLayoutLine(text: "    return value;", bounds: CGRect(x: 20, y: 180, width: 80, height: 10))
    ]
    guard joinOCRLines(structured) == "- first item\n  indented continuation\n    return value;" else {
        throw NativeError("SELF_TEST: OCR layout changed a list or indented code line.")
    }
    let fenced = ["```text", "literal line", "another literal line", "```", "normal paragraph", "next paragraph"].enumerated().map {
        OCRLayoutLine(text: $0.element, bounds: CGRect(x: 0, y: $0.offset * 40, width: 100, height: 10))
    }
    guard joinOCRLines(fenced) == "```text\nliteral line\nanother literal line\n```\nnormal paragraph\n\nnext paragraph" else {
        throw NativeError("SELF_TEST: OCR layout inferred paragraph breaks inside a fenced block.")
    }
    let invalid = [
        OCRLayoutLine(text: "invalid bounds", bounds: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 10)),
        OCRLayoutLine(text: "keep line break", bounds: CGRect(x: 0, y: 80, width: 100, height: 10)),
        OCRLayoutLine(text: "zero height", bounds: CGRect(x: 0, y: 180, width: 100, height: 0))
    ]
    guard joinOCRLines(invalid) == "invalid bounds\nkeep line break\nzero height",
          joinOCRLines([]).isEmpty else {
        throw NativeError("SELF_TEST: OCR invalid or empty geometry was not handled conservatively.")
    }
}

// Exercise the same snapshot/restore used by selection fallback, on an isolated
// pasteboard. Never inspect or overwrite NSPasteboard.general or another app.
func privatePasteboardSelfTest() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let custom = NSPasteboard.PasteboardType("org.echolingo.self-test.binary")
    let unicode = "回声译 🪞\nquotes: \" ' ` $() ; & | \\ end\0"
    let second = "second fixture item 日本語"
    let fixtures: [[NSPasteboard.PasteboardType: Data]] = [
        [.string: Data(unicode.utf8),
         .html: Data("<p>EchoLingo <strong>回声译</strong></p>".utf8),
         .rtf: Data(#"{\rtf1\ansi EchoLingo fixture 2468}"#.utf8),
         custom: Data([0, 255, 128, 1, 13, 10])],
        [.string: Data(second.utf8), custom: Data()]
    ]
    let items = try fixtures.map { formats -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in formats {
            guard item.setData(data, forType: type) else {
                throw NativeError("SELF_TEST: Could not seed a private clipboard fixture.")
            }
        }
        return item
    }
    pasteboard.clearContents()
    guard pasteboard.writeObjects(items) else {
        throw NativeError("SELF_TEST: Could not write a private clipboard fixture.")
    }
    // AppKit may synthesize UTF-16 alongside UTF-8. Snapshot the materialized
    // fixture's full native representation set, then require all of it back.
    let materialized = try (pasteboard.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
        var formats: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            guard let data = item.data(forType: type) else {
                throw NativeError("SELF_TEST: A seeded clipboard fixture format was unavailable.")
            }
            formats[type] = data
        }
        return formats
    }
    guard materialized.count == fixtures.count,
          zip(materialized, fixtures).allSatisfy({ actual, expected in
              expected.allSatisfy { actual[$0.key] == $0.value }
          }) else {
        throw NativeError("SELF_TEST: Private clipboard fixture seeding changed an expected representation.")
    }
    let saved = try SavedPasteboard(pasteboard)
    pasteboard.clearContents()
    guard pasteboard.setString("temporary copied fixture", forType: .string) else {
        throw NativeError("SELF_TEST: Could not simulate a private clipboard copy.")
    }
    try saved.restore(pasteboard)
    let restored = pasteboard.pasteboardItems ?? []
    guard restored.count == materialized.count else {
        throw NativeError("SELF_TEST: Clipboard snapshot lost a pasteboard item.")
    }
    for (item, formats) in zip(restored, materialized) {
        guard Set(item.types) == Set(formats.keys) else {
            throw NativeError("SELF_TEST: Clipboard fixture type mismatch: \(item.types.map { $0.rawValue }.sorted()) vs \(formats.keys.map { $0.rawValue }.sorted()).")
        }
        for (type, expected) in formats {
            guard item.data(forType: type) == expected else {
                throw NativeError("SELF_TEST: Clipboard snapshot changed fixture format \(type.rawValue).")
            }
        }
    }
    pasteboard.clearContents()
    let empty = try SavedPasteboard(pasteboard)
    guard pasteboard.setString("temporary copy over an empty fixture", forType: .string) else {
        throw NativeError("SELF_TEST: Could not seed an empty-clipboard restoration fixture.")
    }
    try empty.restore(pasteboard)
    guard (pasteboard.pasteboardItems ?? []).isEmpty, (pasteboard.types ?? []).isEmpty else {
        throw NativeError("SELF_TEST: Restoring an empty clipboard retained copied data.")
    }
}

func pngSizeGuardSelfTest() throws {
    for (data, expectedPrefix) in [(Data(), "CAPTURE:"), (Data(repeating: 0, count: maximumPNGBytes + 1), "CAPTURE_TOO_LARGE:")] {
        do {
            _ = try encodePNG(data)
            throw NativeError("SELF_TEST: Invalid PNG byte count was accepted.")
        } catch let error as NativeError {
            guard error.message.hasPrefix(expectedPrefix) else { throw error }
        }
    }
    // The encoder's inclusive byte limit is separate from image decoding. Exact
    // boundary bytes verify it without capturing a screen or retaining a file.
    let boundary = Data(repeating: 0, count: maximumPNGBytes)
    guard Data(base64Encoded: try encodePNG(boundary)) == boundary else {
        throw NativeError("SELF_TEST: The exact PNG byte limit did not roundtrip.")
    }
}

func recognize(_ handler: VNImageRequestHandler) throws -> String {
    let request = VNRecognizeTextRequest()
    // Vision cancellation is cooperative; unlike the former subprocess, the
    // in-process bridge cannot forcibly kill OCR without killing the app.
    let deadline = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    deadline.schedule(deadline: .now() + 30)
    deadline.setEventHandler { request.cancel() }
    deadline.resume()
    defer { deadline.setEventHandler {}; deadline.cancel() }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let supported = try request.supportedRecognitionLanguages()
    let preferred = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
    request.recognitionLanguages = preferred.filter { supported.contains($0) }
    if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
    do { try handler.perform([request]) }
    catch is CancellationError { throw NativeError("OCR_TIMEOUT: 文字识别超时，请缩小区域后重试。") }
    let observations = request.results ?? []
    // Axis-normalized edge skew avoids treating normalized x/y units as an
    // undistorted pixel angle. Tall, vertical, or noticeably tilted boxes disable
    // layout inference for the whole result; their original line breaks remain.
    let allowGeometry = observations.allSatisfy { observation in
        let box = observation.boundingBox
        guard validOCRBounds(box) else { return false }
        return observation.topRight.x > observation.topLeft.x &&
            abs(observation.topRight.y - observation.topLeft.y) <= 0.2 * box.height &&
            abs(observation.topLeft.x - observation.bottomLeft.x) <= 0.2 * box.width
    }
    let lines = observations.compactMap { observation -> OCRLayoutLine? in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        let box = observation.boundingBox
        return OCRLayoutLine(text: text, bounds: CGRect(x: box.minX, y: 1 - box.maxY,
                                                        width: box.width, height: box.height))
    }
    let text = joinOCRLines(lines, allowGeometry: allowGeometry)
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw NativeError("NO_TEXT: No text was recognized. Select a larger, clearer area and retry.")
    }
    return text
}

func withCapturedRegion<T>(_ operation: (URL) throws -> T) throws -> T {
    // Hotkeys only inspect permission. Requests must come from the explicit
    // Settings action; never reopen a system prompt on each capture attempt.
    guard CGPreflightScreenCaptureAccess() else {
        throw NativeError("PERMISSION: 请在 EchoLingo 设置中开启屏幕录制权限后重试；系统可能要求重新打开应用。")
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("echolingo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                          attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("selection.png")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    // Native capture supplies a crosshair, Escape cancellation, Retina pixel
    // coordinates and multi-display selection without involving our app window.
    process.arguments = ["-i", "-x", "-t", "png", file.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    let deadline = Date().addingTimeInterval(120)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if process.isRunning {
        process.terminate()
        process.waitUntilExit()
        throw NativeError("CANCELLED: Screenshot selection timed out after 120 seconds.")
    }
    process.waitUntilExit()
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw NativeError("CANCELLED: Screenshot selection was cancelled. If capture never appeared, check Screen Recording permission.")
    }
    guard process.terminationStatus == 0 else {
        throw NativeError("CAPTURE: macOS could not capture the selected region. Check Screen Recording permission.")
    }
    return try operation(file)
}

func captureOCR() throws -> String {
    return try withCapturedRegion { file in
        try recognize(VNImageRequestHandler(url: file, options: [:]))
    }
}

let maximumPNGBytes = 8 * 1024 * 1024

func encodePNG(_ data: Data) throws -> String {
    guard !data.isEmpty else { throw NativeError("CAPTURE: Captured PNG was empty.") }
    guard data.count <= maximumPNGBytes else {
        throw NativeError("CAPTURE_TOO_LARGE: Captured PNG exceeds 8 MiB. Select a smaller region.")
    }
    return data.base64EncodedString()
}

func captureImage() throws -> String {
    return try withCapturedRegion { file in
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumPNGBytes else {
            throw NativeError("CAPTURE_TOO_LARGE: Captured PNG exceeds 8 MiB. Select a smaller region.")
        }
        return try encodePNG(Data(contentsOf: file))
    }
}

func permissionStatus() -> [String: Any] {
    return ["platform": "macos", "supported": true, "identity": "application-process",
            "runningBundledApp": Bundle.main.bundleURL.pathExtension == "app",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "processId": ProcessInfo.processInfo.processIdentifier,
            "accessibilityGranted": AXIsProcessTrusted(),
            "screenCaptureGranted": CGPreflightScreenCaptureAccess()]
}

func onMainThread<T>(_ action: () throws -> T) rethrows -> T {
    if Thread.isMainThread { return try action() }
    return try DispatchQueue.main.sync(execute: action)
}

func requestPermission(_ kind: String) throws -> [String: Any] {
    // Only the explicit Settings IPC reaches this function. Both APIs inspect
    // this app process; permission checks in hotkeys never set a prompt option.
    switch kind {
    case "accessibility":
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = onMainThread { AXIsProcessTrustedWithOptions(options) }
        }
    case "screenCapture":
        if !CGPreflightScreenCaptureAccess() { _ = onMainThread { CGRequestScreenCaptureAccess() } }
    default: throw NativeError("PERMISSION_KIND: 不支持的权限类型。")
    }
    return permissionStatus()
}

func openPermissionSettings(_ kind: String) throws {
    let pane: String
    switch kind {
    case "accessibility": pane = "Privacy_Accessibility"
    case "screenCapture": pane = "Privacy_ScreenCapture"
    default: throw NativeError("PERMISSION_KIND: 不支持的权限类型。")
    }
    // Fixed local System Settings destination; no user-controlled URL/scheme.
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"),
          onMainThread({ NSWorkspace.shared.open(url) }) else {
        throw NativeError("PERMISSION_SETTINGS: 无法打开系统设置，请手动进入隐私与安全性。")
    }
}

func diagnostics() -> [String: Any] {
    let languages = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
    return ["platform": "macos", "helper": "swift-appkit-vision", "localOcr": true,
            "nativeExecution": "in-process-static", "permissions": permissionStatus(),
            "accessibilityGranted": AXIsProcessTrusted(),
            "screenCaptureGranted": CGPreflightScreenCaptureAccess(),
            "ocrLanguages": languages, "ocrEngine": "Apple Vision",
            "selection": "Accessibility selected text, then Cmd+C with clipboard restoration",
            "screens": displayDiagnostics()]
}

func displayDiagnostics() -> [[String: Any]] {
    // CoreGraphics display inspection works on the worker used by Rust tests
    // and IPC. Do not ask AppKit for NSScreen.screens off the main thread or
    // synchronously dispatch to an absent main-loop in the CLI/test host.
    var displays = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else { return [] }
    return displays.prefix(Int(count)).map { display in
        let bounds = CGDisplayBounds(display)
        let mode = CGDisplayCopyDisplayMode(display)
        let scale = mode.map { $0.width > 0 ? Double($0.pixelWidth) / Double($0.width) : 1 } ?? 1
        return ["width": bounds.width, "height": bounds.height, "scale": scale]
    }
}

func selfTest(input: Data = Data()) throws -> [String: Any] {
    if !input.isEmpty && String(data: input, encoding: .utf8) != "回声译\0EchoLingo 🪞" {
        throw NativeError("SELF_TEST: Native bridge input did not preserve UTF-8 and NUL.")
    }
    try paragraphGeometrySelfTest()
    // AppKit can fulfill synthesized clipboard-format promises synchronously.
    // Run this fixture only in the CLI's actual main thread; a Rust unit-test
    // worker has no main event loop, so main.sync would deadlock there.
    let privatePasteboardTested = Thread.isMainThread
    if privatePasteboardTested { try privatePasteboardSelfTest() }
    try pngSizeGuardSelfTest()
    let width = 1100, height = 160
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NativeError("SELF_TEST: Could not create image context.")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "EchoLingo translation 2468", attributes: attributes))
    context.textPosition = CGPoint(x: 30, y: 65)
    CTLineDraw(line, context)
    guard let image = context.makeImage() else { throw NativeError("SELF_TEST: Could not create test bitmap.") }
    let recognitionStart = ProcessInfo.processInfo.systemUptime
    let text = try recognize(VNImageRequestHandler(cgImage: image, options: [:]))
    let recognitionMilliseconds = (ProcessInfo.processInfo.systemUptime - recognitionStart) * 1000
    guard text.lowercased().contains("echolingo"), text.contains("2468") else {
        throw NativeError("SELF_TEST: Local OCR did not recognize the generated fixture.")
    }
    let png = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) else {
        throw NativeError("SELF_TEST: Could not create PNG encoder.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination),
          Data(base64Encoded: try encodePNG(png as Data)) == png as Data else {
        throw NativeError("SELF_TEST: PNG base64 roundtrip failed.")
    }
    return ["ocrFixturePassed": true, "recognized": text, "diagnostics": diagnostics(),
            "ocrFixtureElapsedMs": recognitionMilliseconds,
            "ocrFixtureTimingScope": "Generated 1100x160 image; Vision recognize only; excludes capture, image drawing and application startup",
            "pngBase64RoundtripPassed": true, "paragraphGeometryFixturePassed": true,
            "privatePasteboardFixturePassed": privatePasteboardTested,
            "privatePasteboardFixtureSkipped": !privatePasteboardTested, "pngSizeGuardsPassed": true,
            "interactiveCaptureTested": false, "generalClipboardTouched": false,
            "clipboardChanged": false, "bridgeInputPassed": !input.isEmpty]
}

func nativeResponse(mode: String, input: Data = Data()) -> [String: Any] {
    do {
        switch mode {
        case "--selected-text": return ["ok": true, "text": try selection()]
        case "--capture-ocr": return ["ok": true, "text": try captureOCR()]
        case "--capture-image": return ["ok": true, "imageBase64": try captureImage()]
        case "--clipboard":
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
                throw NativeError("CLIPBOARD_EMPTY: The clipboard does not contain text.")
            }
            return ["ok": true, "text": text]
        case "--copy":
            guard input.count <= 2 * 1024 * 1024, let text = String(data: input, encoding: .utf8) else {
                throw NativeError("CLIPBOARD: Invalid or oversized UTF-8 input.")
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else { throw NativeError("CLIPBOARD: Cannot write to clipboard.") }
            return ["ok": true, "text": ""]
        case "--permissions": return ["ok": true, "permissions": permissionStatus()]
        case "--request-accessibility", "--request-screenCapture":
            let kind = String(mode.dropFirst("--request-".count))
            return ["ok": true, "permissions": try requestPermission(kind)]
        case "--open-settings-accessibility", "--open-settings-screenCapture":
            try openPermissionSettings(String(mode.dropFirst("--open-settings-".count)))
            return ["ok": true, "text": ""]
        case "--diagnostics": return ["ok": true, "diagnostics": diagnostics()]
        case "--self-test": return ["ok": true, "diagnostics": try selfTest(input: input)]
        default: throw NativeError("NATIVE_MODE: Unsupported native operation.")
        }
    } catch let error as NativeError {
        return ["ok": false, "error": error.message]
    } catch {
        return ["ok": false, "error": "NATIVE: \(error.localizedDescription)"]
    }
}

#if ECHOLINGO_LIBRARY
// An explicit length preserves NUL/Unicode clipboard input. The caller owns the
// returned buffer until echolingo_native_free; no Swift object crosses the ABI.
@_cdecl("echolingo_native_run")
public func echolingoNativeRun(_ mode: UnsafePointer<CChar>?, _ input: UnsafePointer<UInt8>?,
                               _ inputLength: Int, _ outputLength: UnsafeMutablePointer<Int>?) -> UnsafeMutablePointer<UInt8>? {
    return autoreleasepool {
        guard let mode = mode, let outputLength = outputLength else { return nil }
        outputLength.pointee = 0
        guard inputLength >= 0, inputLength <= 2 * 1024 * 1024,
              inputLength == 0 || input != nil else { return nil }
        let data = inputLength == 0 ? Data() : Data(bytes: input!, count: inputLength)
        let object = nativeResponse(mode: String(cString: mode), input: data)
        guard let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        let result = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, encoded.count))
        encoded.copyBytes(to: result, count: encoded.count)
        outputLength.pointee = encoded.count
        return result
    }
}

@_cdecl("echolingo_native_free")
public func echolingoNativeFree(_ buffer: UnsafeMutablePointer<UInt8>?) {
    buffer?.deallocate()
}
#else
@main
struct EchoLingoNativeCLI {
    static func main() {
        let mode = CommandLine.arguments.dropFirst().first ?? "--diagnostics"
        let input = mode == "--copy" ? FileHandle.standardInput.readDataToEndOfFile() : Data()
        let response = nativeResponse(mode: mode, input: input)
        emit(response)
        if response["ok"] as? Bool != true { exit(1) }
    }
}
#endif
