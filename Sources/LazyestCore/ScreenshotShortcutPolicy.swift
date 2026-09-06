import CoreGraphics

/// Only the native full-screen and region shortcuts are exchanged.
/// Screenshot toolbar, Option combinations and key repeats remain untouched.
public enum ScreenshotShortcutPolicy {
  public static func shouldSwap(keyCode: Int, flags: CGEventFlags, isRepeat: Bool) -> Bool {
    !isRepeat && (keyCode == 20 || keyCode == 21)
      && flags.contains([.maskCommand, .maskShift])
      && !flags.contains(.maskAlternate)
  }

  public static func forwardedFlags(_ flags: CGEventFlags) -> CGEventFlags {
    var result = flags
    if result.contains(.maskControl) {
      result.remove(.maskControl)
    } else {
      result.insert(.maskControl)
    }
    return result
  }

  // Include BOTH Control keys: file captures must wait for the physical
  // Control key to be released or macOS can still choose the clipboard path.
  public static func releaseKeys(triggerKeyCode: CGKeyCode) -> [CGKeyCode] {
    [triggerKeyCode, 54, 55, 56, 60, 59, 62]
  }
}
