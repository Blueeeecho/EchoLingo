import AppKit
import ApplicationServices
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Vision
import NaturalLanguage
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
#if canImport(Translation) && compiler(>=6.2)
import Translation
import SwiftUI
#endif

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

func focusedElement(applicationPID: pid_t? = nil) -> AXUIElement? {
    let pid = applicationPID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
    let roots = pid.map { [AXUIElementCreateApplication($0), AXUIElementCreateSystemWide()] }
        ?? [AXUIElementCreateSystemWide()]
    for root in roots {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
        let element = value as! AXUIElement
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success,
              pid == nil || owner == pid else { continue }
        return element
    }
    return nil
}

enum SelectionDecision: Equatable {
    case text(String)
    case empty
    case copy
}

// Use the same decision policy in production and fixtures. A nonzero public AX
// range can recover text when an app omits/inconsistently empties AXSelectedText.
// A confirmed empty selection must never copy an editor's entire current line.
// Known WPS document wrappers are an explicit exception: their zero ranges can
// be placeholders, just like their empty AXSelectedText. Do not extend that
// exception to ordinary editable text controls or other applications.
func selectionDecision(selectedText: String?, selectedRange: CFRange?, rangeText: String?, opaqueDocument: Bool = false) -> SelectionDecision {
    if let text = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .text(text)
    }
    if let range = selectedRange {
        guard range.location >= 0, range.length >= 0 else { return .empty }
        if range.length == 0 { return opaqueDocument ? .copy : .empty }
        if let text = rangeText {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .text(text)
        }
        return .copy
    }
    // A document/window wrapper (for example a custom office canvas) may
    // advertise an empty AXSelectedText without implementing text ranges.
    // That is unavailable information, unlike an editor's confirmed empty
    // range. Do not apply this exception to editable text controls.
    return selectedText == nil || (selectedRange == nil && opaqueDocument) ? .copy : .empty
}

func opaqueSelectionContainer(_ role: String?, bundleIdentifier: String?) -> Bool {
    // Keep this compatibility exception scoped to WPS; a generic editor may
    // implement copy-current-line while reporting no selection information.
    guard bundleIdentifier == "com.kingsoft.wpsoffice.mac" else { return false }
    return ["AXWindow", "AXGroup", "AXScrollArea", "AXLayoutArea", "AXDocument", "AXWebArea"].contains(role ?? "")
}

func unavailableSelectionRange(_ status: AXError) -> Bool {
    [.attributeUnsupported, .noValue, .notImplemented].contains(status)
}

func selectionRangesDecision(_ ranges: [CFRange], texts: [String?], opaqueDocument: Bool = false) -> SelectionDecision? {
    guard ranges.count <= 64, ranges.count == texts.count,
          ranges.allSatisfy({ $0.location >= 0 && $0.length >= 0 }) else { return nil }
    let positive = ranges.indices.filter { ranges[$0].length > 0 }
    guard !positive.isEmpty else { return opaqueDocument ? .copy : .empty }
    guard positive.allSatisfy({ texts[$0] != nil }) else { return .copy }
    let text = positive.compactMap { texts[$0] }.joined(separator: "\n")
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .text(text)
}

func requireSelectionForeground(_ original: pid_t?, _ current: pid_t?) throws {
    guard let original = original, original > 0, original == current else {
        throw NativeError("SELECTION: The foreground application changed. Select text in the source application and retry.")
    }
}

func requireUnprotectedSelection(_ subrole: String?) throws {
    guard subrole != kAXSecureTextFieldSubrole as String else {
        throw NativeError("NO_SELECTION: Selection capture is unavailable for a protected text field.")
    }
}

func accessibilitySelection(element: AXUIElement?) throws -> String? {
    guard let element = element else { return nil }
    var subrole: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success {
        try requireUnprotectedSelection(subrole as? String)
    }
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    var owner: pid_t = 0
    let bundleIdentifier = AXUIElementGetPid(element, &owner) == .success
        ? NSRunningApplication(processIdentifier: owner)?.bundleIdentifier : nil
    let opaqueDocument = opaqueSelectionContainer(role as? String, bundleIdentifier: bundleIdentifier)
    var selected: CFTypeRef?
    let selectedText = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success
        ? selected as? String : nil
    if let text = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
    var selectedRange: CFRange?
    var rangeValue: CFTypeRef?
    var rangeText: String?
    let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
    if selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
       rangeStatus == .success,
       let value = rangeValue, CFGetTypeID(value) == AXValueGetTypeID() {
        let axValue = value as! AXValue
        var range = CFRange(location: 0, length: 0)
        if AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
           range.location >= 0, range.length >= 0 {
            selectedRange = range
            if range.length > 0 {
                var extracted: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                              axValue, &extracted) == .success {
                    rangeText = extracted as? String
                }
            }
        }
    }
    var decision: SelectionDecision?
    // Some document implementations publish only the plural range API. Use
    // public ranges rather than reading the document's AXValue or contents.
    var pluralUnavailable = true
    if (selectedRange == nil || (opaqueDocument && selectedRange?.length == 0))
        && selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
        var values: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangesAttribute as CFString, &values)
        pluralUnavailable = unavailableSelectionRange(status)
        if status == .success,
           let values = values as? [Any], values.count <= 64 {
            var ranges = [CFRange](), texts = [String?]()
            for raw in values {
                let rawValue = raw as CFTypeRef
                guard CFGetTypeID(rawValue) == AXValueGetTypeID() else { break }
                let value = rawValue as! AXValue
                var range = CFRange(location: -1, length: -1)
                guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else { break }
                ranges.append(range)
                var extracted: CFTypeRef?
                let status = range.length > 0
                    ? AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, value, &extracted)
                    : .noValue
                texts.append(status == .success ? extracted as? String : nil)
            }
            if ranges.count == values.count {
                decision = selectionRangesDecision(ranges, texts: texts, opaqueDocument: opaqueDocument)
            }
        }
    }
    let rangesUnavailable = unavailableSelectionRange(rangeStatus) && pluralUnavailable
    switch decision ?? selectionDecision(selectedText: selectedText, selectedRange: selectedRange, rangeText: rangeText,
                                          opaqueDocument: opaqueDocument && (rangesUnavailable || selectedRange != nil)) {
    case .text(let text): return text
    case .empty: throw NativeError("NO_SELECTION: No text is selected in the source application.")
    case .copy: return nil
    }
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
    func restore(_ pasteboard: NSPasteboard, ifUnchangedSince expectedCount: Int? = nil) throws {
        if let expectedCount, pasteboard.changeCount != expectedCount {
            throw NativeError("CLIPBOARD_CHANGED: Another copy operation occurred during selection capture; the newer clipboard was preserved. Retry.")
        }
        pasteboard.clearContents()
        if !items.isEmpty && !pasteboard.writeObjects(items) {
            throw NativeError("CLIPBOARD_RESTORE_FAILED: The original clipboard could not be restored. The copied selection may still be on the clipboard.")
        }
    }
}

enum SelectionCopyObservation: Equatable {
    case waiting
    case completed(changeCount: Int, text: String?)
    case unchangedTimeout
    case unfinishedTimeout
    case superseded
}

// Pure production state machine: a clear/change notification alone is not a
// completed copy. Wait for stable text, but never follow another generation
// after accepting a text candidate; it may belong to a newer user operation.
struct SelectionCopyCompletion {
    let initialCount: Int
    private(set) var candidateCount: Int?
    private var candidateText: String?
    private var stableSince: TimeInterval?
    private var observedCount: Int?
    private var observedSince: TimeInterval?
    static let settleInterval: TimeInterval = 0.02

    init(initialCount: Int) {
        self.initialCount = initialCount
    }

