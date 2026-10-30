import AppKit
import ApplicationServices
import Carbon
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

// Keep only the latest explicit selection attempt in memory. Diagnostics never
// query a selection, clipboard or window title and never write this trace out.
final class SelectionTrace {
    private static let lock = NSLock()
    private static var latest: [String: Any] = ["state": "unread", "schemaVersion": 1]
    static let maximumEvents = 32
    private static let allowedFields: Set<String> = [
        "axApplicationStatus", "axPIDStatus", "axPID", "workspacePID", "workspaceOnMainThread",
        "foregroundSource", "foregroundPID", "bundleIdentifier", "foregroundMismatch", "root",
        "focusStatus", "focusPIDStatus", "focusOwner", "expectedPID", "ownerMatches", "valueTypeValid",
        "role", "roleStatus", "subrole", "subroleStatus", "selectedTextStatus", "selectedTextEmpty",
        "rangeStatus", "rangeState", "rangeLength", "rangeTextStatus", "pluralStatus", "pluralState", "rangeCount", "positiveRangeCount",
        "decision", "documentContainer", "opaqueDocument", "copyIssued", "probeNodes", "probeRoot", "copyStrategy", "windowMatches"
    ]
    private let start = ProcessInfo.processInfo.systemUptime
    private let publish: Bool
    private var events = [[String: Any]]()
    private var phase = "started"
    private var truncated = false
    private var copyIssued = false
    init(publish: Bool = true) {
        self.publish = publish
        record("started")
    }
    func record(_ phase: String, _ fields: [String: Any] = [:]) {
        self.phase = String(phase.prefix(64))
        if fields["copyIssued"] as? Bool == true { copyIssued = true }
        var event: [String: Any] = ["phase": self.phase, "mainThread": Thread.isMainThread,
                                    "elapsedMs": elapsedMilliseconds()]
        for (key, value) in fields where Self.allowedFields.contains(key) {
            if let value = value as? String { event[key] = String(value.prefix(256)) }
            else if value is NSNumber || value is NSNull { event[key] = value }
        }
        if events.count < Self.maximumEvents { events.append(event) } else { truncated = true }
        store(state: "running", errorCategory: nil)
    }
    func finish(errorCategory: String? = nil) {
        store(state: errorCategory == nil ? "completed" : "failed", errorCategory: errorCategory)
    }
    private func elapsedMilliseconds() -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1000
    }
    func snapshot(state: String = "running", errorCategory: String? = nil) -> [String: Any] {
        let categories: Set<String> = ["PERMISSION", "SELECTION", "SELECTION_UNAVAILABLE", "NO_SELECTION", "CANCELLED", "CLIPBOARD",
            "CLIPBOARD_CHANGED", "CLIPBOARD_RESTORE_FAILED", "CLIPBOARD_RESTORE_SKIPPED"]
        let category = errorCategory.map { categories.contains($0) ? $0 : "NATIVE" }
        return ["schemaVersion": 1, "state": state, "phase": phase,
                "errorCategory": category as Any? ?? NSNull(), "copyIssued": copyIssued,
                "elapsedMs": elapsedMilliseconds(), "events": events, "eventsTruncated": truncated]
    }
    private func store(state: String, errorCategory: String?) {
        guard publish else { return }
        let value = snapshot(state: state, errorCategory: errorCategory)
        Self.lock.lock(); Self.latest = value; Self.lock.unlock()
    }
    static func lastSnapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
}

struct SelectionApplicationSnapshot {
    let pid: pid_t?
    let bundleIdentifier: String?
}

func selectionForegroundSource(axStatus: AXError, axPIDStatus: AXError?, axPID: pid_t?, workspacePID: pid_t?) -> (pid_t?, String) {
    if axStatus == .success, axPIDStatus == .success, let axPID, axPID > 0 {
        return (axPID, "axFocusedApplication")
    }
    // noValue means the requested AX value does not exist, not that access was
    // denied or the app timed out. Custom applications can omit the system
    // focused-app value while remaining the live Workspace key-event target.
    // Only the current main-thread Workspace read may supply this identity;
    // failures, invalid AX objects and invalid successful PID reads stay closed.
    if [.attributeUnsupported, .notImplemented, .noValue].contains(axStatus), let workspacePID, workspacePID > 0 {
        return (workspacePID, axStatus == .noValue ? "workspaceNoValueFallback" : "workspaceUnsupportedFallback")
    }
    return (nil, "unavailable")
}

func selectionApplicationSnapshot(trace: SelectionTrace? = nil, phase: String = "foreground") -> SelectionApplicationSnapshot {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &value)
    var axPID: pid_t?
    var pidStatus: AXError?
    if status == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
        var pid: pid_t = 0
        pidStatus = AXUIElementGetPid(value as! AXUIElement, &pid)
        if pidStatus == .success { axPID = pid }
    }
    // NSWorkspace is a main-thread comparison/fallback, not the authority when
    // AX has a current application. AX queries stay on the capture worker.
    let metadata = onMainThread { () -> (pid_t?, String, pid_t?, String?, Bool) in
        let workspacePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let (pid, source) = selectionForegroundSource(axStatus: status, axPIDStatus: pidStatus,
                                                    axPID: axPID, workspacePID: workspacePID)
        let bundle = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        return (pid, source, workspacePID, bundle, Thread.isMainThread)
    }
    trace?.record(phase, ["axApplicationStatus": status.rawValue, "axPIDStatus": pidStatus?.rawValue as Any? ?? NSNull(),
        "axPID": axPID as Any? ?? NSNull(), "workspacePID": metadata.2 as Any? ?? NSNull(),
        "workspaceOnMainThread": metadata.4, "foregroundSource": metadata.1,
        "foregroundPID": metadata.0 as Any? ?? NSNull(), "bundleIdentifier": metadata.3 as Any? ?? NSNull(),
        "foregroundMismatch": axPID != nil && metadata.2 != nil && axPID != metadata.2])
    return SelectionApplicationSnapshot(pid: metadata.0, bundleIdentifier: metadata.3)
}

func selectionFocusOwnerMatches(_ expectedPID: pid_t?, _ owner: pid_t, _ status: AXError) -> Bool {
    guard let expectedPID, expectedPID > 0 else { return false }
    return status == .success && owner == expectedPID
}

func selectionQueryBudgetAvailable(_ deadline: TimeInterval?) -> Bool {
    deadline.map { ProcessInfo.processInfo.systemUptime < $0 } ?? true
}

struct SelectionProbeBudgetExpired: Error {}

func requireSelectionQueryBudget(_ deadline: TimeInterval?) throws {
    guard selectionQueryBudgetAvailable(deadline) else { throw SelectionProbeBudgetExpired() }
}

func selectionFocusQueryState(status: AXError, valueTypeValid: Bool, ownerMatches: Bool) -> String {
    guard status == .success else { return unavailableSelectionRange(status) ? "unavailable" : "invalid" }
    return valueTypeValid && ownerMatches ? "valid" : "invalid"
}

// Keep unavailable metadata distinct from malformed, failed or foreign focus.
// Only the former can authorize the read-only focused-window recovery below.
func focusedElementQuery(applicationPID: pid_t? = nil, trace: SelectionTrace? = nil,
                         phase: String = "focus", deadline: TimeInterval? = nil) -> SelectionQuery<AXUIElement> {
    let pid = applicationPID ?? selectionApplicationSnapshot(trace: trace).pid
    guard let pid, pid > 0 else { return .invalid }
    let system = AXUIElementCreateSystemWide()
    var invalid = false
    var limited = false
    func query(_ root: AXUIElement, _ name: String) -> AXUIElement? {
        guard selectionQueryBudgetAvailable(deadline) else { limited = true; return nil }
        if deadline != nil && name != "systemWide" && AXUIElementSetMessagingTimeout(root, 0.03) != .success {
            invalid = true; return nil
        }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &value)
        let valid = value.map { CFGetTypeID($0) == AXUIElementGetTypeID() } ?? false
        guard status == .success, let value, valid else {
            if selectionFocusQueryState(status: status, valueTypeValid: valid, ownerMatches: false) == "invalid" { invalid = true }
            trace?.record(phase, ["root": name, "focusStatus": status.rawValue, "valueTypeValid": valid])
            return nil
        }
        let element = value as! AXUIElement
        guard selectionQueryBudgetAvailable(deadline) else { limited = true; return nil }
        if deadline != nil && AXUIElementSetMessagingTimeout(element, 0.03) != .success { invalid = true; return nil }
        var owner: pid_t = 0
        let ownerStatus = AXUIElementGetPid(element, &owner)
        let matches = selectionFocusOwnerMatches(pid, owner, ownerStatus)
        if !matches { invalid = true }
        trace?.record(phase, ["root": name, "focusStatus": status.rawValue, "focusPIDStatus": ownerStatus.rawValue,
            "focusOwner": owner, "expectedPID": pid, "ownerMatches": matches])
        return matches ? element : nil
    }
    if let element = query(AXUIElementCreateApplication(pid), "application") { return .value(element) }
    if let element = query(system, "systemWide") { return .value(element) }
    // Some applications expose focus only through the system's focused app.
    // Validate that application before querying it; never follow a new owner.
    guard selectionQueryBudgetAvailable(deadline) else { return invalid ? .invalid : .limited }
    var application: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &application)
    var owner: pid_t = 0
    if status == .success, let application, CFGetTypeID(application) == AXUIElementGetTypeID() {
        let root = application as! AXUIElement
        guard selectionQueryBudgetAvailable(deadline) else { return invalid ? .invalid : .limited }
        if deadline != nil && AXUIElementSetMessagingTimeout(root, 0.03) != .success { return .invalid }
        let ownerStatus = AXUIElementGetPid(root, &owner)
        let matches = selectionFocusOwnerMatches(pid, owner, ownerStatus)
        if !matches { invalid = true }
        trace?.record(phase, ["root": "systemFocusedApplication", "axApplicationStatus": status.rawValue,
            "focusPIDStatus": ownerStatus.rawValue, "focusOwner": owner, "expectedPID": pid, "ownerMatches": matches])
        if matches, let element = query(root, "systemFocusedApplication") { return .value(element) }
    } else {
        if !unavailableSelectionRange(status) { invalid = true }
        trace?.record(phase, ["root": "systemFocusedApplication", "axApplicationStatus": status.rawValue])
    }
    return invalid ? .invalid : (limited ? .limited : .unavailable)
}

func focusedElement(applicationPID: pid_t? = nil, trace: SelectionTrace? = nil, phase: String = "focus") -> AXUIElement? {
    focusedElementQuery(applicationPID: applicationPID, trace: trace, phase: phase).value
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
func selectionDecision(selectedText: String?, selectedRange: CFRange?, rangeText: String?, opaqueDocument: Bool = false,
                       documentContainer: Bool = false) -> SelectionDecision {
    if let text = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .text(text)
    }
    if let range = selectedRange {
        guard validSelectionRange(range) else { return .empty }
        if range.length == 0 { return opaqueDocument ? .copy : .empty }
        if let text = rangeText {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return opaqueDocument || documentContainer ? .copy : .empty
            }
            return .text(text)
        }
        return .copy
    }
    // A document/window wrapper (for example a custom office canvas) may
    // advertise an empty AXSelectedText without implementing text ranges.
    // That is unavailable information, unlike an editor's confirmed empty
    // range. Do not apply this exception to editable text controls.
    return selectedText == nil || opaqueDocument || documentContainer ? .copy : .empty
}

