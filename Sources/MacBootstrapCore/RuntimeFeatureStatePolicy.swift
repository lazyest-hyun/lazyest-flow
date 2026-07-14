public enum RuntimeFeatureState: Equatable {
  case off
  case active
  case unavailable
}

public enum RuntimeFeatureStatePolicy {
  public static func resolve(requested: Bool, active: Bool) -> RuntimeFeatureState {
    switch (requested, active) {
    case (false, false):
      return .off
    case (true, true):
      return .active
    case (false, true), (true, false):
      return .unavailable
    }
  }
}
