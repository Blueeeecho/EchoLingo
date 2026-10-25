// Read-only installed-app window probe. No screenshots, window titles, source
// application content, clipboard or permission requests are collected.
import AppKit
import CoreGraphics
import Foundation

let bundleID = "io.github.blueeeecho.echolingo"
guard CommandLine.arguments.count == 2,
      let pid = Int32(CommandLine.arguments[1]),
      let application = NSRunningApplication(processIdentifier: pid),
      application.bundleIdentifier == bundleID else {
    fputs("Expected the PID of a running EchoLingo app bundle.\n", stderr)
    exit(1)
}
guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    fputs("Could not inspect onscreen window metadata.\n", stderr)
    exit(1)
}
let ownWindows = windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }
let regularWindows = ownWindows.filter {
    guard ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
          let bounds = $0[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? NSNumber,
          let height = bounds["Height"] as? NSNumber else { return false }
    return width.doubleValue >= 100 && height.doubleValue >= 100
}
let report: [String: Any] = [
    "bundleIdentifier": bundleID,
    "processId": pid,
    "onscreenRegularWindowCount": regularWindows.count,
    "frontmostIsEchoLingo": NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
    "applicationIsHidden": application.isHidden,
    "windowTitlesCollected": false,
    "screenshotsTaken": false,
    "permissionRequestsMade": false
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