func opaqueSelectionContainer(_ role: String?, bundleIdentifier: String?) -> Bool {
    // Keep this compatibility exception scoped to WPS; a generic editor may
    // implement copy-current-line while reporting no selection information.
    guard bundleIdentifier == "com.kingsoft.wpsoffice.mac" else { return false }
    // WPS also exposes its document canvas as AXSplitGroup with no selected
    // text and a placeholder zero range even while the document has a selection.
    return ["AXWindow", "AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXDocument", "AXWebArea"].contains(role ?? "")
}

func unavailableSelectionRange(_ status: AXError) -> Bool {
    [.attributeUnsupported, .noValue, .notImplemented].contains(status)
}

func readonlySelectionContainer(_ role: String?) -> Bool {
    // The focused document itself is not an ordinary editable input control.
    // Do not infer this from AXWindow/AXGroup or from an arbitrary app name.
    role == "AXWebArea" || role == "AXDocument"
}

enum SelectionQuery<Value> {
    case value(Value)
    case unavailable
    case invalid
    case limited

    var state: String {
        switch self { case .value: return "valid"; case .unavailable: return "unavailable"; case .invalid: return "invalid"; case .limited: return "resourceLimit" }
    }
    var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}

struct SelectionRangeValue {
    let value: AXValue
    let range: CFRange
}

func validSelectionRange(_ range: CFRange) -> Bool {
    range.location >= 0 && range.length >= 0 && !range.location.addingReportingOverflow(range.length).overflow
}

func selectionTextQuery(status: AXError, value: CFTypeRef?) -> SelectionQuery<String> {
    guard status == .success else { return unavailableSelectionRange(status) ? .unavailable : .invalid }
    guard let text = value as? String else { return .invalid }
    return .value(text)
}

func selectionRangeQuery(status: AXError, value: CFTypeRef?) -> SelectionQuery<SelectionRangeValue> {
    guard status == .success else { return unavailableSelectionRange(status) ? .unavailable : .invalid }
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return .invalid }
    let axValue = value as! AXValue
    var range = CFRange(location: -1, length: -1)
    guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range),
          validSelectionRange(range) else { return .invalid }
    return .value(SelectionRangeValue(value: axValue, range: range))
}

func selectionRangesQuery(status: AXError, value: CFTypeRef?) -> SelectionQuery<[SelectionRangeValue]> {
    guard status == .success else { return unavailableSelectionRange(status) ? .unavailable : .invalid }
    guard let value, CFGetTypeID(value) == CFArrayGetTypeID(), let values = value as? [Any],
          values.count <= 64 else { return .invalid }
    var ranges = [SelectionRangeValue]()
    for value in values {
        guard case .value(let range) = selectionRangeQuery(status: .success, value: value as CFTypeRef) else { return .invalid }
        ranges.append(range)
    }
    return .value(ranges)
}

func requireUsableSelectionQuery<Value>(_ query: SelectionQuery<Value>) throws {
    if case .limited = query { throw SelectionProbeBudgetExpired() }
    if case .invalid = query {
        throw NativeError("SELECTION: The application returned invalid selection metadata or an accessibility query failed. Select text and retry.")
    }
}

func requireSelectionCopyTarget(role: String?, subrole: String?) throws {
    try requireUnprotectedSelection(subrole)
    // Reject focus on UI chrome, not text controls inside a dialog. Unknown
    // custom document roles retain the guarded compatibility fallback.
    let nonTextRoles = ["AXSheet", "AXButton", "AXPopUpButton", "AXMenuButton", "AXMenu", "AXMenuItem", "AXMenuBar", "AXMenuBarItem"]
    if nonTextRoles.contains(role ?? "") || (role == "AXWindow" && ["AXDialog", "AXSystemDialog"].contains(subrole ?? "")) {
        throw NativeError("NO_SELECTION: The focused control is not a text selection source.")
    }
}

func selectionFocusClassification(role: SelectionQuery<String>, subrole: SelectionQuery<String>,
                                  copyFallback: Bool) throws -> (role: String?, subrole: String?) {
    try requireUsableSelectionQuery(role)
    try requireUsableSelectionQuery(subrole)
    if copyFallback { try requireSelectionCopyTarget(role: role.value, subrole: subrole.value) }
    else { try requireUnprotectedSelection(subrole.value) }
    return (role.value, subrole.value)
}

func selectionRangesDecision(_ ranges: [CFRange], texts: [String?], opaqueDocument: Bool = false,
                             documentContainer: Bool = false) -> SelectionDecision? {
    guard ranges.count <= 64, ranges.count == texts.count,
          ranges.allSatisfy(validSelectionRange) else { return nil }
    let positive = ranges.indices.filter { ranges[$0].length > 0 }
    guard !positive.isEmpty else { return opaqueDocument ? .copy : .empty }
    guard positive.allSatisfy({ texts[$0] != nil }) else { return .copy }
    let text = positive.compactMap { texts[$0] }.joined(separator: "\n")
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return opaqueDocument || documentContainer ? .copy : .empty
    }
    return .text(text)
}

func requireSelectionForeground(_ original: pid_t?, _ current: pid_t?) throws {
    guard let original = original, original > 0, original == current else {
        throw NativeError("SELECTION: The foreground application changed. Select text in the source application and retry.")
    }
}

func recheckSelectionApplication(_ expected: SelectionApplicationSnapshot, trace: SelectionTrace, phase: String) throws {
    let current = selectionApplicationSnapshot(trace: trace, phase: phase)
    try requireSelectionForeground(expected.pid, current.pid)
    if let bundle = expected.bundleIdentifier, current.bundleIdentifier != bundle {
        throw NativeError("SELECTION: The source application identity changed. Select text and retry.")
    }
}

func requireUnprotectedSelection(_ subrole: String?) throws {
    guard subrole != kAXSecureTextFieldSubrole as String else {
        throw NativeError("NO_SELECTION: Selection capture is unavailable for a protected text field.")
    }
}

struct SelectionContainerEmpty: Error {}

func accessibilitySelection(element: AXUIElement?, bundleIdentifier: String? = nil,
                            trace: SelectionTrace? = nil, phase: String = "ax-selection", deadline: TimeInterval? = nil,
                            recoverContainerEmpty: Bool = false) throws -> String? {
    guard let element = element else {
        trace?.record(phase, ["decision": "focusUnavailable"])
        return nil
    }
    var subrole: CFTypeRef?
    try requireSelectionQueryBudget(deadline)
    let subroleStatus = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
    trace?.record(phase, ["subroleStatus": subroleStatus.rawValue, "subrole": subrole as? String as Any? ?? NSNull()])
    try requireUsableSelectionQuery(selectionTextQuery(status: subroleStatus, value: subrole))
    var role: CFTypeRef?
    try requireSelectionQueryBudget(deadline)
    let roleStatus = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    trace?.record(phase, ["roleStatus": roleStatus.rawValue, "role": role as? String as Any? ?? NSNull()])
    let classification = try selectionFocusClassification(role: selectionTextQuery(status: roleStatus, value: role),
        subrole: selectionTextQuery(status: subroleStatus, value: subrole), copyFallback: false)
    var owner: pid_t = 0
    try requireSelectionQueryBudget(deadline)
    let ownerStatus = AXUIElementGetPid(element, &owner)
    if deadline != nil && ownerStatus != .success { throw unavailableSelectionError() }
    let bundleIdentifier = bundleIdentifier ?? (ownerStatus == .success
        ? onMainThread { NSRunningApplication(processIdentifier: owner)?.bundleIdentifier } : nil)
    let opaqueDocument = opaqueSelectionContainer(classification.role, bundleIdentifier: bundleIdentifier)
    let documentContainer = readonlySelectionContainer(classification.role)
    trace?.record(phase, ["roleStatus": roleStatus.rawValue, "role": role as? String as Any? ?? NSNull(),
        "focusPIDStatus": ownerStatus.rawValue, "focusOwner": owner, "opaqueDocument": opaqueDocument,
        "documentContainer": documentContainer])
    var selected: CFTypeRef?
    try requireSelectionQueryBudget(deadline)
    let textStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected)
    let textQuery = selectionTextQuery(status: textStatus, value: selected)
    if deadline != nil { try requireUsableSelectionQuery(textQuery) }
    let selectedText = textQuery.value
    trace?.record(phase, ["selectedTextStatus": textStatus.rawValue,
        "selectedTextEmpty": selectedText.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } as Any? ?? NSNull()])
    if let text = selectedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        trace?.record(phase, ["decision": "text"])
        return text
    }
    var rangeValue: CFTypeRef?
    var rangeText: String?
    try requireSelectionQueryBudget(deadline)
    let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
    let rangeQuery = selectionRangeQuery(status: rangeStatus, value: rangeValue)
    trace?.record(phase, ["rangeStatus": rangeStatus.rawValue, "rangeState": rangeQuery.state])
    try requireUsableSelectionQuery(rangeQuery)
    let selectedRange = rangeQuery.value?.range
    if let value = rangeQuery.value, value.range.length > 0 {
        var extracted: CFTypeRef?
        try requireSelectionQueryBudget(deadline)
        let status = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                               value.value, &extracted)
        let query = selectionTextQuery(status: status, value: extracted)
        trace?.record(phase, ["rangeTextStatus": status.rawValue])
        try requireUsableSelectionQuery(query)
        rangeText = query.value
    }
    var decision: SelectionDecision?
    // Some document implementations publish only the plural range API. Use
    // public ranges rather than reading the document's AXValue or contents.
    var pluralUnavailable = true
    if shouldQueryPluralSelectionRanges(selectedRange, role: classification.role, opaqueDocument: opaqueDocument,
                                       boundedContainerProbe: deadline != nil) {
        var values: CFTypeRef?
        try requireSelectionQueryBudget(deadline)
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangesAttribute as CFString, &values)
        let query = selectionRangesQuery(status: status, value: values)
        pluralUnavailable = query.state == "unavailable"
        trace?.record(phase, ["pluralStatus": status.rawValue, "pluralState": query.state])
        try requireUsableSelectionQuery(query)
        if let values = query.value {
            var texts = [String?]()
            for value in values {
                try requireSelectionQueryBudget(deadline)
                guard value.range.length > 0 else { texts.append(nil); continue }
                var extracted: CFTypeRef?
                try requireSelectionQueryBudget(deadline)
                let status = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                                       value.value, &extracted)
                let textQuery = selectionTextQuery(status: status, value: extracted)
                trace?.record(phase, ["rangeTextStatus": status.rawValue])
                try requireUsableSelectionQuery(textQuery)
                texts.append(textQuery.value)
            }
            let ranges = values.map(\.range)
            decision = selectionRangesDecision(ranges, texts: texts, opaqueDocument: opaqueDocument,
                                               documentContainer: documentContainer)
            trace?.record(phase, ["rangeCount": ranges.count, "positiveRangeCount": ranges.filter { $0.length > 0 }.count])
        }
    }
    let rangesUnavailable = unavailableSelectionRange(rangeStatus) && pluralUnavailable
    let resolved = decision ?? selectionDecision(selectedText: selectedText, selectedRange: selectedRange, rangeText: rangeText,
        opaqueDocument: opaqueDocument && (rangesUnavailable || selectedRange != nil),
        documentContainer: documentContainer && (rangesUnavailable || selectedRange != nil))
    let decisionName: String
    switch resolved { case .text: decisionName = "text"; case .empty: decisionName = "empty"; case .copy: decisionName = "copy" }
    trace?.record(phase, ["rangeStatus": rangeStatus.rawValue, "rangeLength": selectedRange?.length as Any? ?? NSNull(),
                         "decision": decisionName])
    switch resolved {
    case .text(let text): return text
    case .empty:
        try requireUsableSelectionQuery(textQuery)
        if recoverContainerEmpty && selectionRecoveryContainer(classification.role) { throw SelectionContainerEmpty() }
        throw NativeError("NO_SELECTION: No text is selected in the source application.")
    case .copy:
        try requireUsableSelectionQuery(textQuery)
        try requireSelectionCopyTarget(role: classification.role, subrole: classification.subrole)
        return nil
    }
}

