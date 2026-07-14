public enum SleepPreventionDecision: Equatable {
  case disabled
  case active
  case waitingForPower
  case lowBattery
  case thermalSafety
}

public enum SleepPreventionPolicy {
  public static let defaultLowBatteryCutoff = 20

  public static func resolve(
    enabled: Bool,
    includeBattery: Bool,
    onACPower: Bool,
    batteryPercent: Int?,
    thermalSafetyRequired: Bool,
    lowBatteryCutoff: Int = defaultLowBatteryCutoff
  ) -> SleepPreventionDecision {
    guard enabled else { return .disabled }
    guard !thermalSafetyRequired else { return .thermalSafety }
    guard onACPower || includeBattery else { return .waitingForPower }
    if !onACPower, let batteryPercent, batteryPercent <= lowBatteryCutoff {
      return .lowBattery
    }
    return .active
  }
}
