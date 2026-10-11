import Foundation

/// Startup login is distinct from launching Flow after login and unlocking a sleeping Mac.
/// No public API confirms all account and management restrictions, so FileVault off
/// must never be presented as proof that automatic login is available or enabled.
public enum AutomaticLoginPolicy {
  public enum FileVaultState: Equatable {
    case on
    case off
    case unknown
  }

  public enum Eligibility: Equatable {
    case blockedByFileVault
    case needsSystemSettingsReview
    case unknown
  }

  public static func fileVaultState(output: String, exitCode: Int32, timedOut: Bool = false)
    -> FileVaultState
  {
    guard !timedOut else { return .unknown }
    switch (output.trimmingCharacters(in: .whitespacesAndNewlines), exitCode) {
    case ("true", 0): return .on
    case ("false", 1): return .off
    default: return .unknown
    }
  }

  public static func eligibility(fileVault: FileVaultState) -> Eligibility {
    switch fileVault {
    case .on: return .blockedByFileVault
    case .off: return .needsSystemSettingsReview
    case .unknown: return .unknown
    }
  }
}
