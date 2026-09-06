import AppKit
import ApplicationServices
import Foundation

@discardableResult
func openAccessibilitySystemSettings() -> Bool {
  guard
    let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
  else {
    return false
  }
  return NSWorkspace.shared.open(url)
}

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

func applicationIsHidden(_ application: NSRunningApplication) -> Bool {
  let element = AXUIElementCreateApplication(application.processIdentifier)
  var value: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(element, kAXHiddenAttribute as CFString, &value) == .success,
    let number = value as? NSNumber
  else {
    return application.isHidden
  }
  return number.boolValue
}

@discardableResult
func setApplicationHidden(_ application: NSRunningApplication, _ hidden: Bool) -> Bool {
  let element = AXUIElementCreateApplication(application.processIdentifier)
  let value = NSNumber(value: hidden)
  if AXUIElementSetAttributeValue(element, kAXHiddenAttribute as CFString, value) == .success {
    return true
  }
  return hidden ? application.hide() : application.unhide()
}

func visibleApplicationBehind(excluding processIdentifiers: Set<pid_t>) -> NSRunningApplication? {
  guard
    let windowInfo = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
  else {
    return nil
  }

  var seen = Set<pid_t>()
  for window in windowInfo {
    guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
      !processIdentifiers.contains(ownerPID),
      (window[kCGWindowLayer as String] as? Int ?? 0) == 0,
      (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
      seen.insert(ownerPID).inserted,
      let application = NSRunningApplication(processIdentifier: ownerPID),
      application.activationPolicy == .regular,
      !application.isTerminated,
      !applicationIsHidden(application)
    else {
      continue
    }
    return application
  }
  return nil
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
  let path = NSBezierPath()
  path.move(to: NSPoint(x: 2, y: 4))
  path.curve(
    to: NSPoint(x: 15.5, y: 13.5),
    controlPoint1: NSPoint(x: 10, y: 2.5), controlPoint2: NSPoint(x: 7, y: 15))
  path.move(to: NSPoint(x: 11.5, y: 14.5))
  path.line(to: NSPoint(x: 15.5, y: 13.5))
  path.line(to: NSPoint(x: 14.5, y: 9.5))
  path.lineWidth = 1.8
  path.lineCapStyle = .round
  path.lineJoinStyle = .round
  path.stroke()
  image.unlockFocus()
  image.isTemplate = true
  image.accessibilityDescription = "Lazyest Flow"
  return image
}