    mutating func observe(countBefore: Int, text: String?, countAfter: Int,
                          now: TimeInterval, expired: Bool) -> SelectionCopyObservation {
        guard countBefore == countAfter else { return .superseded }
        if let candidateCount, candidateCount != countAfter { return .superseded }
        guard countAfter != initialCount else { return expired ? .unchangedTimeout : .waiting }
        if observedCount != countAfter {
            observedCount = countAfter
            observedSince = now
        }
        let nonemptyText = text.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        if let nonemptyText {
            if candidateCount == nil || candidateText != nonemptyText {
                candidateCount = countAfter
                candidateText = nonemptyText
                stableSince = now
            }
            if now - (stableSince ?? now) >= Self.settleInterval {
                return .completed(changeCount: countAfter, text: nonemptyText)
            }
        } else if candidateCount != nil {
            // Lazy materialization changed underneath the accepted text. Do
            // not restore an older snapshot over this ambiguous clipboard.
            return .superseded
        }
        // A bounded empty-copy response can still clear the original data.
        // Its generation is checked again inside restore before any write.
        guard expired else { return .waiting }
        guard candidateCount == nil, now - (observedSince ?? now) >= Self.settleInterval else {
            return .unfinishedTimeout
        }
        return .completed(changeCount: countAfter, text: nil)
    }
}

func requireSelectionFocus(_ expected: AXUIElement?, applicationPID: pid_t?) throws -> AXUIElement {
    guard let expected,
          let current = focusedElement(applicationPID: applicationPID), CFEqual(expected, current) else {
        throw NativeError("SELECTION: The focused control changed or is unavailable. Select text and retry.")
    }
    var subrole: CFTypeRef?
    if AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subrole) == .success {
        try requireUnprotectedSelection(subrole as? String)
    }
    return current
}

func requireSelectionModifiersReleased() throws {
    let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    guard CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty else {
        throw NativeError("SELECTION: Release the shortcut keys and retry.")
    }
}

func copiedSelection(_ pasteboard: NSPasteboard, initialCount: Int) throws -> (changeCount: Int, text: String?) {
    var completion = SelectionCopyCompletion(initialCount: initialCount)
    let deadline = ProcessInfo.processInfo.systemUptime + 1.2
    while true {
        let before = pasteboard.changeCount
        let text = before == initialCount ? nil : pasteboard.string(forType: .string)
        let after = pasteboard.changeCount
        let now = ProcessInfo.processInfo.systemUptime
        switch completion.observe(countBefore: before, text: text, countAfter: after, now: now, expired: now >= deadline) {
        case .waiting: Thread.sleep(forTimeInterval: 0.005)
        case .completed(let changeCount, let text): return (changeCount, text)
        case .unchangedTimeout:
            throw NativeError("NO_SELECTION: The application did not copy any selection. Try screenshot OCR for text that cannot be selected.")
        case .unfinishedTimeout:
            throw NativeError("CLIPBOARD_RESTORE_SKIPPED: The copied text did not settle before capture timed out; the original clipboard could not be restored safely. Current contents were preserved. Retry.")
        case .superseded:
            throw NativeError("CLIPBOARD_CHANGED: Another clipboard update occurred during selection capture; the newer clipboard was preserved. Retry.")
        }
    }
}