// A container's zero range describes that object, not necessarily the text
// selection in one of its descendants. Recovery only reads public selection
// attributes; it never reads AXValue/document contents or authorizes blind copy.
func selectionRecoveryContainer(_ role: String?) -> Bool {
    ["AXWindow", "AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXDocument", "AXWebArea"].contains(role ?? "")
}

func shouldQueryPluralSelectionRanges(_ range: CFRange?, role: String?, opaqueDocument: Bool,
                                     boundedContainerProbe: Bool = false) -> Bool {
    // Preserve the existing ordinary/WPS path. The newly supported generic
    // zero-range container path runs only inside deadline-bound recovery.
    range == nil || ((opaqueDocument || (boundedContainerProbe && selectionRecoveryContainer(role))) && range?.length == 0)
}

struct SelectionProbeObservation<Node> {
    let text: String?
    let children: [Node]
    let protected: Bool
    var resourceLimit: Bool = false
}

enum SelectionProbeResult: Equatable {
    case text(String)
    case none
    case ambiguous
    case incomplete
    case resourceLimit
    case stale

    var state: String {
        switch self {
        case .text: return "text"
        case .none: return "noPositiveSelection"
        case .ambiguous: return "ambiguousSelection"
        case .incomplete: return "probeInvalid"
        case .resourceLimit: return "probeResourceLimit"
        case .stale: return "contextUnverified"
        }
    }
}

// A partial traversal never supplies text. A resource limit is distinct from
// invalid metadata: it may request an independent, guarded user-action copy,
// but does not certify a selection or the safety of unvisited nodes.
func probeUniqueSelection<Node>(root: Node, maximumNodes: Int = 64, maximumDepth: Int = 6,
                               same: (Node, Node) -> Bool, contextIsCurrent: () -> Bool,
                               withinBudget: () -> Bool = { true },
                               observe: (Node, Int) -> SelectionProbeObservation<Node>?) -> (SelectionProbeResult, Int) {
    guard maximumNodes > 0, maximumDepth >= 0, withinBudget() else { return (.resourceLimit, 0) }
    guard contextIsCurrent() else { return (withinBudget() ? .stale : .resourceLimit, 0) }
    var pending: [(Node, Int)] = [(root, 0)]
    var visited = [Node]()
    var selected: String?
    while !pending.isEmpty {
        let (node, depth) = pending.removeFirst()
        if visited.contains(where: { same($0, node) }) { continue }
        guard withinBudget(), visited.count < maximumNodes, depth <= maximumDepth else { return (.resourceLimit, visited.count) }
        visited.append(node)
        // A hard observer failure wins even if its AX call also used the budget.
        guard let value = observe(node, maximumNodes - visited.count) else { return (.incomplete, visited.count) }
        if value.protected { continue }
        if value.resourceLimit { return (.resourceLimit, visited.count) }
        if let text = value.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard selected == nil else { return (.ambiguous, visited.count) }
            selected = text
            continue
        }
        guard value.children.count <= maximumNodes - visited.count,
              depth < maximumDepth || value.children.isEmpty else { return (.resourceLimit, visited.count) }
        pending.append(contentsOf: value.children.map { ($0, depth + 1) })
    }
    guard withinBudget() else { return (.resourceLimit, visited.count) }
    guard contextIsCurrent() else { return (withinBudget() ? .stale : .resourceLimit, visited.count) }
    guard withinBudget() else { return (.resourceLimit, visited.count) }
    return (selected.map(SelectionProbeResult.text) ?? .none, visited.count)
}

func selectionProbeAllowsCompatibility(_ result: SelectionProbeResult, knownUnsafeTarget: Bool) -> Bool {
    guard !knownUnsafeTarget else { return false }
    return result == .none || result == .resourceLimit
}

// Caught only by the explicit selection action; it is not permission to post
// an event without an independently captured and revalidated window ticket.
struct SelectionCompatibilityRequired: Error { let reason: String }

func unavailableSelectionError() -> NativeError {
    NativeError("SELECTION_UNAVAILABLE: 当前应用未提供可验证的选区或焦点。请先按 Cmd+C，再使用菜单栏的“翻译剪贴板”；也可使用截图识别。")
}

func selectionElementOwnerMatches(_ element: AXUIElement, _ pid: pid_t) -> Bool {
    var owner: pid_t = 0
    let status = AXUIElementGetPid(element, &owner)
    return selectionFocusOwnerMatches(pid, owner, status)
}

func focusedSelectionWindow(applicationPID: pid_t, trace: SelectionTrace? = nil,
                            deadline: TimeInterval) -> SelectionQuery<AXUIElement> {
    guard selectionQueryBudgetAvailable(deadline) else { return .limited }
    let application = AXUIElementCreateApplication(applicationPID)
    guard AXUIElementSetMessagingTimeout(application, 0.03) == .success else { return .invalid }
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value)
    let valid = value.map { CFGetTypeID($0) == AXUIElementGetTypeID() } ?? false
    trace?.record("selection-probe-window", ["focusStatus": status.rawValue, "valueTypeValid": valid])
    guard status == .success else { return unavailableSelectionRange(status) ? .unavailable : .invalid }
    guard valid, let value else { return .invalid }
    let window = value as! AXUIElement
    guard AXUIElementSetMessagingTimeout(window, 0.03) == .success,
          selectionElementOwnerMatches(window, applicationPID) else { return .invalid }
    return selectionQueryBudgetAvailable(deadline) ? .value(window) : .limited
}

func selectionRecoveryRole(_ element: AXUIElement, applicationPID: pid_t,
                           deadline: TimeInterval) throws -> String? {
    try requireSelectionQueryBudget(deadline)
    guard AXUIElementSetMessagingTimeout(element, 0.03) == .success,
          selectionElementOwnerMatches(element, applicationPID) else { throw unavailableSelectionError() }
    var role: CFTypeRef?, subrole: CFTypeRef?
    try requireSelectionQueryBudget(deadline)
    let roleStatus = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    // Validate a hard error before checking the next call's budget.
    let roleQuery = selectionTextQuery(status: roleStatus, value: role)
    try requireUsableSelectionQuery(roleQuery)
    try requireSelectionQueryBudget(deadline)
    let subroleStatus = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
    let classification = try selectionFocusClassification(role: roleQuery,
        subrole: selectionTextQuery(status: subroleStatus, value: subrole), copyFallback: true)
    return selectionRecoveryContainer(classification.role) ? classification.role : nil
}

func selectionEditableRole(_ role: String?) -> Bool {
    ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"].contains(role ?? "")
}

func selectionTargetBlocksCompatibility(isSourceTarget: Bool, role: String?,
                                        rejectedControl: Bool = false, emptySelection: Bool = false) -> Bool {
    isSourceTarget && (rejectedControl || (emptySelection && selectionEditableRole(role)))
}

func selectionNodeExplicitlyFocused(_ element: AXUIElement, deadline: TimeInterval) throws -> Bool {
    try requireSelectionQueryBudget(deadline)
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &value)
    if unavailableSelectionRange(status) { return false }
    guard status == .success, let value, CFGetTypeID(value) == CFBooleanGetTypeID() else {
        throw unavailableSelectionError()
    }
    return CFBooleanGetValue((value as! CFBoolean))
}

func recoverySelection(originalFocus: AXUIElement?, source: SelectionApplicationSnapshot,
                       trace: SelectionTrace) throws -> String {
    guard let pid = source.pid, pid > 0 else { throw unavailableSelectionError() }
    // Soft budget, not a wall-clock guarantee: existing NSWorkspace/system AX
    // calls are nonpreemptible. Per-object candidate messages use 30 ms.
    let deadline = ProcessInfo.processInfo.systemUptime + 0.18
    let root: AXUIElement
    if let originalFocus { root = originalFocus }
    else {
        switch focusedSelectionWindow(applicationPID: pid, trace: trace, deadline: deadline) {
        case .value(let window): root = window
        case .unavailable: throw SelectionCompatibilityRequired(reason: "rootUnavailable")
        case .limited: throw SelectionCompatibilityRequired(reason: "rootResourceLimit")
        case .invalid: throw unavailableSelectionError()
        }
    }
    do {
        guard try selectionRecoveryRole(root, applicationPID: pid, deadline: deadline) != nil else { throw unavailableSelectionError() }
    } catch is SelectionProbeBudgetExpired { throw SelectionCompatibilityRequired(reason: "rootResourceLimit") }
    var observedContextChange = false
    var hardContextFailure = false
    var knownUnsafeTarget = false
    func contextIsCurrent() -> Bool {
        let current = selectionApplicationSnapshot(trace: trace, phase: "foreground-selection-probe")
        guard let currentPID = current.pid, currentPID > 0 else { hardContextFailure = true; return false }
        if currentPID != pid { observedContextChange = true; return false }
        if let expectedBundle = source.bundleIdentifier {
            guard let currentBundle = current.bundleIdentifier else { hardContextFailure = true; return false }
            if currentBundle != expectedBundle { observedContextChange = true; return false }
        }
        let focus = focusedElementQuery(applicationPID: pid, deadline: deadline)
        if focus.state == "invalid" { hardContextFailure = true; return false }
        if focus.state == "resourceLimit" { return false }
        if let originalFocus {
            guard let currentFocus = focus.value else { hardContextFailure = true; return false }
            let same = CFEqual(originalFocus, currentFocus)
            if !same { observedContextChange = true }
            return same
        }
        if focus.value != nil { observedContextChange = true; return false }
        let window = focusedSelectionWindow(applicationPID: pid, deadline: deadline)
        if window.state == "invalid" || window.state == "unavailable" { hardContextFailure = true; return false }
        guard let currentWindow = window.value else { return false }
        let same = CFEqual(root, currentWindow)
        if !same { observedContextChange = true }
        return same
    }
    let (result, count) = probeUniqueSelection(root: root, same: { CFEqual($0, $1) },
        contextIsCurrent: contextIsCurrent,
        withinBudget: { selectionQueryBudgetAvailable(deadline) }) { element, remaining in
        func limited() -> SelectionProbeObservation<AXUIElement> {
            SelectionProbeObservation(text: nil, children: [], protected: false, resourceLimit: true)
        }
        do {
            try requireSelectionQueryBudget(deadline)
            guard AXUIElementSetMessagingTimeout(element, 0.03) == .success,
                  selectionElementOwnerMatches(element, pid) else { return nil }
            var role: CFTypeRef?, subrole: CFTypeRef?
            try requireSelectionQueryBudget(deadline)
            let roleStatus = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            let roleQuery = selectionTextQuery(status: roleStatus, value: role)
            try requireUsableSelectionQuery(roleQuery)
            try requireSelectionQueryBudget(deadline)
            let subroleStatus = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            let subroleQuery = selectionTextQuery(status: subroleStatus, value: subrole)
            try requireUsableSelectionQuery(subroleQuery)
            let sensitive = subroleQuery.value == kAXSecureTextFieldSubrole as String
            // A background empty search/password field is not the source
            // target. Only original or explicitly AXFocused nodes block copy.
            var sourceTarget = originalFocus.map { CFEqual($0, element) } ?? false
            if !sourceTarget && (sensitive || selectionEditableRole(roleQuery.value)) {
                sourceTarget = try selectionNodeExplicitlyFocused(element, deadline: deadline)
            }
            do { try requireSelectionCopyTarget(role: roleQuery.value, subrole: subroleQuery.value) }
            catch {
                if selectionTargetBlocksCompatibility(isSourceTarget: sourceTarget, role: roleQuery.value, rejectedControl: true) { knownUnsafeTarget = true }
                return SelectionProbeObservation(text: nil, children: [], protected: true)
            }
            var text: String?
            do { text = try accessibilitySelection(element: element, bundleIdentifier: source.bundleIdentifier, deadline: deadline) }
            catch let error as NativeError where error.message.hasPrefix("NO_SELECTION:") {
                if selectionTargetBlocksCompatibility(isSourceTarget: sourceTarget, role: roleQuery.value, emptySelection: true) { knownUnsafeTarget = true }
            }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return SelectionProbeObservation(text: text, children: [], protected: false)
            }
            guard selectionRecoveryContainer(roleQuery.value) else {
                return SelectionProbeObservation(text: nil, children: [], protected: false)
            }
            var childCount: CFIndex = 0
            try requireSelectionQueryBudget(deadline)
            let countStatus = AXUIElementGetAttributeValueCount(element, kAXChildrenAttribute as CFString, &childCount)
            if unavailableSelectionRange(countStatus) { return SelectionProbeObservation(text: nil, children: [], protected: false) }
            guard countStatus == .success, childCount >= 0 else { return nil }
            guard childCount <= remaining else { return limited() }
            guard childCount > 0 else { return SelectionProbeObservation(text: nil, children: [], protected: false) }
            var values: CFArray?
            try requireSelectionQueryBudget(deadline)
            guard AXUIElementCopyAttributeValues(element, kAXChildrenAttribute as CFString, 0, childCount, &values) == .success,
                  let values, CFArrayGetCount(values) == childCount else { return nil }
            var children = [AXUIElement]()
            for index in 0..<childCount {
                guard let pointer = CFArrayGetValueAtIndex(values, index) else { return nil }
                let child = Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
                guard CFGetTypeID(child) == AXUIElementGetTypeID() else { return nil }
                children.append(child as! AXUIElement)
            }
            return SelectionProbeObservation(text: nil, children: children, protected: false)
        } catch is SelectionProbeBudgetExpired { return limited() }
        catch { return nil }
    }
    trace.record("selection-probe", ["decision": observedContextChange ? "sourceChanged" : result.state, "probeNodes": count,
        "probeRoot": originalFocus == nil ? "focusedWindow" : "focusContainer"])
    if observedContextChange { throw NativeError("CANCELLED: 原取词窗口或焦点已改变，请重新选择。") }
    guard !hardContextFailure, !knownUnsafeTarget else { throw unavailableSelectionError() }
    if case .text(let text) = result { return text }
    if selectionProbeAllowsCompatibility(result, knownUnsafeTarget: knownUnsafeTarget) {
        throw SelectionCompatibilityRequired(reason: result.state)
    }
    throw unavailableSelectionError()
}

