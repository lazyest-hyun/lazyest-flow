import ApplicationServices

public enum ScrollSourceKind {
  case mouse
  case trackpad
  case unknown
}

public enum WheelScrollPolicy {
  public static func shouldReverse(_ event: CGEvent, source: ScrollSourceKind = .unknown) -> Bool {
    guard event.type == .scrollWheel, !event.flags.contains(.maskControl) else { return false }
    // HID wheel reports and CGEvents arrive separately. A recently used mouse
    // must never make the following trackpad gesture look like a mouse wheel.
    guard event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
      event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0
    else { return false }
    switch source {
    case .mouse:
      return true
    case .trackpad:
      return false
    case .unknown:
      // Unidentified continuous input can be a trackpad or touch surface.
      // High-resolution physical wheels remain supported when HID identifies them.
      return event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
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