func selection() throws -> String {
    try requireAccessibility()
    let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    try requireSelectionForeground(foregroundPID, NSWorkspace.shared.frontmostApplication?.processIdentifier)
    let originalFocus = focusedElement(applicationPID: foregroundPID)
    if let text = try accessibilitySelection(element: originalFocus) {
        try requireSelectionForeground(foregroundPID, NSWorkspace.shared.frontmostApplication?.processIdentifier)
        return text
    }
    // The shortcut's modifiers must be released before a clean Cmd+C event.
    let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    let deadline = ProcessInfo.processInfo.systemUptime + 1.5
    while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw NativeError("SELECTION: Release the shortcut keys and retry.") }
        Thread.sleep(forTimeInterval: 0.02)
    }
    try requireSelectionForeground(foregroundPID, NSWorkspace.shared.frontmostApplication?.processIdentifier)
    let currentFocus = try requireSelectionFocus(originalFocus, applicationPID: foregroundPID)
    // The selection may have been cleared while the hotkey was released.
    // Recheck before touching the clipboard or sending the copy command.
    if let text = try accessibilitySelection(element: currentFocus) {
        try requireSelectionForeground(foregroundPID, NSWorkspace.shared.frontmostApplication?.processIdentifier)
        return text
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
    try requireSelectionForeground(foregroundPID, NSWorkspace.shared.frontmostApplication?.processIdentifier)
    _ = try requireSelectionFocus(originalFocus, applicationPID: foregroundPID)
    try requireSelectionModifiersReleased()
    guard pasteboard.changeCount == initialCount else {
        throw NativeError("CLIPBOARD_CHANGED: The clipboard changed before selection capture; its newer contents were preserved. Retry.")
    }
    try requireSelectionForeground(foregroundPID, NSWorkspace.shared.frontmostApplication?.processIdentifier)
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    let copied = try copiedSelection(pasteboard, initialCount: initialCount)
    // Restore even if focus changed while the already-posted copy completed.
    // A newer clipboard generation always wins over our saved representation.
    var contextError: Error?
    do {
        try requireSelectionForeground(foregroundPID, NSWorkspace.shared.frontmostApplication?.processIdentifier)
        _ = try requireSelectionFocus(originalFocus, applicationPID: foregroundPID)
    } catch { contextError = error }
    try saved.restore(pasteboard, ifUnchangedSince: copied.changeCount)
    if let contextError { throw contextError }
    let text = copied.text
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

func selectionPolicySelfTest() throws {
    let unicode = "回声译 🪞\n日本語\0EchoLingo"
    let positive = CFRange(location: 7, length: (unicode as NSString).length)
    let zero = CFRange(location: 7, length: 0)
    let fixtures: [(String?, CFRange?, String?, SelectionDecision)] = [
        (unicode, nil, nil, .text(unicode)),
        (nil, positive, unicode, .text(unicode)),
        ("", positive, unicode, .text(unicode)),
        (" \n", positive, unicode, .text(unicode)),
        (nil, positive, nil, .copy),
        ("", positive, nil, .copy),
        (nil, positive, " \n", .empty),
        (nil, zero, nil, .empty),
        ("", zero, nil, .empty),
        (nil, nil, nil, .copy),
        ("", nil, nil, .empty),
        (" \n", nil, nil, .empty),
        ("", CFRange(location: -1, length: 1), nil, .empty)
    ]
    for (selectedText, selectedRange, rangeText, expected) in fixtures {
        guard selectionDecision(selectedText: selectedText, selectedRange: selectedRange, rangeText: rangeText) == expected else {
            throw NativeError("SELF_TEST: Selection range recovery or empty-selection copy protection failed.")
        }
    }
    for role in ["AXWindow", "AXGroup", "AXScrollArea", "AXLayoutArea", "AXDocument", "AXWebArea", "AXTextArea", "AXTextField", "AXSearchField", "AXComboBox", "AXButton", ""] {
        let opaque = opaqueSelectionContainer(role, bundleIdentifier: "com.kingsoft.wpsoffice.mac")
        guard selectionDecision(selectedText: "", selectedRange: nil, rangeText: nil, opaqueDocument: opaque)
                == (opaque ? .copy : .empty),
              selectionDecision(selectedText: "", selectedRange: zero, rangeText: nil, opaqueDocument: opaque)
                == (opaque ? .copy : .empty),
              selectionDecision(selectedText: nil, selectedRange: zero, rangeText: nil, opaqueDocument: opaque)
                == (opaque ? .copy : .empty),
              selectionDecision(selectedText: unicode, selectedRange: zero, rangeText: nil, opaqueDocument: opaque) == .text(unicode),
              selectionDecision(selectedText: "", selectedRange: positive, rangeText: unicode, opaqueDocument: opaque) == .text(unicode),
              selectionDecision(selectedText: "", selectedRange: CFRange(location: -1, length: 3), rangeText: nil,
                                opaqueDocument: opaque) == .empty,
              !opaqueSelectionContainer(role, bundleIdentifier: "fixture.generic-editor"),
              !opaqueSelectionContainer(role, bundleIdentifier: nil) else {
            throw NativeError("SELF_TEST: WPS document placeholders or ordinary editable empty-range protection failed.")
        }
    }
    for status in [AXError.success, .attributeUnsupported, .noValue, .notImplemented, .cannotComplete, .invalidUIElement, .failure, .apiDisabled] {
        guard unavailableSelectionRange(status) == [.attributeUnsupported, .noValue, .notImplemented].contains(status) else {
            throw NativeError("SELF_TEST: Invalid or timed-out accessibility queries were treated as unavailable selection ranges.")
        }
    }
    guard selectionRangesDecision([positive], texts: [unicode]) == .text(unicode),
          selectionRangesDecision([zero, positive], texts: [nil, unicode]) == .text(unicode),
          selectionRangesDecision([positive, positive], texts: ["first", "second"]) == .text("first\nsecond"),
          selectionRangesDecision([positive], texts: [nil]) == .copy,
          selectionRangesDecision([zero], texts: [nil]) == .empty,
          selectionRangesDecision([zero], texts: [nil], opaqueDocument: true) == .copy,
          selectionRangesDecision([positive], texts: [unicode], opaqueDocument: true) == .text(unicode),
          selectionRangesDecision([positive], texts: [" \n"], opaqueDocument: true) == .empty,
          selectionRangesDecision([positive], texts: [" \n"]) == .empty,
          selectionRangesDecision([], texts: []) == .empty,
          selectionRangesDecision([], texts: [], opaqueDocument: true) == .copy,
          selectionRangesDecision([positive], texts: []) == nil,
          selectionRangesDecision([CFRange(location: -1, length: 3)], texts: [nil]) == nil,
          selectionRangesDecision(Array(repeating: positive, count: 65), texts: Array(repeating: unicode, count: 65)) == nil else {
        throw NativeError("SELF_TEST: Plural text-range recovery or its bounds failed.")
    }
    let foregroundFixtures: [(pid_t?, pid_t?, Bool)] = [
        (123, 123, true), (123, 456, false), (123, nil, false),
        (nil, 123, false), (nil, nil, false), (0, 0, false), (-1, -1, false)
    ]
    for (original, current, expected) in foregroundFixtures {
        var accepted = true
        do { try requireSelectionForeground(original, current) }
        catch let error as NativeError {
            guard error.message.hasPrefix("SELECTION:") else { throw error }
            accepted = false
        }
        guard accepted == expected else {
            throw NativeError("SELF_TEST: Selection foreground guard accepted an unavailable or changed application.")
        }
    }
    for subrole in [nil, "AXSearchField", kAXSecureTextFieldSubrole as String] as [String?] {
        var accepted = true
        do { try requireUnprotectedSelection(subrole) }
        catch let error as NativeError {
            guard error.message.hasPrefix("NO_SELECTION:") else { throw error }
            accepted = false
        }
        guard accepted == (subrole != kAXSecureTextFieldSubrole as String) else {
            throw NativeError("SELF_TEST: Protected selection policy failed.")
        }
    }
    try selectionCopyPolicySelfTest()
}

func selectionCopyPolicySelfTest() throws {
    var unchanged = SelectionCopyCompletion(initialCount: 10)
    guard unchanged.observe(countBefore: 10, text: "old clipboard text", countAfter: 10, now: 0, expired: false) == .waiting,
          unchanged.observe(countBefore: 10, text: "old clipboard text", countAfter: 10, now: 1.2, expired: true) == .unchangedTimeout else {
        throw NativeError("SELF_TEST: An unchanged clipboard was mistaken for copied selection.")
    }
    var deferred = SelectionCopyCompletion(initialCount: 10)
    guard deferred.observe(countBefore: 11, text: nil, countAfter: 11, now: 0.01, expired: false) == .waiting,
          deferred.observe(countBefore: 11, text: "", countAfter: 11, now: 0.02, expired: false) == .waiting,
          deferred.observe(countBefore: 12, text: "selected fixture", countAfter: 12, now: 0.1, expired: false) == .waiting,
          deferred.observe(countBefore: 12, text: "selected fixture", countAfter: 12, now: 0.13, expired: false)
            == .completed(changeCount: 12, text: "selected fixture") else {
        throw NativeError("SELF_TEST: A clear-then-write clipboard copy completed too soon or lost its text.")
    }
    var newer = SelectionCopyCompletion(initialCount: 10)
    guard newer.observe(countBefore: 11, text: "selected fixture", countAfter: 11, now: 0.1, expired: false) == .waiting,
          newer.observe(countBefore: 12, text: "newer user fixture", countAfter: 12, now: 0.13, expired: false) == .superseded else {
        throw NativeError("SELF_TEST: A newer clipboard operation replaced the accepted copy candidate.")
    }
    var duringRead = SelectionCopyCompletion(initialCount: 10)
    guard duringRead.observe(countBefore: 11, text: "fixture", countAfter: 12, now: 0.1, expired: false) == .superseded else {
        throw NativeError("SELF_TEST: A clipboard write during materialization was accepted.")
    }
    var empty = SelectionCopyCompletion(initialCount: 10)
    guard empty.observe(countBefore: 11, text: " \n", countAfter: 11, now: 0.1, expired: false) == .waiting,
          empty.observe(countBefore: 11, text: nil, countAfter: 11, now: 1.2, expired: true)
            == .completed(changeCount: 11, text: nil) else {
        throw NativeError("SELF_TEST: Empty copy did not wait or provide its guarded restoration generation.")
    }
    var lazy = SelectionCopyCompletion(initialCount: 10)
    guard lazy.observe(countBefore: 11, text: "first fixture", countAfter: 11, now: 0, expired: false) == .waiting,
          lazy.observe(countBefore: 11, text: "completed fixture", countAfter: 11, now: 0.01, expired: false) == .waiting,
          lazy.observe(countBefore: 11, text: "completed fixture", countAfter: 11, now: 0.025, expired: false) == .waiting,
          lazy.observe(countBefore: 11, text: "completed fixture", countAfter: 11, now: 0.04, expired: false)
            == .completed(changeCount: 11, text: "completed fixture") else {
        throw NativeError("SELF_TEST: Lazy clipboard text settled before its final representation.")
    }
    var clearedCandidate = SelectionCopyCompletion(initialCount: 10)
    guard clearedCandidate.observe(countBefore: 11, text: "selected fixture", countAfter: 11, now: 0, expired: false) == .waiting,
          clearedCandidate.observe(countBefore: 11, text: nil, countAfter: 11, now: 0.01, expired: false) == .superseded else {
        throw NativeError("SELF_TEST: An invalidated candidate was restored over an ambiguous clipboard.")
    }
    var late = SelectionCopyCompletion(initialCount: 10)
    guard late.observe(countBefore: 11, text: "late fixture", countAfter: 11, now: 1.19, expired: false) == .waiting,
          late.observe(countBefore: 11, text: "late fixture", countAfter: 11, now: 1.2, expired: true) == .unfinishedTimeout else {
        throw NativeError("SELF_TEST: The copy deadline bypassed text stabilization.")
    }
    var lateClear = SelectionCopyCompletion(initialCount: 10)
    guard lateClear.observe(countBefore: 11, text: nil, countAfter: 11, now: 1.2, expired: true) == .unfinishedTimeout else {
        throw NativeError("SELF_TEST: A new clipboard generation at the deadline was restored too early.")
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
    let expectedCopyCount = pasteboard.changeCount
    pasteboard.clearContents()
    guard pasteboard.setString("newer private fixture", forType: .string) else {
        throw NativeError("SELF_TEST: Could not seed a newer clipboard fixture.")
    }
    do {
        try saved.restore(pasteboard, ifUnchangedSince: expectedCopyCount)
        throw NativeError("SELF_TEST: A newer clipboard generation was overwritten.")
    } catch let error as NativeError {
        guard error.message.hasPrefix("CLIPBOARD_CHANGED:"),
              pasteboard.string(forType: .string) == "newer private fixture" else { throw error }
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

func withCapturedRegion<T>(_ operation: (CGImage) throws -> T) throws -> T {
    // Hotkeys only inspect permission. Requests must come from the explicit
    // Settings action; never reopen a system prompt on each capture attempt.
    guard CGPreflightScreenCaptureAccess() else {
        throw NativeError("PERMISSION: 请在 EchoLingo 设置中开启屏幕录制权限后重试；系统可能要求重新打开应用。")
    }
    // The transparent selector and screenshot API now share this application's
    // process identity. Images stay in memory and are released after OCR/API
    // encoding; neither a helper process nor a temporary screenshot is created.
    return try operation(captureNativeRegionImage())
}

func captureOCR() throws -> String {
    return try withCapturedRegion { image in
        try recognize(VNImageRequestHandler(cgImage: image, options: [:]))
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
    return try withCapturedRegion { image in
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) else {
            throw NativeError("CAPTURE: 无法创建截图图像。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NativeError("CAPTURE: 无法编码截图图像。") }
        return try encodePNG(png as Data)
    }
}

func screenCapturePermissionFields(preflight: Bool, requestState: String? = nil) -> [String: Any] {
    // A false preflight is not proof that a visible System Settings switch is
    // off: stale registration and OS/API disagreements need explicit diagnosis.
    // Never turn a successful earlier request into cached capture authority.
    var result: [String: Any] = ["screenCaptureGranted": preflight,
                                "screenCapturePreflightGranted": preflight,
                                "screenCaptureState": preflight ? "granted" : "unconfirmed"]
    if let state = requestState {
        result["screenCaptureRequestState"] = state
        let known = state == "available" || state == "denied"
        let consistent = !known || preflight == (state == "available")
        result["screenCaptureAuthorizationConsistent"] = consistent
        if !consistent { result["screenCaptureState"] = "inconsistent" }
    }
    return result
}

func permissionStatus(screenCaptureRequestState: String? = nil) -> [String: Any] {
    var result: [String: Any] = ["platform": "macos", "supported": true, "identity": "application-process",
            "runningBundledApp": Bundle.main.bundleURL.pathExtension == "app",
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "bundlePath": Bundle.main.bundleURL.path,
            "processId": ProcessInfo.processInfo.processIdentifier,
            "accessibilityGranted": AXIsProcessTrusted()]
    result.merge(screenCapturePermissionFields(preflight: CGPreflightScreenCaptureAccess(),
                                              requestState: screenCaptureRequestState)) { _, new in new }
    return result
}

// This gate and waiter hold only the one explicit request's lifecycle. They do
// not retain a grant, window/app metadata or screenshot, and never change a
// hotkey's passive CGPreflightScreenCaptureAccess guard.
final class ScreenCapturePermissionRequest {
    private static let gate = NSLock()
    private static var inFlight = false
    private let condition = NSCondition()
    private var result: String?
    static func begin() -> ScreenCapturePermissionRequest? {
        gate.lock(); defer { gate.unlock() }
        guard !inFlight else { return nil }
        inFlight = true
        return ScreenCapturePermissionRequest()
    }
    func finish(_ state: String) {
        condition.lock()
        guard result == nil else { condition.unlock(); return }
        result = state
        condition.broadcast()
        condition.unlock()
        Self.gate.lock(); Self.inFlight = false; Self.gate.unlock()
    }
    func wait(seconds: TimeInterval) -> String {
        let deadline = Date().addingTimeInterval(seconds)
        condition.lock(); defer { condition.unlock() }
        while result == nil {
            if !condition.wait(until: deadline), result == nil { return "timedOut" }
        }
        return result!
    }
}

func requestScreenCapturePermission() -> String {
    if CGPreflightScreenCaptureAccess() { return "available" }
    // The production IPC runs on spawn_blocking; never block the AppKit thread
    // that must service the actual system permission confirmation.
    guard !Thread.isMainThread else { return "failed" }
    guard let request = ScreenCapturePermissionRequest.begin() else { return "busy" }
    #if canImport(ScreenCaptureKit)
    if #available(macOS 12.3, *) {
        // SCShareableContent can itself show a consent prompt. This function
        // belongs ONLY to an explicit Settings request, never status/hotkeys.
        DispatchQueue.main.async {
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
                if let error = error as NSError? {
                    request.finish(error.domain == SCStreamErrorDomain && error.code == -3801 ? "denied" : "failed")
                } else {
                    request.finish(content?.displays.isEmpty == false ? "available" : "failed")
                }
                // Deliberately discard all returned window/app/display metadata.
            }
        }
        // If the owner leaves a prompt pending, keep the gate until the callback
        // arrives. Another click must not create another concurrent prompt.
        return request.wait(seconds: 120)
    }
    #endif
    let granted = onMainThread { CGRequestScreenCaptureAccess() }
    request.finish(granted ? "available" : "denied")
    return request.wait(seconds: 0)
}

func screenCapturePermissionPolicySelfTest() throws {
    let cases: [(Bool, String?, String, Bool?)] = [
        (false, nil, "unconfirmed", nil), (true, nil, "granted", nil),
        (false, "available", "inconsistent", false), (true, "available", "granted", true),
        (false, "denied", "unconfirmed", true), (true, "denied", "inconsistent", false),
        (false, "failed", "unconfirmed", true), (false, "timedOut", "unconfirmed", true),
        (false, "busy", "unconfirmed", true)
    ]
    for (preflight, request, state, consistent) in cases {
        let fields = screenCapturePermissionFields(preflight: preflight, requestState: request)
        guard fields["screenCaptureGranted"] as? Bool == preflight,
              fields["screenCapturePreflightGranted"] as? Bool == preflight,
              fields["screenCaptureState"] as? String == state,
              fields["screenCaptureAuthorizationConsistent"] as? Bool == consistent,
              fields["screenCaptureRequestState"] as? String == request else {
            throw NativeError("SELF_TEST: Screen capture permission-state policy failed.")
        }
    }
    guard let first = ScreenCapturePermissionRequest.begin(),
          ScreenCapturePermissionRequest.begin() == nil,
          first.wait(seconds: 0) == "timedOut",
          ScreenCapturePermissionRequest.begin() == nil else {
        throw NativeError("SELF_TEST: Concurrent or timed-out screen permission request reopened the gate.")
    }
    first.finish("denied")
    guard first.wait(seconds: 0) == "denied", let next = ScreenCapturePermissionRequest.begin() else {
        throw NativeError("SELF_TEST: Completed screen permission request did not release the gate.")
    }
    // A duplicate old callback must not clear the new request's in-flight gate.
    first.finish("available")
    guard ScreenCapturePermissionRequest.begin() == nil else {
        throw NativeError("SELF_TEST: An old permission callback released a newer request.")
    }
    next.finish("available")
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
        return permissionStatus(screenCaptureRequestState: requestScreenCapturePermission())
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

// Apple supports direct, UI-free sessions only on macOS 26+. Their public
// installedSource initializer cannot request downloads. Preparation is a separate
// explicit Settings action using Apple's SwiftUI download confirmation flow.
struct SystemTranslationInput: Decodable {
    var text: String?
    var source: String
    var target: String
    var operationId: String? = nil
}

struct SystemTranslationCancellationInput: Decodable { let operationId: String }

func validSystemTranslationOperationId(_ value: String) -> Bool {
    value.range(of: #"\A[A-Za-z0-9_-]{1,40}\z"#, options: .regularExpression) != nil
}

func cancelSystemTranslationInput(_ input: Data) throws -> String {
    guard input.count <= 256,
          let request = try? JSONDecoder().decode(SystemTranslationCancellationInput.self, from: input),
          validSystemTranslationOperationId(request.operationId) else {
        throw NativeError("SYSTEM_TRANSLATION_INPUT: 无效的系统翻译操作编号。")
    }
    return request.operationId
}

func decodeSystemTranslationInput(_ input: Data, requiresText: Bool) throws -> SystemTranslationInput {
    guard input.count <= 2 * 1024 * 1024,
          let request = try? JSONDecoder().decode(SystemTranslationInput.self, from: input),
          request.source == "auto" || validSystemLanguage(request.source),
          validSystemLanguage(request.target),
          request.operationId.map(validSystemTranslationOperationId) ?? true,
          request.text?.unicodeScalars.count ?? 0 <= 20_000 else {
        throw NativeError("SYSTEM_TRANSLATION_INPUT: 系统翻译的文字或语言设置无效。")
    }
    if requiresText && request.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
        throw NativeError("SYSTEM_TRANSLATION_INPUT: 请输入需要翻译的文字。")
    }
    return request
}

func validSystemLanguage(_ value: String) -> Bool {
    value != "auto" && value.range(of: #"\A[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8}){0,3}\z"#, options: .regularExpression) != nil
}

func detectedTextLanguage(_ text: String) throws -> String {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          text.unicodeScalars.count <= 20_000 else {
        throw NativeError("SYSTEM_TRANSLATION_LANGUAGE: 无法检测原文语言，请手动选择源语言。")
    }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage,
          validSystemLanguage(language.rawValue) else {
        throw NativeError("SYSTEM_TRANSLATION_LANGUAGE: 无法检测原文语言，请手动选择源语言。")
    }
    // NaturalLanguage can identify very short shared Han phrases such as 你好
    // as zh-Hant. Use actual distinguishing characters for these short inputs;
    // shared characters use the Simplified Chinese starter model. Explicit
    // source-language selections never pass through this heuristic.
    let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
    if language.rawValue.lowercased().hasPrefix("zh"), letters.count <= 8 {
        let traditional = Set("體國學術語譯軟電腦網頁開關設置權錄螢幕選擇輸歡應簡實現測試錯誤請這個為與來說對會時後過還讓無發現經驗點擊備註書寫讀畫圖區裡處動視務預設總廣東臺灣樂萬億專業聲".unicodeScalars)
        let simplified = Set("体国学术语译软电脑网页开关设置权录荧选择输欢应简实现测试错误请这个为与来说对会时后过还让无发现经验点击备书写读画图区里处动视务预总广东台万亿专业声".unicodeScalars)
        let traditionalCount = letters.filter { traditional.contains($0) }.count
        let simplifiedCount = letters.filter { simplified.contains($0) }.count
        return traditionalCount > simplifiedCount ? "zh-Hant" : "zh-Hans"
    }
    return language.rawValue
}

func systemSourceLanguage(_ request: SystemTranslationInput, forTranslation: Bool) throws -> (String, Bool) {
    if request.source != "auto" { return (request.source, false) }
    guard let text = request.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        if forTranslation {
            throw NativeError("SYSTEM_TRANSLATION_LANGUAGE: 无法检测原文语言，请手动选择源语言。")
        }
        // Status/preparation without source text is scoped to this starter pair;
        // it never asserts that every automatically detected pair is installed.
        return (request.target.lowercased().hasPrefix("en") ? "zh-Hans" : "en", true)
    }
    return (try detectedTextLanguage(text), false)
}

func systemTranslationUnavailable() -> [String: Any] {
    return ["supported": false, "available": false, "requiresSetup": false,
            "status": "unavailable", "platform": "macos", "providerName": "Apple 系统翻译",
            "minimumVersion": "26.0", "onDevice": true,
            "message": "当前版本的免 API 系统翻译需要 macOS 26 或更新版本；也可以配置自己的翻译服务。"]
}

func systemTranslationPolicySelfTest() throws {
    let good = Data(#"{"text":"Hello 🪞\u0000world","source":"auto","target":"zh-Hant"}"#.utf8)
    let request = try decodeSystemTranslationInput(good, requiresText: true)
    guard request.text == "Hello 🪞\0world", request.target == "zh-Hant",
          !validSystemLanguage("auto"), !validSystemLanguage("zh-Hant\n"),
          !validSystemLanguage("en;open"), validSystemLanguage("zh-Hans"),
          validSystemLanguage("pt-BR"),
          try systemSourceLanguage(SystemTranslationInput(text: nil, source: "auto", target: "en"), forTranslation: false).0 == "zh-Hans",
          try systemSourceLanguage(SystemTranslationInput(text: nil, source: "auto", target: "zh-Hant"), forTranslation: false).0 == "en",
          try systemSourceLanguage(SystemTranslationInput(text: nil, source: "zh-Hant", target: "en"), forTranslation: false).0 == "zh-Hant",
          try detectedTextLanguage("你好") == "zh-Hans",
          try detectedTextLanguage("歡迎使用翻譯") == "zh-Hant",
          try detectedTextLanguage("Hello world") == "en" else {
        throw NativeError("SELF_TEST: System translation input policy failed.")
    }
    for invalid in [#"{"text":" ","source":"en","target":"zh-Hans"}"#,
                    #"{"text":"Hello","source":"auto","target":"auto"}"#,
                    #"{"text":"Hello","source":"en","target":"en\n"}"#] {
        do {
            _ = try decodeSystemTranslationInput(Data(invalid.utf8), requiresText: true)
            throw NativeError("SELF_TEST: Invalid system translation input was accepted.")
        } catch let error as NativeError {
            guard error.message.hasPrefix("SYSTEM_TRANSLATION_INPUT:") else { throw error }
        }
    }
    try systemTranslationOutputSelfTest()
}

private func translationLines(_ text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")
}

private func blankTranslationLine(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces).isEmpty
}

private func protectedTranslationCode(_ lines: [String]) -> Bool {
    let patterns = [
        #"^ {0,3}(`{3,}|~{3,})"#,
        #"^(\t| {4})"#,
        #"^\s*[{}\[\]]\s*[,;]?$"#,
        #"^\s*(?:["'][^"']+["']|[\p{L}_][\p{L}\p{N}_.-]*)\s*:\s*\S+"#,
        #"^\s*(?:const|let|var|fn|def|class|struct|enum|impl|pub|use|import|package|function|export)\b"#,
        #"^\s*[\p{L}_$][\p{L}\p{N}_$]*(?:\.[\p{L}_$][\p{L}\p{N}_$]*)*\("#,
        #"^\s*(?:\$\s+\S|</?[A-Za-z][^>]*>)"#,
    ]
    return lines.contains { line in
        if blankTranslationLine(line) { return false }
        return line.contains("\t") || patterns.contains {
            line.range(of: $0, options: .regularExpression) != nil
        }
    }
}

/// Apple can insert empty paragraphs between the lines of a tight list or a
/// single source paragraph. Remove only those added blank rows, and only when
/// the source has no explicit empty paragraph. Never join nonempty lines or
/// rewrite markers, spaces, typed source, code, or any other provider's result.
func normalizeSystemTranslationOutput(source: String, translated: String) -> String {
    let outputLines = translationLines(translated)
    let nonempty = outputLines.filter { !blankTranslationLine($0) }
    guard !nonempty.isEmpty, nonempty.count != outputLines.count else { return translated }
    let sourceLines = translationLines(source)
    guard let first = sourceLines.firstIndex(where: { !blankTranslationLine($0) }),
          let last = sourceLines.lastIndex(where: { !blankTranslationLine($0) }),
          !sourceLines[first...last].contains(where: blankTranslationLine),
          !source.contains("\u{2028}"), !source.contains("\u{2029}"),
          !protectedTranslationCode(sourceLines) else { return translated }
    guard !protectedTranslationCode(outputLines) else { return translated }
    return nonempty.joined(separator: "\n")
}

func systemTranslationOutputSelfTest() throws {
    let bulletSource = "• 支持 quiet_pin、路径、冒号及符号包装等文本。\n• 取词/OCR 后原文可以手动编辑。\n• 保留明确段落和代码结构。\n• 放大固定按钮。"
    let bulletOutput = "• Supports quiet_pin, paths, colons, etc.\n\nKeep the original text.\n\n• Edit the selected/OCR text.\n\n• Keep paragraph and code structure.\n\n• Enlarge the pin button."
    let bulletExpected = "• Supports quiet_pin, paths, colons, etc.\nKeep the original text.\n• Edit the selected/OCR text.\n• Keep paragraph and code structure.\n• Enlarge the pin button."
    let fixtures: [(String, String, String)] = [
        (bulletSource, bulletOutput, bulletExpected),
        ("First source line\nsecond source line", "第一行\n\n第二行", "第一行\n第二行"),
        ("One paragraph.", "一段。\n \t\n继续。", "一段。\n继续。"),
        ("- First item\n- Second item", "- 第一项\n\n\n- 第二项", "- 第一项\n- 第二项"),
        ("1. First item\n2. Second item", "1. 第一项\n\n2. 第二项", "1. 第一项\n2. 第二项"),
        ("First line  \nSecond line", "第一行  \n\n第二行", "第一行  \n第二行"),
        ("第一行\r\n第二行", "First line\r\n\r\nSecond line", "First line\nSecond line"),
        ("Source", "\n译文\n\n", "译文"),
        ("First paragraph.\n\nSecond paragraph.", "第一段。\n\n\n第二段。", "第一段。\n\n\n第二段。"),
        ("- First item\n \n- Second item", "- 第一项\n\n- 第二项", "- 第一项\n\n- 第二项"),
        ("```python\nprint('hello')\n```", "```python\n\nprint('你好')\n```", "```python\n\nprint('你好')\n```"),
        ("    print('hello')\n    return 1", "    print('你好')\n\n    return 1", "    print('你好')\n\n    return 1"),
        ("{\n\"key\": \"value\"\n}", "{\n\n\"键\": \"值\"\n}", "{\n\n\"键\": \"值\"\n}"),
        ("key: value\nother: value", "键: 值\n\n其他: 值", "键: 值\n\n其他: 值"),
        ("First\tcolumn\nsecond\tcolumn", "第一\t列\n\n第二\t列", "第一\t列\n\n第二\t列"),
        ("Source", "```\n\ncode\n```", "```\n\ncode\n```"),
        ("First\u{2029}Second", "第一\n\n第二", "第一\n\n第二"),
        ("Source", "译文\r\n第二行", "译文\r\n第二行"),
        ("", "译文\n\n第二行", "译文\n\n第二行"),
    ]
    for (source, translated, expected) in fixtures {
        guard normalizeSystemTranslationOutput(source: source, translated: translated) == expected else {
            throw NativeError("SELF_TEST: Source-aware system translation output policy failed.")
        }
    }
}

#if canImport(Translation) && compiler(>=6.2)
// The synchronous C ABI is called on a Rust blocking worker while AppKit's main
// loop remains alive. A standalone CLI services its run loop while waiting.
// The locked result owns no source text after completion and is never persisted.
final class SystemTranslationWaiter: @unchecked Sendable {
    private let condition = NSCondition()
    private var result: Result<[String: Any], Error>?
    func finish(_ value: Result<[String: Any], Error>) {
        condition.lock()
        if result == nil { result = value; condition.broadcast() }
        condition.unlock()
    }
    func wait(seconds: TimeInterval) throws -> [String: Any] {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while true {
            condition.lock()
            if let result = result { condition.unlock(); return try result.get() }
            if Date() >= deadline {
                condition.unlock()
                throw NativeError("SYSTEM_TRANSLATION_TIMEOUT: 系统翻译等待超时，请重试。")
            }
            if Thread.isMainThread {
                condition.unlock()
                _ = RunLoop.current.run(mode: .default, before: min(deadline, Date(timeIntervalSinceNow: 0.02)))
            } else {
                _ = condition.wait(until: deadline)
                condition.unlock()
            }
        }
    }
}

// A cancellation can arrive before the Rust blocking worker registers its
// Task. Bounded tombstones plus an attach gate make that cancellation durable.
// None of these entries contains source text, language data or UI objects.
final class SystemTranslationJob: @unchecked Sendable {
    private let condition = NSCondition()
    private var attached = false
    private var cancelled = false
    private var task: Task<Void, Never>?
    func attach(_ task: Task<Void, Never>) {
        condition.lock()
        self.task = task
        attached = true
        let shouldCancel = cancelled
        condition.broadcast()
        condition.unlock()
        if shouldCancel { task.cancel() }
    }
    func begin() throws {
        condition.lock()
        while !attached { condition.wait() }
        let shouldCancel = cancelled
        condition.unlock()
        if shouldCancel { throw CancellationError() }
    }
    func cancel() {
        condition.lock()
        cancelled = true
        let task = task
        condition.unlock()
        task?.cancel()
    }
}

final class SystemTranslationJobs: @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [String: SystemTranslationJob] = [:]
    private var cancelledBeforeStart: [String] = []
    func register(_ operationId: String) throws -> SystemTranslationJob {
        lock.lock()
        defer { lock.unlock() }
        if let index = cancelledBeforeStart.firstIndex(of: operationId) {
            cancelledBeforeStart.remove(at: index)
            throw NativeError("SYSTEM_TRANSLATION_CANCELLED: 已取消系统翻译。")
        }
        guard jobs.isEmpty else {
            throw NativeError("SYSTEM_TRANSLATION_BUSY: 之前的系统翻译正在结束，请稍后重试。")
        }
        let job = SystemTranslationJob()
        jobs[operationId] = job
        return job
    }
    func remove(_ operationId: String, job: SystemTranslationJob) {
        lock.lock()
        if jobs[operationId] === job { jobs.removeValue(forKey: operationId) }
        lock.unlock()
    }
    func cancel(_ operationId: String) {
        lock.lock()
        let job = jobs[operationId]
        if job == nil && !cancelledBeforeStart.contains(operationId) {
            cancelledBeforeStart.append(operationId)
            if cancelledBeforeStart.count > 128 { cancelledBeforeStart.removeFirst() }
        }
        lock.unlock()
        job?.cancel()
    }
}

let systemTranslationJobs = SystemTranslationJobs()

func awaitSystemTranslation(seconds: TimeInterval, operationId: String? = nil,
                            _ operation: @escaping () async throws -> [String: Any]) throws -> [String: Any] {
    let waiter = SystemTranslationWaiter()
    let job = try operationId.map { try systemTranslationJobs.register($0) }
    let task = Task.detached {
        let result: Result<[String: Any], Error>
        do {
            try job?.begin()
            try Task.checkCancellation()
            result = .success(try await operation())
        } catch is CancellationError {
            result = .failure(NativeError("SYSTEM_TRANSLATION_CANCELLED: 已取消系统翻译。"))
        } catch { result = .failure(error) }
        // Remove before waking the C caller, so the next user action observes
        // completed cleanup instead of a transient false busy result.
        if let operationId = operationId, let job = job {
            systemTranslationJobs.remove(operationId, job: job)
        }
        waiter.finish(result)
    }
    job?.attach(task)
    do { return try waiter.wait(seconds: seconds) }
    catch { job?.cancel(); task.cancel(); throw error }
}

func systemTranslationCancellationSelfTest() throws {
    systemTranslationJobs.cancel("selftest-before")
    do {
        _ = try awaitSystemTranslation(seconds: 2, operationId: "selftest-before") {
            throw NativeError("SELF_TEST: A pre-cancelled operation started.")
        }
        throw NativeError("SELF_TEST: Pre-registration cancellation was ignored.")
    } catch let error as NativeError {
        guard error.message.hasPrefix("SYSTEM_TRANSLATION_CANCELLED:") else { throw error }
    }
    // Exercise actual cooperative Task.sleep cancellation, not a translation
    // mock or a second copy of registry logic. No Translation API runs here.
    let entered = SystemTranslationWaiter()
    let ended = SystemTranslationWaiter()
    DispatchQueue.global().async {
        do {
            _ = try awaitSystemTranslation(seconds: 3, operationId: "selftest-active") {
                entered.finish(.success(["entered": true]))
                try await Task.sleep(nanoseconds: 10_000_000_000)
                return ["slept": true]
            }
            ended.finish(.failure(NativeError("SELF_TEST: Active cancellation was ignored.")))
        } catch let error as NativeError {
            if error.message.hasPrefix("SYSTEM_TRANSLATION_CANCELLED:") {
                ended.finish(.success(["cancelled": true]))
            } else { ended.finish(.failure(error)) }
        } catch { ended.finish(.failure(error)) }
    }
    _ = try entered.wait(seconds: 2)
    systemTranslationJobs.cancel("selftest-active")
    guard try ended.wait(seconds: 2)["cancelled"] as? Bool == true else {
        throw NativeError("SELF_TEST: Active cancellation did not reach the Swift Task.")
    }
    let liveEntered = SystemTranslationWaiter()
    let liveEnded = SystemTranslationWaiter()
    DispatchQueue.global().async {
        do {
            let value = try awaitSystemTranslation(seconds: 2, operationId: "selftest-live") {
                liveEntered.finish(.success(["entered": true]))
                try await Task.sleep(nanoseconds: 50_000_000)
                return ["completed": true]
            }
            liveEnded.finish(.success(value))
        } catch { liveEnded.finish(.failure(error)) }
    }
    _ = try liveEntered.wait(seconds: 2)
    // Cancelling another identifier must leave the running operation alone.
    systemTranslationJobs.cancel("selftest-other")
    guard try liveEnded.wait(seconds: 2)["completed"] as? Bool == true else {
        throw NativeError("SELF_TEST: Unrelated cancellation affected a live operation.")
    }
    let repeated = try awaitSystemTranslation(seconds: 2, operationId: "selftest-live") { ["completed": true] }
    guard repeated["completed"] as? Bool == true else {
        throw NativeError("SELF_TEST: Completed system translation was not removed.")
    }
}

@available(macOS 26.0, *)
func systemTranslationFailure(_ error: Error) -> NativeError {
    if let native = error as? NativeError { return native }
    switch error {
    case TranslationError.notInstalled:
        return NativeError("SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: 请在设置中点击「准备系统翻译」，确认下载所需语言后重试。")
    case TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage,
         TranslationError.unsupportedLanguagePairing:
        return NativeError("SYSTEM_TRANSLATION_UNSUPPORTED: Apple 系统翻译不支持当前语言组合，请选择其他语言或翻译服务。")
    case TranslationError.unableToIdentifyLanguage:
        return NativeError("SYSTEM_TRANSLATION_LANGUAGE: 无法检测原文语言，请手动选择源语言。")
    case TranslationError.alreadyCancelled, is CancellationError:
        return NativeError("SYSTEM_TRANSLATION_CANCELLED: 已取消系统翻译。")
    default:
        return NativeError("SYSTEM_TRANSLATION_FAILED: Apple 系统翻译暂时不可用，请重试或选择其他翻译服务。")
    }
}

@available(macOS 26.0, *)
func availableSystemTranslation(_ request: SystemTranslationInput) async throws -> [String: Any] {
    let (source, starterPair) = try systemSourceLanguage(request, forTranslation: false)
    let state: LanguageAvailability.Status
    if systemLanguagesEquivalent(source, request.target) { state = .installed }
    else { state = await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: request.target)) }
    let status: String
    let available: Bool
    let requiresSetup: Bool
    var message: String
    switch state {
    case .installed:
        status = "installed"; available = true; requiresSetup = false
        message = "此语言组合已可使用 Apple 系统翻译，无需 API 密钥。"
    case .supported:
        status = "downloadRequired"; available = false; requiresSetup = true
        message = "请点击「准备系统翻译」，在系统确认后下载所需语言。"
    case .unsupported:
        status = "unsupported"; available = false; requiresSetup = false
        message = "Apple 系统翻译不支持此语言组合，请选择其他语言或翻译服务。"
    @unknown default:
        status = "unavailable"; available = false; requiresSetup = false
        message = "无法确认系统翻译状态，请重试。"
    }
    if starterPair { message += " 当前检查的是 \(source) → \(request.target)，其他源语言将分别检查。" }
    return ["supported": true, "available": available, "requiresSetup": requiresSetup,
            "status": status, "platform": "macos", "providerName": "Apple 系统翻译",
            "minimumVersion": "26.0", "onDevice": true, "source": source,
            "target": request.target, "starterPair": starterPair, "message": message]
}

@available(macOS 13.0, *)
func systemTargetLanguageMatches(_ requested: String, _ returned: Locale.Language) -> Bool {
    let expected = Locale.Language(identifier: requested)
    guard expected.languageCode == returned.languageCode else { return false }
    // Chinese targets have an explicit product distinction. Apple's returned
    // language metadata must preserve that script rather than accepting zh.
    if expected.languageCode?.identifier == "zh" {
        return expected.script == returned.script
    }
    return true
}

@available(macOS 13.0, *)
func systemLanguagesEquivalent(_ source: String, _ target: String) -> Bool {
    // en-US and en are the same language for a no-op translation. Chinese
    // variants remain distinct; a Traditional target is never replaced by Hans.
    return systemTargetLanguageMatches(target, Locale.Language(identifier: source))
}

@available(macOS 26.0, *)
func translateWithSystem(_ request: SystemTranslationInput) async throws -> [String: Any] {
    let (source, _) = try systemSourceLanguage(request, forTranslation: true)
    let text = request.text ?? ""
    // Preserve the requested Chinese script. Do not substitute generic zh or
    // another target if Apple's availability/session rejects the exact pair.
    if systemLanguagesEquivalent(source, request.target) {
        return ["text": text, "sourceLanguage": source, "targetLanguage": request.target]
    }
    let status = await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: request.target))
    guard status == .installed else {
        throw NativeError(status == .supported
            ? "SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED: 请在设置中点击「准备系统翻译」，确认下载所需语言后重试。"
            : "SYSTEM_TRANSLATION_UNSUPPORTED: Apple 系统翻译不支持当前语言组合，请选择其他语言或翻译服务。")
    }
    let session = TranslationSession(installedSource: Locale.Language(identifier: source), target: Locale.Language(identifier: request.target))
    guard !session.canRequestDownloads else {
        throw NativeError("SYSTEM_TRANSLATION_FAILED: 系统翻译未能进入本机语言模式。")
    }
    do {
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            let response = try await session.translate(text)
            try Task.checkCancellation()
            guard !response.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NativeError("SYSTEM_TRANSLATION_FAILED: 系统翻译返回了空结果，请重试。")
            }
            guard systemTargetLanguageMatches(request.target, response.targetLanguage) else {
                throw NativeError("SYSTEM_TRANSLATION_UNSUPPORTED: Apple 系统翻译未保留所选目标语言，请选择其他翻译服务。")
            }
            return ["text": normalizeSystemTranslationOutput(source: text, translated: response.targetText),
                    "sourceLanguage": source, "targetLanguage": request.target]
        }, onCancel: { session.cancel() })
    } catch { throw systemTranslationFailure(error) }
}

