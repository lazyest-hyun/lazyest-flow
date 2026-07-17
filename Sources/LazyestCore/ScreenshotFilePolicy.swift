public enum ScreenshotFilePolicy {
  public static let maxEncodedBytes = 64 * 1024 * 1024
  public static let maxPixelCount = 50_000_000
  public static let maxPNGCompatibilityPixelCount = 25_000_000

  public static func acceptsEncodedByteCount(_ byteCount: Int) -> Bool {
    byteCount > 0 && byteCount <= maxEncodedBytes
  }

  public static func acceptsImage(width: Int, height: Int, frameCount: Int) -> Bool {
    guard width > 0, height > 0, frameCount == 1 else { return false }
    return width <= maxPixelCount / height
  }

  public static func shouldCreatePNGCompatibilityImage(width: Int, height: Int) -> Bool {
    guard width > 0, height > 0 else { return false }
    return width <= maxPNGCompatibilityPixelCount / height
  }
}
