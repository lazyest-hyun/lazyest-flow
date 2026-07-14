public enum InputDeviceRolePolicy {
  private static let genericDesktopPage = 1
  private static let keyboardPage = 7
  private static let consumerPage = 12
  private static let mouseUsage = 2
  private static let keyboardUsage = 6
  private static let xUsage = 0x30
  private static let yUsage = 0x31
  private static let wheelUsage = 0x38
  private static let consumerWheelUsage = 0x238

  public static func isTrackpad(identity: String) -> Bool {
    identity.lowercased().contains("trackpad")
  }

  public static func confirmsKeyboard(
    primaryUsagePage: Int,
    primaryUsage: Int,
    elementUsagePage: Int,
    isBuiltIn: Bool,
    isVirtual: Bool
  ) -> Bool {
    !isBuiltIn && !isVirtual && primaryUsagePage == genericDesktopPage
      && primaryUsage == keyboardUsage && elementUsagePage == keyboardPage
  }

  public static func confirmsMouse(
    primaryUsagePage: Int,
    primaryUsage: Int,
    elementUsagePage: Int,
    elementUsage: Int,
    isBuiltIn: Bool,
    isVirtual: Bool,
    isTrackpad: Bool
  ) -> Bool {
    !isBuiltIn && !isVirtual && !isTrackpad && primaryUsagePage == genericDesktopPage
      && primaryUsage == mouseUsage
      && isPointerOrWheelElement(usagePage: elementUsagePage, usage: elementUsage)
  }

  public static func isWheelElement(usagePage: Int, usage: Int) -> Bool {
    (usagePage == genericDesktopPage && usage == wheelUsage)
      || (usagePage == consumerPage && usage == consumerWheelUsage)
  }

  private static func isPointerOrWheelElement(usagePage: Int, usage: Int) -> Bool {
    isWheelElement(usagePage: usagePage, usage: usage)
      || (usagePage == genericDesktopPage && (usage == xUsage || usage == yUsage))
  }
}