@available(macOS 26.0, *)
struct SystemTranslationPreparationView: View {
    let configuration: TranslationSession.Configuration
    let languagePair: String
    let started: (TranslationSession) -> Void
    let installed: () -> Void
    let failed: (Error) -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("准备 Apple 系统翻译").font(.headline)
            Text(languagePair).font(.subheadline)
            Text("macOS 将请求确认并下载所需语言。下载后可直接使用本机翻译，无需 API 密钥。")
                .fixedSize(horizontal: false, vertical: true)
            HStack { ProgressView().controlSize(.small); Text("等待系统完成准备…"); Spacer(); Button("取消", action: cancel) }
        }
        .padding(24).frame(width: 420)
        .translationTask(configuration) { session in
            started(session)
            do {
                try await session.prepareTranslation()
                guard let source = configuration.source else {
                    throw NativeError("SYSTEM_TRANSLATION_LANGUAGE: 请先选择源语言。")
                }
                // Apple can return while assets are still downloading. Keep
                // this explicit window cancellable until the exact pair is
                // installed; the outer operation imposes a 180-second limit.
                while true {
                    try Task.checkCancellation()
                    let state = await LanguageAvailability().status(from: source, to: configuration.target)
                    if state == .installed { installed(); return }
                    if state == .unsupported {
                        throw NativeError("SYSTEM_TRANSLATION_UNSUPPORTED: Apple 系统翻译不支持当前语言组合。")
                    }
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            } catch { failed(error) }
        }
    }
}