// The compatibility path is an explicit user-requested Copy command, not an
// AX selection proof. Capture its source window before any recovery traversal.
// Returned window titles are not inspected or recorded. This path never
// requests document contents or screenshots.
struct SelectionCopyTicket: Equatable {
    let pid: pid_t
    let bundleIdentifier: String
    let windowID: CGWindowID
}

func selectionWindowNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite else { return nil }
    return number.doubleValue
}

func selectionCopyWindowID(records: [[String: Any]], expectedPID: pid_t) -> CGWindowID? {
    // The list is front-to-back. Do not search for an arbitrary later window
    // owned by the app if another app owns the front normal visible window.
    for record in records {
        guard let layer = selectionWindowNumber(record[kCGWindowLayer as String]), layer.rounded() == layer else { return nil }
        if layer != 0 { continue }
        guard let alpha = selectionWindowNumber(record[kCGWindowAlpha as String]), alpha >= 0, alpha <= 1 else { return nil }
        if alpha == 0 { continue }
        guard let bounds = record[kCGWindowBounds as String] as? [String: Any],
              selectionWindowNumber(bounds["X"]) != nil, selectionWindowNumber(bounds["Y"]) != nil,
              let width = selectionWindowNumber(bounds["Width"]), let height = selectionWindowNumber(bounds["Height"]),
              width >= 0, height >= 0 else { return nil }
        if width == 0 || height == 0 { continue }
        guard let owner = selectionWindowNumber(record[kCGWindowOwnerPID as String]), owner == Double(expectedPID),
              let id = selectionWindowNumber(record[kCGWindowNumber as String]), id > 0,
              id.rounded() == id, id <= Double(UInt32.max) else { return nil }
        return CGWindowID(id)
    }
    return nil
}

func selectionCopyTicket(source: SelectionApplicationSnapshot) -> SelectionCopyTicket? {
    guard let pid = source.pid, pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
          let bundle = source.bundleIdentifier, !bundle.isEmpty,
          let records = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
          let windowID = selectionCopyWindowID(records: records, expectedPID: pid) else { return nil }
    return SelectionCopyTicket(pid: pid, bundleIdentifier: bundle, windowID: windowID)
}

func selectionCompatibilityContextAllowed(ticket: SelectionCopyTicket, current: SelectionCopyTicket?,
                                          originalFocusAvailable: Bool, focusState: String,
                                          sameFocus: Bool, secureInputEnabled: Bool) -> Bool {
    guard !secureInputEnabled, current == ticket else { return false }
    return originalFocusAvailable ? focusState == "valid" && sameFocus : focusState == "unavailable"
}

// Only a single down/up pair may be sent. No menu/global fallback is attempted
// after PID-directed delivery, even if the app ignores it or the clipboard stalls.
struct SelectionCopyDispatch {
    private(set) var issued = false
    mutating func postOnce(_ post: () -> Void) throws {
        guard !issued else { throw unavailableSelectionError() }
        issued = true
        post()
    }
}

func requireSelectionCopyContext(source: SelectionApplicationSnapshot, originalFocus: AXUIElement?,
                                 ticket: SelectionCopyTicket?, trace: SelectionTrace,
                                 phase: String) throws -> AXUIElement? {
    try recheckSelectionApplication(source, trace: trace, phase: phase)
    guard let ticket else {
        return try requireSelectionFocus(originalFocus, applicationPID: source.pid, trace: trace, phase: phase + "-focus")
    }
    // This API returns a system-wide Boolean, not an owner PID. If secure input
    // is enabled anywhere we conservatively decline the compatibility command.
    let secure = IsSecureEventInputEnabled()
    let focus = focusedElementQuery(applicationPID: ticket.pid, trace: trace, phase: phase + "-focus",
                                    deadline: ProcessInfo.processInfo.systemUptime + 0.18)
    let sameFocus = originalFocus.flatMap { previous in focus.value.map { CFEqual(previous, $0) } } ?? false
    let current = selectionCopyTicket(source: source)
    trace.record(phase + "-ticket", ["windowMatches": current == ticket, "copyStrategy": "windowTicket"])
    guard selectionCompatibilityContextAllowed(ticket: ticket, current: current,
        originalFocusAvailable: originalFocus != nil, focusState: focus.state, sameFocus: sameFocus,
        secureInputEnabled: secure) else { throw unavailableSelectionError() }
    // Preserve concrete target protections whenever an AX element is known.
    if let element = focus.value {
        var role: CFTypeRef?, subrole: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let subroleStatus = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        _ = try selectionFocusClassification(role: selectionTextQuery(status: roleStatus, value: role),
            subrole: selectionTextQuery(status: subroleStatus, value: subrole), copyFallback: true)
    }
    return focus.value
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

func requireSelectionFocus(_ expected: AXUIElement?, applicationPID: pid_t?, trace: SelectionTrace? = nil,
                           phase: String = "focus-recheck") throws -> AXUIElement {
    guard let expected,
          let current = focusedElement(applicationPID: applicationPID, trace: trace, phase: phase), CFEqual(expected, current) else {
        trace?.record(phase, ["decision": "focusChangedOrUnavailable"])
        throw NativeError("SELECTION: The focused control changed or is unavailable. Select text and retry.")
    }
    var subrole: CFTypeRef?
    let subroleStatus = AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subrole)
    var role: CFTypeRef?
    let roleStatus = AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role)
    trace?.record(phase, ["roleStatus": roleStatus.rawValue, "role": role as? String as Any? ?? NSNull(),
                         "subroleStatus": subroleStatus.rawValue, "subrole": subrole as? String as Any? ?? NSNull()])
    _ = try selectionFocusClassification(role: selectionTextQuery(status: roleStatus, value: role),
        subrole: selectionTextQuery(status: subroleStatus, value: subrole), copyFallback: true)
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
    let trace = SelectionTrace()
    do {
        let text = try captureSelectedText(trace: trace)
        trace.finish()
        return text
    } catch let error as NativeError {
        trace.finish(errorCategory: error.message.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "NATIVE")
        throw error
    } catch {
        trace.finish(errorCategory: "NATIVE")
        throw error
    }
}

