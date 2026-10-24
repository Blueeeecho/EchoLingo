import AppKit
import ApplicationServices
import CoreGraphics
import CoreText
import Foundation
import Vision

// This command-line helper never activates an application or opens a main window.
// The Tauri caller must keep the previously focused application in the foreground.
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
        throw NativeError("PERMISSION: Enable Accessibility for EchoLingo / echolingo-native-helper in System Settings → Privacy & Security → Accessibility, then retry. Clipboard translation does not require this permission.")
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
}

func recognize(_ handler: VNImageRequestHandler) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let supported = try request.supportedRecognitionLanguages()
    let preferred = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
    request.recognitionLanguages = preferred.filter { supported.contains($0) }
    if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
    try handler.perform([request])
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
    if !CGPreflightScreenCaptureAccess() && !CGRequestScreenCaptureAccess() {
        throw NativeError("PERMISSION: Enable Screen Recording for EchoLingo / echolingo-native-helper in System Settings → Privacy & Security, then reopen EchoLingo and retry.")
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

func diagnostics() -> [String: Any] {
    let languages = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
    return ["platform": "macos", "helper": "swift-appkit-vision", "localOcr": true,
            "accessibilityGranted": AXIsProcessTrusted(),
            "screenCaptureGranted": CGPreflightScreenCaptureAccess(),
            "ocrLanguages": languages, "ocrEngine": "Apple Vision",
            "selection": "Accessibility selected text, then Cmd+C with clipboard restoration",
            "screens": NSScreen.screens.map { ["width": $0.frame.width, "height": $0.frame.height, "scale": $0.backingScaleFactor] }]
}

func selfTest() throws -> [String: Any] {
    try paragraphGeometrySelfTest()
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
    let text = try recognize(VNImageRequestHandler(cgImage: image, options: [:]))
    guard text.lowercased().contains("echolingo"), text.contains("2468") else {
        throw NativeError("SELF_TEST: Local OCR did not recognize the generated fixture.")
    }
    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
          Data(base64Encoded: try encodePNG(png)) == png else {
        throw NativeError("SELF_TEST: PNG base64 roundtrip failed.")
    }
    return ["ocrFixturePassed": true, "recognized": text, "diagnostics": diagnostics(),
            "pngBase64RoundtripPassed": true, "paragraphGeometryFixturePassed": true,
            "interactiveCaptureTested": false, "clipboardChanged": false]
}

do {
    let mode = CommandLine.arguments.dropFirst().first ?? "--diagnostics"
    switch mode {
    case "--selected-text": emit(["ok": true, "text": try selection()])
    case "--capture-ocr": emit(["ok": true, "text": try captureOCR()])
    case "--capture-image": emit(["ok": true, "imageBase64": try captureImage()])
    case "--clipboard":
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { throw NativeError("CLIPBOARD_EMPTY: The clipboard does not contain text.") }
        emit(["ok": true, "text": text])
    case "--copy":
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { throw NativeError("CLIPBOARD: Invalid UTF-8 input.") }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw NativeError("CLIPBOARD: Cannot write to clipboard.") }
        emit(["ok": true, "text": ""])
    case "--diagnostics": emit(["ok": true, "diagnostics": diagnostics()])
    case "--self-test": emit(["ok": true, "diagnostics": try selfTest()])
    default: throw NativeError("Unsupported native helper mode.")
    }
} catch let error as NativeError {
    emit(["ok": false, "error": error.message])
    exit(1)
} catch {
    emit(["ok": false, "error": "NATIVE: \(error.localizedDescription)"])
    exit(1)
}