@available(macOS 26.0, *)
final class SystemTranslationPreparation: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var completed = false
    private var cancelSession: (() -> Void)?
    private let waiter: SystemTranslationWaiter
    init(waiter: SystemTranslationWaiter) { self.waiter = waiter }
    func show(source: String, target: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 468, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "准备系统翻译"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SystemTranslationPreparationView(
            configuration: TranslationSession.Configuration(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target)),
            languagePair: "\(source) → \(target)",
            started: { [weak self] session in self?.installSession(session) },
            installed: { [weak self] in self?.finish(.success(["prepared": true])) },
            failed: { [weak self] error in self?.finish(.failure(systemTranslationFailure(error))) },
            cancel: { [weak self] in self?.cancel() }))
        self.window = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func installSession(_ session: TranslationSession) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.installSession(session) }; return }
        if completed { session.cancel() }
        else { cancelSession = { session.cancel() } }
    }
    func cancel() {
        finish(.failure(NativeError("SYSTEM_TRANSLATION_CANCELLED: 已取消系统翻译准备。")))
    }
    func finish(_ result: Result<[String: Any], Error>) {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.finish(result) }; return }
        guard !completed else { return }
        completed = true
        // Cancel this session and remove its SwiftUI task when closing.
        // System language assets already downloaded remain managed by macOS.
        cancelSession?()
        cancelSession = nil
        window?.contentView = nil
        window?.close()
        window = nil
        waiter.finish(result)
        activeSystemTranslationPreparation = nil
    }
    func windowWillClose(_ notification: Notification) { cancel() }
}