func captureSelectedText(trace: SelectionTrace) throws -> String {
    trace.record("accessibility-preflight")
    try requireAccessibility()
    let source = selectionApplicationSnapshot(trace: trace, phase: "foreground-initial")
    let foregroundPID = source.pid
    try requireSelectionForeground(foregroundPID, foregroundPID)
    // Snapshot while the original source is still foreground, not after a slow
    // probe (which could accidentally adopt the user's newly selected window).
    let initialTicket = selectionCopyTicket(source: source)
    let originalFocusQuery = focusedElementQuery(applicationPID: foregroundPID, trace: trace, phase: "focus-initial")
    let originalFocus = originalFocusQuery.value
    var compatibilityTicket: SelectionCopyTicket?
    do {
        do {
            if let text = try accessibilitySelection(element: originalFocus, bundleIdentifier: source.bundleIdentifier,
                                                    trace: trace, phase: "ax-selection-initial", recoverContainerEmpty: true) {
                try recheckSelectionApplication(source, trace: trace, phase: "foreground-after-ax")
                return text
            }
        } catch is SelectionContainerEmpty {
            return try recoverySelection(originalFocus: originalFocus, source: source, trace: trace)
        }
        if originalFocus == nil {
            guard originalFocusQuery.state == "unavailable" else { throw unavailableSelectionError() }
            return try recoverySelection(originalFocus: nil, source: source, trace: trace)
        }
    } catch let requested as SelectionCompatibilityRequired {
        guard let initialTicket else { throw unavailableSelectionError() }
        compatibilityTicket = initialTicket
        trace.record("copy-compatibility", ["decision": requested.reason, "copyStrategy": "windowTicket"])
    }
    let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    let deadline = ProcessInfo.processInfo.systemUptime + 1.5
    trace.record("modifier-release")
    while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw NativeError("SELECTION: Release the shortcut keys and retry.") }
        Thread.sleep(forTimeInterval: 0.02)
    }
    let currentFocus = try requireSelectionCopyContext(source: source, originalFocus: originalFocus,
        ticket: compatibilityTicket, trace: trace, phase: "foreground-before-copy")
    // An ordinary editable zero range still throws NO_SELECTION. Only the
    // typed container-zero result can retain the independent ticket route.
    do {
        if let text = try accessibilitySelection(element: currentFocus, bundleIdentifier: source.bundleIdentifier,
            trace: trace, phase: "ax-selection-recheck", recoverContainerEmpty: compatibilityTicket != nil) {
            try recheckSelectionApplication(source, trace: trace, phase: "foreground-after-ax-recheck")
            return text
        }
    } catch is SelectionContainerEmpty {
        guard compatibilityTicket != nil else { throw unavailableSelectionError() }
    }
    let pasteboard = NSPasteboard.general
    trace.record("clipboard-snapshot")
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
    _ = try requireSelectionCopyContext(source: source, originalFocus: originalFocus,
        ticket: compatibilityTicket, trace: trace, phase: "foreground-before-copy-event")
    try requireSelectionModifiersReleased()
    guard pasteboard.changeCount == initialCount else {
        throw NativeError("CLIPBOARD_CHANGED: The clipboard changed before selection capture; its newer contents were preserved. Retry.")
    }
    try recheckSelectionApplication(source, trace: trace, phase: "foreground-at-copy-event")
    // Recheck the independently observable window and secure-input state at
    // dispatch, after the final foreground query, without re-targeting a ticket.
    if let ticket = compatibilityTicket {
        guard selectionCopyTicket(source: source) == ticket, !IsSecureEventInputEnabled() else { throw unavailableSelectionError() }
    }
    try requireSelectionModifiersReleased()
    guard pasteboard.changeCount == initialCount else {
        throw NativeError("CLIPBOARD_CHANGED: The clipboard changed during the final target check; its newer contents were preserved. Retry.")
    }
    var dispatch = SelectionCopyDispatch()
    try dispatch.postOnce {
        if let ticket = compatibilityTicket {
            down.postToPid(ticket.pid)
            up.postToPid(ticket.pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
    trace.record("copy-wait", ["copyIssued": true, "copyStrategy": compatibilityTicket == nil ? "verifiedFocus" : "windowTicket"])
    let copied: (changeCount: Int, text: String?)
    do { copied = try copiedSelection(pasteboard, initialCount: initialCount) }
    catch let error as NativeError where compatibilityTicket != nil && error.message.hasPrefix("NO_SELECTION:") {
        // An ignored PID-directed command is not evidence of an empty selection.
        // Keep this failure visible, and never retry via a second event route.
        trace.record("copy-no-update", ["decision": "copyNoUpdate", "copyStrategy": "windowTicket"])
        throw unavailableSelectionError()
    }
    // NSPasteboard offers a generation, not a trustworthy writer PID. Keep the
    // existing stable-generation/read-race/conditional restoration protections.
    var contextError: Error?
    do {
        _ = try requireSelectionCopyContext(source: source, originalFocus: originalFocus,
            ticket: compatibilityTicket, trace: trace, phase: "foreground-after-copy")
    } catch { contextError = error }
    trace.record("clipboard-restore")
    try saved.restore(pasteboard, ifUnchangedSince: copied.changeCount)
    if let contextError {
        trace.record("context-rejected-after-restore")
        throw contextError
    }
    guard let text = copied.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw NativeError("NO_SELECTION: The selection did not contain plain text. Try screenshot OCR.")
    }
    trace.record("copy-completed", ["decision": "text"])
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
    for role in ["AXWindow", "AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXDocument", "AXWebArea", "AXTextArea", "AXTextField", "AXSearchField", "AXComboBox", "AXButton", ""] {
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
          selectionRangesDecision([positive], texts: [" \n"], opaqueDocument: true) == .copy,
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
    try wpsSplitGroupSelectionPolicySelfTest()
    try selectionMetadataPolicySelfTest()
    try selectionClassificationPolicySelfTest()
    try selectionQueryPolicySelfTest()
    try selectionCopyPolicySelfTest()
    try selectionRecoverySelfTest()
    try selectionCompatibilitySelfTest()
}

func selectionRecoverySelfTest() throws {
    func expect(_ condition: Bool) throws {
        if !condition { throw NativeError("SELF_TEST: Bounded selection recovery policy failed.") }
    }
    let zero = CFRange(location: 0, length: 0), positive = CFRange(location: 0, length: 3)
    for role in ["AXGroup", "AXWindow", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXWebArea", "AXDocument"] {
        try expect(selectionRecoveryContainer(role))
        try expect(!shouldQueryPluralSelectionRanges(zero, role: role, opaqueDocument: false))
        try expect(shouldQueryPluralSelectionRanges(zero, role: role, opaqueDocument: false, boundedContainerProbe: true))
        try expect(!shouldQueryPluralSelectionRanges(positive, role: role, opaqueDocument: false, boundedContainerProbe: true))
    }
    for role in ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXButton", ""] {
        try expect(!selectionRecoveryContainer(role))
        try expect(!shouldQueryPluralSelectionRanges(zero, role: role, opaqueDocument: false))
        try expect(selectionDecision(selectedText: nil, selectedRange: zero, rangeText: nil) == .empty)
    }
    try expect(shouldQueryPluralSelectionRanges(nil, role: "AXTextArea", opaqueDocument: false))
    try expect(shouldQueryPluralSelectionRanges(zero, role: "AXGroup", opaqueDocument: true))
    for status in [AXError.noValue, .attributeUnsupported, .notImplemented] {
        try expect(selectionFocusQueryState(status: status, valueTypeValid: false, ownerMatches: false) == "unavailable")
    }
    for status in [AXError.cannotComplete, .apiDisabled, .invalidUIElement, .failure, .illegalArgument] {
        try expect(selectionFocusQueryState(status: status, valueTypeValid: false, ownerMatches: false) == "invalid")
    }
    try expect(selectionFocusQueryState(status: .success, valueTypeValid: true, ownerMatches: true) == "valid")
    try expect(selectionFocusQueryState(status: .success, valueTypeValid: false, ownerMatches: true) == "invalid")
    try expect(selectionFocusQueryState(status: .success, valueTypeValid: true, ownerMatches: false) == "invalid")

    typealias Node = SelectionProbeObservation<Int>
    func node(_ text: String? = nil, _ children: [Int] = [], protected: Bool = false) -> Node {
        Node(text: text, children: children, protected: protected)
    }
    func probe(_ graph: [Int: Node], limit: Int = 64, depth: Int = 6,
               owner: [Int: pid_t] = [:], context: () -> Bool = { true }) -> (SelectionProbeResult, Int) {
        probeUniqueSelection(root: 0, maximumNodes: limit, maximumDepth: depth,
                             same: { $0 == $1 }, contextIsCurrent: context) { id, _ in
            guard selectionFocusOwnerMatches(42, owner[id] ?? 42, .success) else { return nil }
            return graph[id]
        }
    }
    // Replay the Codex container-zero shape and the WeChat focused-window
    // shape with generated nodes only. No real app, clipboard, or AX query.
    let unique = [0: node(nil, [1]), 1: node("selected fixture")]
    try expect(probe(unique).0 == .text("selected fixture"))
    try expect(probe(unique, limit: 2, depth: 1).0 == .text("selected fixture"))
    try expect(probe(unique, limit: 1).0 == .resourceLimit)
    try expect(probe(unique, depth: 0).0 == .resourceLimit)
    try expect(probe([0: node(nil, [1]), 1: node(nil, [2]), 2: node("deep")], depth: 1).0 == .resourceLimit)
    try expect(probe([0: node(nil, [1, 2]), 1: node("one"), 2: node("two")]).0 == .ambiguous)
    try expect(probe([0: node(nil, [1, 2]), 1: node("same"), 2: node("same")]).0 == .ambiguous)
    try expect(probe([0: node(nil, [1]), 1: node("", [])]).0 == .none)
    try expect(probe([0: node(nil, [1]), 1: node("password sentinel", [2], protected: true)]).0 == .none)
    // A protected root cannot leak a descendant even if a malformed fixture
    // tries to attach both text and children to it.
    try expect(probe([0: node("password sentinel", [1], protected: true), 1: node("secret")]).0 == .none)
    try expect(probe(unique, owner: [1: 99]).0 == .incomplete)
    try expect(probe(unique, owner: [0: 99]).0 == .incomplete)
    try expect(probe([0: node(nil, [1])]).0 == .incomplete)
    try expect(probe([0: node(nil, [0])]).0 == .none)
    try expect(probe([0: node("ancestor", [1]), 1: node("duplicate descendant")]).0 == .text("ancestor"))
    try expect(probe(unique, context: { false }).0 == .stale)
    var contextChecks = 0
    let changed = probe(unique, context: { contextChecks += 1; return contextChecks == 1 })
    try expect(changed.0 == .stale && contextChecks == 2)
    let expired = probeUniqueSelection(root: 0, same: { $0 == $1 }, contextIsCurrent: { true }) { _, _ -> Node? in nil }
    try expect(expired.0 == .incomplete)
    let budgetExpired = probeUniqueSelection(root: 0, same: { $0 == $1 }, contextIsCurrent: { true },
                                             withinBudget: { false }) { _, _ -> Node? in node("must not read") }
    try expect(budgetExpired.0 == .resourceLimit && budgetExpired.1 == 0)
    var budgetRemaining = true
    let slowRead = probeUniqueSelection(root: 0, same: { $0 == $1 }, contextIsCurrent: { true },
                                       withinBudget: { budgetRemaining }) { _, _ -> Node? in
        budgetRemaining = false
        return node("late selected text")
    }
    try expect(slowRead.0 == .resourceLimit)
    // The legacy strict path still rejects missing focus; compatibility must
    // use a separate independently revalidated window ticket, never this guard.
    do {
        _ = try requireSelectionFocus(nil, applicationPID: 42)
        throw NativeError("SELF_TEST: Recovery removed the copy focus guard.")
    } catch let error as NativeError where error.message.hasPrefix("SELECTION:") { }
    let trace = SelectionTrace(publish: false)
    trace.record("selection-probe", ["decision": "text", "probeNodes": 2, "probeRoot": "focusedWindow",
        "selectedText": "private selection sentinel", "probeText": "private selection sentinel"])
    let data = try JSONSerialization.data(withJSONObject: trace.snapshot(errorCategory: "SELECTION_UNAVAILABLE"))
    let report = String(decoding: data, as: UTF8.self)
    try expect(!report.contains("private selection sentinel") && report.contains("SELECTION_UNAVAILABLE"))
}

func selectionCompatibilitySelfTest() throws {
    func expect(_ condition: Bool) throws {
        if !condition { throw NativeError("SELF_TEST: Controlled selection-copy policy failed.") }
    }
    func record(_ pid: Int = 42, _ id: Int = 7, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowNumber as String: id,
         kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
         kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 800, "Height": 600]]
    }
    try expect(selectionCopyWindowID(records: [record()], expectedPID: 42) == 7)
    try expect(selectionCopyWindowID(records: [record(99, 9, layer: 25), record()], expectedPID: 42) == 7)
    try expect(selectionCopyWindowID(records: [record(99, 9, alpha: 0), record()], expectedPID: 42) == 7)
    try expect(selectionCopyWindowID(records: [record(99, 9), record()], expectedPID: 42) == nil)
    try expect(selectionCopyWindowID(records: [], expectedPID: 42) == nil)
    for key in [kCGWindowOwnerPID as String, kCGWindowNumber as String, kCGWindowLayer as String,
                kCGWindowAlpha as String, kCGWindowBounds as String] {
        var malformed = record(); malformed.removeValue(forKey: key)
        try expect(selectionCopyWindowID(records: [malformed], expectedPID: 42) == nil)
    }
    for invalid in [true, -1, 0, 1.5, Double.infinity, Double(UInt32.max) + 1] as [Any] {
        var malformed = record(); malformed[kCGWindowNumber as String] = invalid
        try expect(selectionCopyWindowID(records: [malformed], expectedPID: 42) == nil)
    }
    var invalidBounds = record()
    invalidBounds[kCGWindowBounds as String] = ["X": 0, "Y": 0, "Width": Double.nan, "Height": 1]
    try expect(selectionCopyWindowID(records: [invalidBounds], expectedPID: 42) == nil)
    let ticket = SelectionCopyTicket(pid: 42, bundleIdentifier: "fixture.source", windowID: 7)
    func allowed(_ current: SelectionCopyTicket? = nil, original: Bool = false,
                 state: String = "unavailable", same: Bool = false, secure: Bool = false) -> Bool {
        selectionCompatibilityContextAllowed(ticket: ticket, current: current,
            originalFocusAvailable: original, focusState: state, sameFocus: same, secureInputEnabled: secure)
    }
    try expect(allowed(ticket)) // Explicit noValue focus + stable independent source window.
    try expect(allowed(ticket, original: true, state: "valid", same: true))
    try expect(!allowed(ticket, secure: true))
    try expect(!allowed(nil))
    try expect(!allowed(SelectionCopyTicket(pid: 99, bundleIdentifier: "fixture.source", windowID: 7)))
    try expect(!allowed(SelectionCopyTicket(pid: 42, bundleIdentifier: "fixture.other", windowID: 7)))
    try expect(!allowed(SelectionCopyTicket(pid: 42, bundleIdentifier: "fixture.source", windowID: 8)))
    for state in ["invalid", "resourceLimit", "valid"] { try expect(!allowed(ticket, state: state)) }
    try expect(!allowed(ticket, original: true, state: "unavailable"))
    try expect(!allowed(ticket, original: true, state: "valid", same: false))
    for result in [SelectionProbeResult.none, .resourceLimit] {
        try expect(selectionProbeAllowsCompatibility(result, knownUnsafeTarget: false))
        try expect(!selectionProbeAllowsCompatibility(result, knownUnsafeTarget: true))
    }
    for result in [SelectionProbeResult.text("positive"), .ambiguous, .incomplete, .stale] {
        try expect(!selectionProbeAllowsCompatibility(result, knownUnsafeTarget: false))
    }
    for role in ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"] {
        try expect(selectionTargetBlocksCompatibility(isSourceTarget: true, role: role, emptySelection: true))
        try expect(!selectionTargetBlocksCompatibility(isSourceTarget: false, role: role, emptySelection: true))
    }
    try expect(!selectionTargetBlocksCompatibility(isSourceTarget: true, role: "AXGroup", emptySelection: true))
    try expect(selectionTargetBlocksCompatibility(isSourceTarget: true, role: "AXTextField", rejectedControl: true))
    try expect(!selectionTargetBlocksCompatibility(isSourceTarget: false, role: "AXTextField", rejectedControl: true))
    typealias Node = SelectionProbeObservation<Int>
    let graph = [0: Node(text: nil, children: [1, 2], protected: false),
                 1: Node(text: "partial must not escape", children: [], protected: false),
                 2: Node(text: nil, children: [3], protected: false)]
    let partial = probeUniqueSelection(root: 0, maximumDepth: 1, same: { $0 == $1 }, contextIsCurrent: { true }) { id, _ in graph[id] }
    try expect(partial.0 == .resourceLimit)
    try expect(selectionProbeAllowsCompatibility(partial.0, knownUnsafeTarget: false))
    try expect(!selectionProbeAllowsCompatibility(partial.0, knownUnsafeTarget: true))
    var budget = true
    let hardAndExpired = probeUniqueSelection(root: 0, same: { $0 == $1 }, contextIsCurrent: { true },
        withinBudget: { budget }) { _, _ -> Node? in budget = false; return nil }
    try expect(hardAndExpired.0 == .incomplete)
    try expect(!selectionProbeAllowsCompatibility(hardAndExpired.0, knownUnsafeTarget: false))
    var copies = 0
    var dispatcher = SelectionCopyDispatch()
    try dispatcher.postOnce { copies += 1 }
    do {
        try dispatcher.postOnce { copies += 1 }
        throw NativeError("SELF_TEST: Controlled copy retried an already posted command.")
    } catch let error as NativeError where error.message.hasPrefix("SELECTION_UNAVAILABLE:") { }
    try expect(copies == 1 && dispatcher.issued)
    // This fixture never posts CGEvents, queries real AX/secure input, reads a
    // real window list, or accesses the user's general pasteboard.
}

