import ApplicationServices

public enum ScrollSourceKind {
  case mouse
  case trackpad
  case unknown
}

public enum WheelScrollPolicy {
  public static func shouldReverse(_ event: CGEvent, source: ScrollSourceKind = .unknown) -> Bool {
    guard event.type == .scrollWheel, !event.flags.contains(.maskControl) else { return false }
    switch source {
    case .mouse:
      return true
    case .trackpad:
      return false
    case .unknown:
      let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
      let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
      if scrollPhase != 0 || momentumPhase != 0 {
        return false
      }
      return true
    }
  }

  @discardableResult
  public static func applyVerticalReverse(to event: CGEvent, source: ScrollSourceKind = .unknown)
    -> Bool
  {
    guard shouldReverse(event, source: source) else { return false }
    let fields = [
      CGEventField.scrollWheelEventDeltaAxis1,
      .scrollWheelEventFixedPtDeltaAxis1,
      .scrollWheelEventPointDeltaAxis1,
    ]
    let originalValues = fields.map { event.getIntegerValueField($0) }
    for (field, value) in zip(fields, originalValues) {
      event.setIntegerValueField(field, value: -value)
    }
    return true
  }
}
