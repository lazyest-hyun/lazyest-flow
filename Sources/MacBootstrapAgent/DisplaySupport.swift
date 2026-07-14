import AppKit
import ApplicationServices
import Foundation

func displayID(for screen: NSScreen) -> UInt32 {
  screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
}

func currentDisplayID() -> UInt32? {
  NSScreen.main.map(displayID(for:))
}

func displayTitle(for targetID: UInt32) -> String? {
  let screens = sortedScreens()
  guard let index = screens.firstIndex(where: { displayID(for: $0) == targetID }) else {
    return nil
  }
  let screen = screens[index]
  return "\(screen.localizedName) · Display \(index + 1) · ID \(targetID)"
}

func currentDockDisplayIDFromWindowServer() -> UInt32? {
  dockDisplayIDFromWindowList([.optionOnScreenOnly, .excludeDesktopElements])
    ?? dockDisplayIDFromWindowList(.optionAll)
}

func appHasVisibleWindows(processIdentifier: pid_t) -> Bool {
  guard
    let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
  else {
    return false
  }
  return windowInfo.contains { window in
    guard (window[kCGWindowOwnerPID as String] as? pid_t) == processIdentifier else {
      return false
    }
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    guard layer == 0 else {
      return false
    }
    guard let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
      let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
    else {
      return false
    }
    return bounds.width > 1 && bounds.height > 1
  }
}

private func dockDisplayIDFromWindowList(_ options: CGWindowListOption) -> UInt32? {
  guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
  else {
    return nil
  }
  let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
    .first?.processIdentifier
  return windowInfo.compactMap { dockWindowDisplayID(from: $0, dockPID: dockPID) }.first
}

private func dockWindowDisplayID(from window: [String: Any], dockPID: pid_t?) -> UInt32? {
  let ownerName = window[kCGWindowOwnerName as String] as? String
  let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
  let isDockOwner = ownerName == "Dock" || (dockPID != nil && ownerPID == dockPID)
  let name = window[kCGWindowName as String] as? String
  let layer = window[kCGWindowLayer as String] as? Int
  guard isDockOwner, name == "Dock" || layer == 20,
    let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
    let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
  else {
    return nil
  }
  let midpoint = CGPoint(x: bounds.midX, y: bounds.midY)
  for screen in NSScreen.screens {
    let id = displayID(for: screen)
    if CGDisplayBounds(id).contains(midpoint) {
      return id
    }
  }
  return nil
}

func sortedScreens() -> [NSScreen] {
  NSScreen.screens.sorted {
    if $0.frame.minX == $1.frame.minX {
      return $0.frame.minY < $1.frame.minY
    }
    return $0.frame.minX < $1.frame.minX
  }
}

func agentMenuBarIcon() -> NSImage {
  let image = NSImage(size: NSSize(width: 18, height: 18))
  image.lockFocus()
  NSColor.black.setStroke()
  NSColor.black.setFill()

  let stroke = NSBezierPath()
  stroke.lineWidth = 1.8
  stroke.lineCapStyle = .round
  stroke.lineJoinStyle = .round
  stroke.move(to: NSPoint(x: 9, y: 3))
  stroke.line(to: NSPoint(x: 9, y: 15))
  stroke.move(to: NSPoint(x: 4.5, y: 6))
  stroke.curve(
    to: NSPoint(x: 9, y: 3.2), controlPoint1: NSPoint(x: 4.8, y: 3.8),
    controlPoint2: NSPoint(x: 7.1, y: 3.1))
  stroke.curve(
    to: NSPoint(x: 13.5, y: 6), controlPoint1: NSPoint(x: 10.9, y: 3.1),
    controlPoint2: NSPoint(x: 13.2, y: 3.8))
  stroke.stroke()

  let top = NSBezierPath(
    roundedRect: NSRect(x: 5.2, y: 11.2, width: 7.6, height: 3.6), xRadius: 1.8, yRadius: 1.8)
  top.lineWidth = 1.6
  top.stroke()

  let leftDot = NSBezierPath(ovalIn: NSRect(x: 4.0, y: 7.8, width: 2.4, height: 2.4))
  leftDot.fill()
  let rightDot = NSBezierPath(ovalIn: NSRect(x: 11.6, y: 7.8, width: 2.4, height: 2.4))
  rightDot.fill()

  image.unlockFocus()
  image.isTemplate = true
  image.accessibilityDescription = "MacBootstrapAgent"
  return image
}