func wpsSplitGroupSelectionPolicySelfTest() throws {
    // The retained real WPS attempt had AXSelectedText=noValue (-25212), a
    // successful singular range of length zero, and a matching focus owner.
    // This fixture tests only that metadata policy, not interactive WPS copy.
    let zero = CFRange(location: 0, length: 0)
    let opaque = opaqueSelectionContainer("AXSplitGroup", bundleIdentifier: "com.kingsoft.wpsoffice.mac")
    guard AXError.noValue.rawValue == -25212, opaque,
          !readonlySelectionContainer("AXSplitGroup"),
          selectionDecision(selectedText: nil, selectedRange: zero, rangeText: nil,
                            opaqueDocument: opaque) == .copy,
          selectionRangesDecision([zero], texts: [nil], opaqueDocument: opaque) == .copy,
          selectionRangesDecision([], texts: [], opaqueDocument: opaque) == .copy else {
        throw NativeError("SELF_TEST: WPS split-group placeholder selection did not retain copy recovery.")
    }
    for (role, bundle) in [("AXSplitGroup", "fixture.generic-editor"), ("AXSplitGroup", nil),
                           ("AXTextArea", "com.kingsoft.wpsoffice.mac"),
                           ("AXTextField", "com.kingsoft.wpsoffice.mac")] as [(String, String?)] {
        let ordinary = opaqueSelectionContainer(role, bundleIdentifier: bundle)
        guard !ordinary,
              selectionDecision(selectedText: nil, selectedRange: zero, rangeText: nil,
                                opaqueDocument: ordinary) == .empty,
              selectionDecision(selectedText: "", selectedRange: zero, rangeText: nil,
                                opaqueDocument: ordinary) == .empty,
              selectionRangesDecision([zero], texts: [nil], opaqueDocument: ordinary) == .empty else {
            throw NativeError("SELF_TEST: WPS split-group recovery leaked into ordinary empty input controls.")
        }
    }
    do {
        // The runtime must reject secure subroles before evaluating the role.
        try requireUnprotectedSelection(kAXSecureTextFieldSubrole as String)
        throw NativeError("SELF_TEST: WPS split-group recovery bypassed protected-field rejection.")
    } catch let error as NativeError where error.message.hasPrefix("NO_SELECTION:") { }
}

func selectionMetadataPolicySelfTest() throws {
    func axRange(_ location: Int, _ length: Int) throws -> AXValue {
        var range = CFRange(location: location, length: length)
        guard let value = AXValueCreate(.cfRange, &range) else {
            throw NativeError("SELF_TEST: Could not create the native range metadata fixture.")
        }
        return value
    }
    func rejected<Value>(_ query: SelectionQuery<Value>) throws -> Bool {
        do { try requireUsableSelectionQuery(query); return false }
        catch let error as NativeError where error.message.hasPrefix("SELECTION:") { return true }
    }
    let zero = try axRange(0, 0), positive = try axRange(3, 7)
    let negativeLocation = try axRange(-1, 1), negativeLength = try axRange(0, -1)
    let overflowing = try axRange(Int.max, 1)
    var point = CGPoint(x: 1, y: 2)
    guard let wrongAXType = AXValueCreate(.cgPoint, &point) else {
        throw NativeError("SELF_TEST: Could not create a wrong-type native metadata fixture.")
    }
    for value in [nil, "not an AXValue" as CFString, NSNumber(value: 7), wrongAXType,
                  negativeLocation, negativeLength, overflowing] as [CFTypeRef?] {
        guard try rejected(selectionRangeQuery(status: .success, value: value)) else {
            throw NativeError("SELF_TEST: Invalid singular native range metadata authorized copy fallback.")
        }
    }
    for value in [nil, "not an array" as CFString, [zero, "bad element"] as NSArray,
                  [positive, negativeLocation] as NSArray, [negativeLength] as NSArray,
                  [overflowing] as NSArray, Array(repeating: zero, count: 65) as NSArray] as [CFTypeRef?] {
        guard try rejected(selectionRangesQuery(status: .success, value: value)) else {
            throw NativeError("SELF_TEST: Invalid plural native range metadata authorized copy fallback.")
        }
    }
    for status in [AXError.cannotComplete, .apiDisabled, .invalidUIElement, .failure, .illegalArgument] {
        guard try rejected(selectionRangeQuery(status: status, value: zero)),
              try rejected(selectionRangesQuery(status: status, value: [zero] as NSArray)),
              try rejected(selectionTextQuery(status: status, value: nil)) else {
            throw NativeError("SELF_TEST: A failed native selection query was mistaken for an unavailable API.")
        }
    }
    for status in [AXError.attributeUnsupported, .noValue, .notImplemented] {
        guard selectionRangeQuery(status: status, value: nil).state == "unavailable",
              selectionRangesQuery(status: status, value: nil).state == "unavailable",
              selectionTextQuery(status: status, value: nil).state == "unavailable" else {
            throw NativeError("SELF_TEST: An explicitly unavailable native selection API lost compatibility recovery.")
        }
    }
    guard let parsedZero = selectionRangeQuery(status: .success, value: zero).value,
          let parsedPositive = selectionRangeQuery(status: .success, value: positive).value,
          let parsedPlural = selectionRangesQuery(status: .success, value: [zero, positive] as NSArray).value,
          parsedPlural.count == 2,
          selectionRangesQuery(status: .success, value: [] as NSArray).value?.isEmpty == true,
          selectionRangesQuery(status: .success, value: Array(repeating: zero, count: 64) as NSArray).value?.count == 64,
          try rejected(selectionTextQuery(status: .success, value: nil)),
          try rejected(selectionTextQuery(status: .success, value: NSNumber(value: 1))),
          selectionTextQuery(status: .success, value: "selected fixture" as CFString).value == "selected fixture" else {
        throw NativeError("SELF_TEST: Native selection metadata parsing lost valid values or accepted invalid text.")
    }
    let opaque = opaqueSelectionContainer("AXSplitGroup", bundleIdentifier: "com.kingsoft.wpsoffice.mac")
    let unavailableText = selectionTextQuery(status: .noValue, value: nil)
    try requireUsableSelectionQuery(unavailableText)
    try requireSelectionCopyTarget(role: "AXSplitGroup", subrole: nil)
    guard selectionDecision(selectedText: unavailableText.value, selectedRange: parsedZero.range, rangeText: nil,
                            opaqueDocument: opaque) == .copy,
          selectionRangesDecision([parsedZero.range], texts: [nil], opaqueDocument: opaque) == .copy,
          selectionDecision(selectedText: nil, selectedRange: parsedZero.range, rangeText: nil) == .empty,
          selectionDecision(selectedText: nil, selectedRange: parsedPositive.range, rangeText: "selected fixture") == .text("selected fixture"),
          selectionRangesDecision(parsedPlural.map(\.range), texts: [nil, "selected fixture"]) == .text("selected fixture") else {
        throw NativeError("SELF_TEST: Parsed metadata lost WPS recovery, positive text or ordinary zero-range protection.")
    }
    for (role, subrole) in [("AXWindow", "AXDialog"), ("AXWindow", "AXSystemDialog"), ("AXSheet", nil),
                           ("AXButton", nil), ("AXPopUpButton", nil), ("AXMenuButton", nil), ("AXMenu", nil),
                           ("AXMenuItem", nil), ("AXMenuBar", nil), ("AXMenuBarItem", nil),
                           ("AXTextArea", kAXSecureTextFieldSubrole as String),
                           ("AXSplitGroup", kAXSecureTextFieldSubrole as String)] as [(String, String?)] {
        do {
            try requireSelectionCopyTarget(role: role, subrole: subrole)
            throw NativeError("SELF_TEST: A non-text or protected focus target authorized blind copy.")
        } catch let error as NativeError where error.message.hasPrefix("NO_SELECTION:") { }
    }
    for (role, subrole) in [("AXWindow", nil), ("AXWindow", "AXStandardWindow"), ("AXSplitGroup", nil),
                           ("AXTextField", nil), ("AXTextArea", nil), ("fixtureCustomDocument", nil)] as [(String, String?)] {
        try requireSelectionCopyTarget(role: role, subrole: subrole)
    }
}