// Access only on the AppKit main thread; one explicit preparation at a time.
@available(macOS 26.0, *)
var activeSystemTranslationPreparation: SystemTranslationPreparation?

@available(macOS 26.0, *)
func prepareSystemTranslation(_ request: SystemTranslationInput) throws -> [String: Any] {
    let state = try awaitSystemTranslation(seconds: 15) { try await availableSystemTranslation(request) }
    if state["available"] as? Bool == true { return state }
    guard state["requiresSetup"] as? Bool == true else {
        throw NativeError("SYSTEM_TRANSLATION_UNSUPPORTED: Apple 系统翻译不支持当前语言组合，请选择其他语言或翻译服务。")
    }
    let (source, _) = try systemSourceLanguage(request, forTranslation: false)
    let waiter = SystemTranslationWaiter()
    let preparation = SystemTranslationPreparation(waiter: waiter)
    try onMainThread {
        guard activeSystemTranslationPreparation == nil else {
            throw NativeError("SYSTEM_TRANSLATION_BUSY: 系统翻译正在准备，请先完成或取消当前操作。")
        }
        activeSystemTranslationPreparation = preparation
        preparation.show(source: source, target: request.target)
    }
    do {
        _ = try waiter.wait(seconds: 180)
        return try awaitSystemTranslation(seconds: 15) { try await availableSystemTranslation(request) }
    } catch {
        // Timeout cancellation belongs to this operation only.
        DispatchQueue.main.async { preparation.cancel() }
        throw error
    }
}
#endif

