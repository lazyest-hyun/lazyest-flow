import CoreGraphics

public enum DockEdge: String {
  case bottom
  case left
  case right
}

public enum DockEdgeTriggerPolicy {
  public static func triggerZone(
    in frame: CGRect,
    edge: DockEdge,
    thickness: CGFloat = 10
  ) -> CGRect {
    let clampedThickness = max(1, thickness)
    switch edge {
    case .left:
      return CGRect(
        x: frame.minX,
        y: frame.minY,
        width: clampedThickness,
        height: frame.height
      )
    case .right:
      return CGRect(
        x: frame.maxX - clampedThickness,
        y: frame.minY,
        width: clampedThickness,
        height: frame.height
      )
    case .bottom:
      return CGRect(
        x: frame.minX,
        y: frame.maxY - clampedThickness,
        width: frame.width,
        height: clampedThickness
      )
    }
  }

  public static func approachPoint(
    in frame: CGRect,
    edge: DockEdge,
    offset: CGFloat = 50
  ) -> CGPoint {
    let availableDistance = edge == .bottom ? frame.height : frame.width
    let clampedOffset = min(max(1, offset), max(1, availableDistance / 2))
    switch edge {
    case .left:
      return CGPoint(x: frame.minX + clampedOffset, y: frame.midY)
    case .right:
      return CGPoint(x: frame.maxX - clampedOffset, y: frame.midY)
    case .bottom:
      return CGPoint(x: frame.midX, y: frame.maxY - clampedOffset)
    }
  }

  public static func triggerPoint(
    in frame: CGRect,
    edge: DockEdge,
    inset: CGFloat = 1
  ) -> CGPoint {
    let clampedInset = max(1, inset)
    switch edge {
    case .left:
      return CGPoint(x: frame.minX + clampedInset, y: frame.midY)
    case .right:
      return CGPoint(x: frame.maxX - clampedInset, y: frame.midY)
    case .bottom:
      return CGPoint(x: frame.midX, y: frame.maxY - clampedInset)
    }
  }

  public static func pressurePoint(
    in frame: CGRect,
    edge: DockEdge,
    overshoot: CGFloat = 20
  ) -> CGPoint {
    let clampedOvershoot = max(1, overshoot)
    switch edge {
    case .left:
      return CGPoint(x: frame.minX - clampedOvershoot, y: frame.midY)
    case .right:
      return CGPoint(x: frame.maxX + clampedOvershoot, y: frame.midY)
    case .bottom:
      return CGPoint(x: frame.midX, y: frame.maxY + clampedOvershoot)
    }
  }
}