func selectionClassificationPolicySelfTest() throws {
    func accepted(role: SelectionQuery<String>, subrole: SelectionQuery<String>, copyFallback: Bool) throws -> Bool {
        do {
            _ = try selectionFocusClassification(role: role, subrole: subrole, copyFallback: copyFallback)
            return true
        } catch let error as NativeError where error.message.hasPrefix("SELECTION:") || error.message.hasPrefix("NO_SELECTION:") {
            return false
        }
    }
    let window = selectionTextQuery(status: .success, value: "AXWindow" as CFString)
    let split = selectionTextQuery(status: .success, value: "AXSplitGroup" as CFString)
    let absent = selectionTextQuery(status: .noValue, value: nil)
    let secure = selectionTextQuery(status: .success, value: kAXSecureTextFieldSubrole as CFString)
    for copyFallback in [false, true] {
        for status in [AXError.cannotComplete, .apiDisabled, .invalidUIElement, .failure, .illegalArgument] {
            let failed = selectionTextQuery(status: status, value: nil)
            guard try !accepted(role: failed, subrole: absent, copyFallback: copyFallback),
                  try !accepted(role: split, subrole: failed, copyFallback: copyFallback) else {
                throw NativeError("SELF_TEST: A role or subrole query failure bypassed selection classification.")
            }
        }
        for value in [nil, NSNumber(value: 1), [] as NSArray] as [CFTypeRef?] {
            let malformed = selectionTextQuery(status: .success, value: value)
            guard try !accepted(role: malformed, subrole: absent, copyFallback: copyFallback),
                  try !accepted(role: split, subrole: malformed, copyFallback: copyFallback) else {
                throw NativeError("SELF_TEST: A successful role query with invalid type bypassed selection classification.")
            }
        }
        for status in [AXError.attributeUnsupported, .noValue, .notImplemented] {
            let unavailable = selectionTextQuery(status: status, value: nil)
            guard try accepted(role: split, subrole: unavailable, copyFallback: copyFallback),
                  try accepted(role: unavailable, subrole: unavailable, copyFallback: copyFallback) else {
                throw NativeError("SELF_TEST: Explicitly unavailable classification blocked a compatible custom document.")
            }
        }
        guard try !accepted(role: split, subrole: secure, copyFallback: copyFallback),
              try accepted(role: selectionTextQuery(status: .success, value: "AXTextField" as CFString),
                           subrole: absent, copyFallback: copyFallback) else {
            throw NativeError("SELF_TEST: Classification lost protected-field rejection or ordinary text input support.")
        }
    }
    for subrole in ["AXDialog", "AXSystemDialog"] {
        let dialog = selectionTextQuery(status: .success, value: subrole as CFString)
        guard try accepted(role: window, subrole: dialog, copyFallback: false),
              try !accepted(role: window, subrole: dialog, copyFallback: true) else {
            throw NativeError("SELF_TEST: Copy recheck accepted a dialog wrapper or blocked direct readable text.")
        }
    }
    guard try accepted(role: window, subrole: absent, copyFallback: true),
          try accepted(role: split, subrole: absent, copyFallback: true),
          try !accepted(role: selectionTextQuery(status: .success, value: "AXButton" as CFString),
                        subrole: absent, copyFallback: true) else {
        throw NativeError("SELF_TEST: Copy reclassification lost WPS document support or accepted changed UI chrome.")
    }
}

func selectionQueryPolicySelfTest() throws {
    // Exercise current AX vs stale Workspace choices without querying any app.
    let foregroundCases: [(AXError, AXError?, pid_t?, pid_t?, pid_t?, String)] = [
        (.success, .success, 42, 7, 42, "axFocusedApplication"),
        (.success, .success, 42, nil, 42, "axFocusedApplication"),
        (.attributeUnsupported, nil, nil, 7, 7, "workspaceUnsupportedFallback"),
        (.notImplemented, nil, nil, 7, 7, "workspaceUnsupportedFallback"),
        (.noValue, nil, nil, 7, 7, "workspaceNoValueFallback"),
        (.noValue, nil, nil, nil, nil, "unavailable"),
        (.noValue, nil, nil, 0, nil, "unavailable"),
        (.noValue, nil, nil, -1, nil, "unavailable"),
        (.cannotComplete, nil, nil, 7, nil, "unavailable"),
        (.apiDisabled, nil, nil, 7, nil, "unavailable"),
        (.failure, nil, nil, 7, nil, "unavailable"),
        (.invalidUIElement, nil, nil, 7, nil, "unavailable"),
        (.illegalArgument, nil, nil, 7, nil, "unavailable"),
        (.success, .invalidUIElement, nil, 7, nil, "unavailable"),
        (.success, .success, 0, 7, nil, "unavailable"),
        (.success, nil, nil, 7, nil, "unavailable"),
        (.attributeUnsupported, nil, nil, 0, nil, "unavailable")
    ]
    for (status, ownerStatus, pid, workspace, expectedPID, expectedSource) in foregroundCases {
        let actual = selectionForegroundSource(axStatus: status, axPIDStatus: ownerStatus, axPID: pid, workspacePID: workspace)
        guard actual.0 == expectedPID, actual.1 == expectedSource else {
            throw NativeError("SELF_TEST: Selection foreground used stale or invalid application metadata.")
        }
    }
    // Replay the retained noValue foreground failure using generated PIDs.
    // The fallback only establishes a candidate identity; every later source
    // and focused-element owner must still match, including when AX recovers.
    let fallback = selectionForegroundSource(axStatus: .noValue, axPIDStatus: nil,
                                            axPID: nil, workspacePID: 42)
    guard AXError.noValue.rawValue == -25212, fallback.0 == 42,
          fallback.1 == "workspaceNoValueFallback" else {
        throw NativeError("SELF_TEST: Missing focused-application AX values lost the live Workspace candidate.")
    }
    let rechecks: [(AXError, AXError?, pid_t?, pid_t?, Bool)] = [
        (.noValue, nil, nil, 42, true),
        (.success, .success, 42, 42, true),
        (.attributeUnsupported, nil, nil, 42, true),
        (.noValue, nil, nil, 43, false),
        (.noValue, nil, nil, nil, false),
        (.success, .success, 43, 42, false),
        (.success, .invalidUIElement, nil, 42, false),
        (.cannotComplete, nil, nil, 42, false),
        (.apiDisabled, nil, nil, 42, false)
    ]
    for (status, pidStatus, pid, workspace, expected) in rechecks {
        let current = selectionForegroundSource(axStatus: status, axPIDStatus: pidStatus,
                                                axPID: pid, workspacePID: workspace)
        var accepted = true
        do { try requireSelectionForeground(fallback.0, current.0) }
        catch { accepted = false }
        guard accepted == expected else {
            throw NativeError("SELF_TEST: Workspace fallback accepted a changed or unverified source application.")
        }
    }
    guard selectionFocusOwnerMatches(fallback.0, 42, .success),
          !selectionFocusOwnerMatches(fallback.0, 43, .success),
          !selectionFocusOwnerMatches(fallback.0, 42, .cannotComplete) else {
        throw NativeError("SELF_TEST: Workspace fallback bypassed focused-element owner validation.")
    }
    guard selectionFocusOwnerMatches(42, 42, .success),
          !selectionFocusOwnerMatches(42, 7, .success),
          !selectionFocusOwnerMatches(nil, 42, .success),
          !selectionFocusOwnerMatches(0, 0, .success),
          !selectionFocusOwnerMatches(42, 42, .invalidUIElement) else {
        throw NativeError("SELF_TEST: Selection focus fallback accepted a foreign or unverified owner.")
    }
    do {
        _ = try requireSelectionFocus(nil, applicationPID: 42)
        throw NativeError("SELF_TEST: Unavailable focus allowed an unguarded copy.")
    } catch let error as NativeError where error.message.hasPrefix("SELECTION:") { }
    let zero = CFRange(location: 2, length: 0), positive = CFRange(location: 2, length: 3)
    for role in ["AXWebArea", "AXDocument", "AXTextField", "AXTextArea", "AXSearchField", "AXGroup", "AXWindow", ""] {
        let document = readonlySelectionContainer(role)
        guard document == ["AXWebArea", "AXDocument"].contains(role),
              selectionDecision(selectedText: "", selectedRange: nil, rangeText: nil,
                                documentContainer: document) == (document ? .copy : .empty),
              selectionDecision(selectedText: "", selectedRange: positive, rangeText: "",
                                documentContainer: document) == (document ? .copy : .empty),
              selectionDecision(selectedText: "", selectedRange: zero, rangeText: nil,
                                documentContainer: document) == .empty,
              selectionRangesDecision([positive], texts: [""], documentContainer: document) == (document ? .copy : .empty),
              selectionRangesDecision([zero], texts: [nil], documentContainer: document) == .empty,
              selectionDecision(selectedText: "", selectedRange: CFRange(location: -1, length: 3), rangeText: "",
                                documentContainer: document) == .empty else {
            throw NativeError("SELF_TEST: Readonly selection recovery weakened ordinary input empty-range protection.")
        }
    }
    guard selectionDecision(selectedText: "", selectedRange: positive, rangeText: "", opaqueDocument: true) == .copy,
          selectionDecision(selectedText: "", selectedRange: nil, rangeText: nil,
              documentContainer: readonlySelectionContainer("AXWebArea") && unavailableSelectionRange(.cannotComplete)) == .empty else {
        throw NativeError("SELF_TEST: Selection document recovery confused a query error with unsupported ranges.")
    }
    let before = try JSONSerialization.data(withJSONObject: SelectionTrace.lastSnapshot(), options: [.sortedKeys])
    let trace = SelectionTrace(publish: false)
    trace.record("fixture", ["role": String(repeating: "a", count: 500), "copyIssued": true,
        "text": "private-selection-sentinel", "clipboard": "private-clipboard-sentinel", "title": "private-title-sentinel"])
    for _ in 0..<64 { trace.record("bounded-fixture") }
    let snapshot = trace.snapshot(state: "failed", errorCategory: "private-error-sentinel")
    let encoded = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
    let serialized = String(decoding: encoded, as: UTF8.self)
    let events = snapshot["events"] as? [[String: Any]] ?? []
    let after = try JSONSerialization.data(withJSONObject: SelectionTrace.lastSnapshot(), options: [.sortedKeys])
    let diagnosticResponse = nativeResponse(mode: "--selection-diagnostics")
    let modeSnapshot = diagnosticResponse["diagnostics"] as? [String: Any] ?? [:]
    let modeEncoded = try JSONSerialization.data(withJSONObject: modeSnapshot, options: [.sortedKeys])
    guard events.count == SelectionTrace.maximumEvents, snapshot["eventsTruncated"] as? Bool == true,
          snapshot["copyIssued"] as? Bool == true, snapshot["errorCategory"] as? String == "NATIVE",
          (events[1]["role"] as? String)?.count == 256,
          !serialized.contains("private-"), before == after,
          diagnosticResponse["ok"] as? Bool == true, modeEncoded == before else {
        throw NativeError("SELF_TEST: Selection diagnostics leaked content, grew unbounded or changed the runtime trace.")
    }
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
func systemInstalledTranslationContractSelfTest() throws {
    let session = TranslationSession(installedSource: Locale.Language(identifier: "zh-Hans"),
                                     target: Locale.Language(identifier: "en"))
    guard !session.canRequestDownloads,
          systemTranslationFailure(TranslationError.notInstalled).message.hasPrefix("SYSTEM_TRANSLATION_DOWNLOAD_REQUIRED:"),
          systemTranslationFailure(TranslationError.unsupportedLanguagePairing).message.hasPrefix("SYSTEM_TRANSLATION_UNSUPPORTED:"),
          systemTranslationFailure(CancellationError()).message.hasPrefix("SYSTEM_TRANSLATION_CANCELLED:") else {
        throw NativeError("SELF_TEST: Installed-only translation contract failed.")
    }
    try systemTranslationStatusPolicySelfTest()
}

@available(macOS 26.0, *)
func systemTranslationStatusPayload(_ state: LanguageAvailability.Status, source: String,
                                    target: String, starterPair: Bool) -> [String: Any] {
    let status: String
    let available: Bool
    let requiresSetup: Bool
    var message: String
    switch state {
    case .installed:
        status = "installed"; available = true; requiresSetup = false
        message = "此语言组合已可使用 Apple 系统翻译，无需 API 密钥。"
    case .supported:
        status = "supported"; available = false; requiresSetup = true
        message = "此语言组合受系统支持，可直接尝试翻译；需要语言包时再点击「准备系统翻译」。"
    case .unsupported:
        status = "unsupported"; available = false; requiresSetup = false
        message = "Apple 系统翻译不支持此语言组合，请选择其他语言或翻译服务。"
    @unknown default:
        status = "unavailable"; available = false; requiresSetup = false
        message = "无法确认系统翻译状态，请重试。"
    }
    if starterPair { message += " 当前检查的是 \(source) → \(target)，其他源语言将分别检查。" }
    return ["supported": true, "available": available, "requiresSetup": requiresSetup,
            "status": status, "platform": "macos", "providerName": "Apple 系统翻译",
            "minimumVersion": "26.0", "onDevice": true, "source": source,
            "target": target, "starterPair": starterPair, "message": message]
}

@available(macOS 26.0, *)
func systemTranslationStatusPolicySelfTest() throws {
    let supported = systemTranslationStatusPayload(.supported, source: "zh-Hans", target: "en", starterPair: false)
    let installed = systemTranslationStatusPayload(.installed, source: "en", target: "zh-Hans", starterPair: false)
    let unsupported = systemTranslationStatusPayload(.unsupported, source: "ja", target: "ko", starterPair: true)
    guard supported["status"] as? String == "supported",
          supported["available"] as? Bool == false,
          supported["requiresSetup"] as? Bool == true,
          supported["message"] as? String == "此语言组合受系统支持，可直接尝试翻译；需要语言包时再点击「准备系统翻译」。",
          installed["status"] as? String == "installed",
          installed["available"] as? Bool == true,
          installed["requiresSetup"] as? Bool == false,
          unsupported["status"] as? String == "unsupported",
          unsupported["requiresSetup"] as? Bool == false,
          unsupported["starterPair"] as? Bool == true,
          unsupported["source"] as? String == "ja", unsupported["target"] as? String == "ko" else {
        throw NativeError("SELF_TEST: Advisory translation availability was mistaken for a missing or installed language pack.")
    }
}

@available(macOS 26.0, *)
func availableSystemTranslation(_ request: SystemTranslationInput) async throws -> [String: Any] {
    let (source, starterPair) = try systemSourceLanguage(request, forTranslation: false)
    let state: LanguageAvailability.Status
    if systemLanguagesEquivalent(source, request.target) { state = .installed }
    else { state = await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: request.target)) }
    return systemTranslationStatusPayload(state, source: source, target: request.target, starterPair: starterPair)
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
func translateWithSystem(_ request: SystemTranslationInput, trace: SystemTranslationTrace) async throws -> [String: Any] {
    let (source, _) = try systemSourceLanguage(request, forTranslation: true)
    let text = request.text ?? ""
    // Preserve the requested Chinese script. Do not substitute generic zh or
    // another target if Apple's availability/session rejects the exact pair.
    if systemLanguagesEquivalent(source, request.target) {
        return ["text": text, "sourceLanguage": source, "targetLanguage": request.target]
    }
    // Availability is advisory in Settings and can be transient. This session
    // cannot request downloads; translate reports the actual installed state.
    trace.phase("createSession")
    let session = TranslationSession(installedSource: Locale.Language(identifier: source), target: Locale.Language(identifier: request.target))
    guard !session.canRequestDownloads else {
        throw NativeError("SYSTEM_TRANSLATION_FAILED: 系统翻译未能进入本机语言模式。")
    }
    do {
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            trace.phase("translate")
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
    } catch { trace.failure(error); throw systemTranslationFailure(error) }
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
            let trace = SystemTranslationTrace()
            do {
                var response = try awaitSystemTranslation(seconds: 45, operationId: request.operationId) { try await translateWithSystem(request, trace: trace) }
                trace.phase("completed")
                response["ok"] = true
                return response
            } catch { trace.failure(error); throw error }
        case "--prepare-system-translation":
            return ["ok": true, "systemTranslation": try prepareSystemTranslation(request)]
        default: break
        }
    }
    #endif
    if mode == "--system-translation-status" { return ["ok": true, "systemTranslation": systemTranslationUnavailable()] }
    throw NativeError("SYSTEM_TRANSLATION_UNAVAILABLE: 当前免 API 系统翻译需要 macOS 26 或更新版本；也可以配置自己的翻译服务。")
}