func systemTranslationResponse(mode: String, input: Data) throws -> [String: Any] {
    let request = try decodeSystemTranslationInput(input, requiresText: mode == "--system-translate")
    #if canImport(Translation) && compiler(>=6.2)
    if #available(macOS 26.0, *) {
        switch mode {
        case "--system-translation-status":
            return ["ok": true, "systemTranslation": try awaitSystemTranslation(seconds: 15) { try await availableSystemTranslation(request) }]
        case "--system-translate":
            var response = try awaitSystemTranslation(seconds: 45, operationId: request.operationId) { try await translateWithSystem(request) }
            response["ok"] = true
            return response
        case "--prepare-system-translation":
            return ["ok": true, "systemTranslation": try prepareSystemTranslation(request)]
        default: break
        }
    }
    #endif
    if mode == "--system-translation-status" { return ["ok": true, "systemTranslation": systemTranslationUnavailable()] }
    throw NativeError("SYSTEM_TRANSLATION_UNAVAILABLE: 当前免 API 系统翻译需要 macOS 26 或更新版本；也可以配置自己的翻译服务。")
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
    try selectionPolicySelfTest()
    try captureSelectionSelfTest()
    try systemTranslationPolicySelfTest()
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
            "selectionPolicyFixturePassed": true, "captureSelectionFixturePassed": true, "captureSelectionDeadlineFixturePassed": true, "systemTranslationPolicyFixturePassed": true, "selectionForegroundFixturePassed": true,
            "opaqueOfficeSelectionPolicyFixturePassed": true, "pluralSelectionRangesFixturePassed": true,
            "selectionCopyCompletionFixturePassed": true,
            "wpsInteractiveSelectionTested": false,
            "protectedSelectionFixturePassed": true,
            "privatePasteboardFixturePassed": privatePasteboardTested,
            "privatePasteboardFixtureSkipped": !privatePasteboardTested, "pngSizeGuardsPassed": true,
            "interactiveCaptureTested": false, "generalClipboardTouched": false,
            "clipboardChanged": false, "bridgeInputPassed": !input.isEmpty]
}