// Latest Apple translation operation only. No source/target text, arbitrary
// error descriptions/userInfo, clipboard data or credentials are retained.
final class SystemTranslationTrace: @unchecked Sendable {
    private static let lock = NSLock()
    private static var next: UInt64 = 0
    private static var latest: [String: Any] = [:]
    private let id: UInt64
    private let started = ProcessInfo.processInfo.systemUptime
    init() {
        Self.lock.lock()
        Self.next &+= 1; id = Self.next
        Self.latest = ["attemptId": id, "phase": "started", "elapsedMs": 0,
                       "startedAtUnixMs": Int64(Date().timeIntervalSince1970 * 1000)]
        Self.lock.unlock()
    }
    func phase(_ phase: String) {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard Self.latest["attemptId"] as? UInt64 == id,
              !["failed", "completed"].contains(Self.latest["phase"] as? String ?? "") else { return }
        Self.latest["phase"] = phase
        Self.latest["elapsedMs"] = (ProcessInfo.processInfo.systemUptime - started) * 1000
    }
    func failure(_ error: Error) {
        let native = error as NSError
        let domain: String
        switch native.domain {
        case NSCocoaErrorDomain: domain = "cocoa"
        case NSURLErrorDomain: domain = "url"
        case NSPOSIXErrorDomain: domain = "posix"
        default: domain = "other"
        }
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard Self.latest["attemptId"] as? UInt64 == id else { return }
        // Keep the first underlying error instead of overwriting it with our
        // user-facing NativeError wrapper after it crosses the C ABI boundary.
        if Self.latest["nativeErrorCode"] == nil {
            Self.latest["nativeErrorCode"] = native.code
            Self.latest["nativeErrorDomain"] = domain
            Self.latest["errorType"] = error is NativeError ? "native" : error is CancellationError ? "cancelled" : "framework"
        }
        if Self.latest["failurePhase"] == nil { Self.latest["failurePhase"] = Self.latest["phase"] }
        Self.latest["phase"] = "failed"
        Self.latest["elapsedMs"] = (ProcessInfo.processInfo.systemUptime - started) * 1000
    }
    static func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }; return latest
    }
}

func systemTranslationTraceSelfTest() throws {
    let old = SystemTranslationTrace()
    old.phase("translate")
    old.failure(NSError(domain: "secret-user-data", code: 71, userInfo: [NSLocalizedDescriptionKey: "private source text"]))
    old.phase("completed")
    let failed = SystemTranslationTrace.snapshot()
    let serialized = String(data: try JSONSerialization.data(withJSONObject: failed), encoding: .utf8) ?? ""
    guard failed["phase"] as? String == "failed", failed["failurePhase"] as? String == "translate",
          failed["nativeErrorDomain"] as? String == "other", failed["nativeErrorCode"] as? Int == 71,
          !serialized.contains("secret"), !serialized.contains("private") else {
        throw NativeError("SELF_TEST: Translation health retained content or lost failure.")
    }
    let current = SystemTranslationTrace()
    current.phase("translate")
    old.failure(NSError(domain: NSURLErrorDomain, code: 3))
    guard SystemTranslationTrace.snapshot()["phase"] as? String == "translate",
          SystemTranslationTrace.snapshot()["nativeErrorCode"] == nil else {
        throw NativeError("SELF_TEST: Old translation overwrote newer diagnostics.")
    }
    current.phase("completed")
}

func diagnostics() -> [String: Any] {
    let languages = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
    return ["platform": "macos", "helper": "swift-appkit-vision", "localOcr": true,
            "nativeExecution": "in-process-static", "permissions": permissionStatus(),
            "accessibilityGranted": AXIsProcessTrusted(),
            "screenCaptureGranted": CGPreflightScreenCaptureAccess(),
            "ocrLanguages": languages, "ocrEngine": "Apple Vision",
            "selection": "Accessibility selected text, then Cmd+C with clipboard restoration",
            "lastSelectionCapture": SelectionTrace.lastSnapshot(),
            "lastSystemTranslation": SystemTranslationTrace.snapshot(),
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
            "opaqueOfficeSelectionPolicyFixturePassed": true, "wpsSplitGroupPolicyFixturePassed": true,
            "selectionMetadataPolicyFixturePassed": true,
            "selectionClassificationPolicyFixturePassed": true,
            "pluralSelectionRangesFixturePassed": true,
            "selectionQueryPolicyFixturePassed": true, "selectionTracePrivacyFixturePassed": true,
            "selectionCopyCompletionFixturePassed": true, "selectionRecoveryFixturePassed": true,
            "controlledSelectionCopyFixturePassed": true,
            "wpsInteractiveSelectionTested": false, "codexInteractiveSelectionTested": false, "wechatInteractiveSelectionTested": false,
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
        case "--selection-diagnostics": return ["ok": true, "diagnostics": SelectionTrace.lastSnapshot()]
        case "--selection-policy-self-test":
            try selectionPolicySelfTest()
            let privatePasteboardTested = Thread.isMainThread
            if privatePasteboardTested { try privatePasteboardSelfTest() }
            return ["ok": true, "diagnostics": ["selectionPolicyFixturePassed": true,
                    "wpsSplitGroupPolicyFixturePassed": true,
                    "selectionMetadataPolicyFixturePassed": true,
                    "selectionClassificationPolicyFixturePassed": true,
                    "selectionQueryPolicyFixturePassed": true, "selectionTracePrivacyFixturePassed": true,
                    "selectionCopyCompletionFixturePassed": true, "selectionRecoveryFixturePassed": true,
            "controlledSelectionCopyFixturePassed": true,
                    "privatePasteboardFixturePassed": privatePasteboardTested,
                    "generalClipboardTouched": false, "permissionRequested": false,
                    "wpsInteractiveSelectionTested": false, "codexInteractiveSelectionTested": false, "wechatInteractiveSelectionTested": false]]
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
            try systemTranslationTraceSelfTest()
            var cancellationTested = false
            var installedOnlyContractTested = false
            #if canImport(Translation) && compiler(>=6.2)
            try systemTranslationCancellationSelfTest()
            cancellationTested = true
            if #available(macOS 26.0, *) {
                try systemInstalledTranslationContractSelfTest()
                installedOnlyContractTested = true
            }
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
            return ["ok": true, "diagnostics": ["systemTranslationPolicyFixturePassed": true, "systemTranslationOutputFixturePassed": true, "systemTranslationOutputFixtureCount": 19, "systemTranslationCancellationFixturePassed": cancellationTested, "systemTranslationCancellationFixtureSkipped": !cancellationTested, "systemTranslationInstalledOnlyFixturePassed": installedOnlyContractTested, "translationEngineCalled": false, "languageDownloadRequested": false]]
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