func nativeResponse(mode: String, input: Data = Data()) -> [String: Any] {
    do {
        switch mode {
        case "--selected-text": return ["ok": true, "text": try selection()]
        case "--selection-policy-self-test":
            try selectionPolicySelfTest()
            let privatePasteboardTested = Thread.isMainThread
            if privatePasteboardTested { try privatePasteboardSelfTest() }
            return ["ok": true, "diagnostics": ["selectionPolicyFixturePassed": true,
                    "selectionCopyCompletionFixturePassed": true,
                    "privatePasteboardFixturePassed": privatePasteboardTested,
                    "generalClipboardTouched": false, "permissionRequested": false,
                    "wpsInteractiveSelectionTested": false]]
        case "--capture-selection-self-test":
            try captureSelectionSelfTest()
            return ["ok": true, "diagnostics": ["captureSelectionFixturePassed": true, "captureSelectionDeadlineFixturePassed": true, "screenCaptured": false, "permissionRequested": false]]
        case "--capture-selector-preview":
            // Explicit development-only UI preview. It never checks/requests
            // TCC, enumerates shareable content, captures pixels or invokes OCR.
            let plan = try selectNativeCaptureRegion()
            return ["ok": true, "selectedRect": ["x": plan.region.minX, "y": plan.region.minY,
                     "width": plan.region.width, "height": plan.region.height],
                    "diagnostics": ["screenCaptured": false, "permissionRequested": false,
                     "ocrInvoked": false, "translationInvoked": false,
                     "displayCount": plan.displays.count, "scale": plan.scale]]
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
        case "--permission-policy-self-test":
            try screenCapturePermissionPolicySelfTest()
            return ["ok": true, "diagnostics": ["permissionPolicyFixturePassed": true,
                    "permissionRequested": false, "screenCaptured": false, "passiveStatusUsesPreflightOnly": true]]
        case "--request-accessibility", "--request-screenCapture":
            let kind = String(mode.dropFirst("--request-".count))
            return ["ok": true, "permissions": try requestPermission(kind)]
        case "--open-settings-accessibility", "--open-settings-screenCapture":
            try openPermissionSettings(String(mode.dropFirst("--open-settings-".count)))
            return ["ok": true, "text": ""]
        case "--cancel-system-translation":
            let operationId = try cancelSystemTranslationInput(input)
            #if canImport(Translation) && compiler(>=6.2)
            systemTranslationJobs.cancel(operationId)
            #endif
            return ["ok": true, "text": ""]
        case "--system-translation-self-test":
            try systemTranslationPolicySelfTest()
            var cancellationTested = false
            #if canImport(Translation) && compiler(>=6.2)
            try systemTranslationCancellationSelfTest()
            cancellationTested = true
            #endif
            if #available(macOS 13.0, *) {
                #if canImport(Translation) && compiler(>=6.2)
                guard systemTargetLanguageMatches("zh-Hans", Locale.Language(identifier: "zh")),
                      systemTargetLanguageMatches("zh-Hant", Locale.Language(identifier: "zh-TW")),
                      !systemTargetLanguageMatches("zh-Hant", Locale.Language(identifier: "zh-Hans")),
                      !systemTargetLanguageMatches("en", Locale.Language(identifier: "fr")),
                      systemLanguagesEquivalent("zh", "zh-Hans"),
                      systemLanguagesEquivalent("en-US", "en"),
                      !systemLanguagesEquivalent("zh-Hant", "zh-Hans") else {
                    throw NativeError("SELF_TEST: System translation target script policy failed.")
                }
                #endif
            }
            return ["ok": true, "diagnostics": ["systemTranslationPolicyFixturePassed": true, "systemTranslationOutputFixturePassed": true, "systemTranslationOutputFixtureCount": 19, "systemTranslationCancellationFixturePassed": cancellationTested, "systemTranslationCancellationFixtureSkipped": !cancellationTested, "translationEngineCalled": false, "languageDownloadRequested": false]]
        case "--detect-language":
            guard input.count <= 2 * 1024 * 1024, let text = String(data: input, encoding: .utf8) else {
                throw NativeError("SYSTEM_TRANSLATION_LANGUAGE: 无法检测原文语言，请手动选择源语言。")
            }
            return ["ok": true, "text": try detectedTextLanguage(text)]
        case "--system-translation-status", "--system-translate", "--prepare-system-translation":
            return try systemTranslationResponse(mode: mode, input: input)
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
        if mode == "--capture-selector-preview" {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            DispatchQueue.global(qos: .userInitiated).async {
                let response = nativeResponse(mode: mode, input: Data())
                DispatchQueue.main.async {
                    emit(response)
                    exit(response["ok"] as? Bool == true ? 0 : 1)
                }
            }
            application.run()
            return
        }
        let readsInput = ["--copy", "--detect-language", "--system-translation-status", "--system-translate", "--prepare-system-translation", "--cancel-system-translation"].contains(mode)
        let input = readsInput ? FileHandle.standardInput.readDataToEndOfFile() : Data()
        let response = nativeResponse(mode: mode, input: input)
        emit(response)
        if response["ok"] as? Bool != true { exit(1) }
    }
}
#endif
