import CoreGraphics

public enum DockEdge: String {
  case bottom
  case left
  case right
}

public enum ScreenCorner: String, CaseIterable {
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
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

  public static func allowsHotCorner(
    at point: CGPoint,
    in frame: CGRect,
    edge: DockEdge,
    activeCorners: Set<ScreenCorner>,
    originAtTop: Bool,
    size: CGFloat = 24
  ) -> Bool {
    matchingHotCorner(
      at: point,
      in: frame,
      edge: edge,
      activeCorners: activeCorners,
      originAtTop: originAtTop,
      size: size
    ) != nil
  }

  public static func matchingHotCorner(
    at point: CGPoint,
    in frame: CGRect,
    edge: DockEdge,
    activeCorners: Set<ScreenCorner>,
    originAtTop: Bool,
    size: CGFloat = 24
  ) -> ScreenCorner? {
    let relevantCorners: [ScreenCorner]
    switch edge {
    case .bottom:
      relevantCorners = [.bottomLeft, .bottomRight]
    case .left:
      relevantCorners = [.topLeft, .bottomLeft]
    case .right:
      relevantCorners = [.topRight, .bottomRight]
    }

    return relevantCorners.first { corner in
      activeCorners.contains(corner)
        && hotCornerZone(
          in: frame,
          corner: corner,
          originAtTop: originAtTop,
          size: size
        ).contains(point)
    }
  }

  public static func missionControlArgument(forHotCornerAction action: Int) -> String? {
    switch action {
    case 2:
      return "0"
    case 3:
      return "2"
    case 4:
      return "1"
    default:
      return nil
    }
  }

  private static func hotCornerZone(
    in frame: CGRect,
    corner: ScreenCorner,
    originAtTop: Bool,
    size: CGFloat
  ) -> CGRect {
    let clampedSize = max(1, min(size, min(frame.width, frame.height)))
    let isRight = corner == .topRight || corner == .bottomRight
    let isPhysicalBottom = corner == .bottomLeft || corner == .bottomRight
    let usesMaxY = originAtTop ? isPhysicalBottom : !isPhysicalBottom

    return CGRect(
      x: isRight ? frame.maxX - clampedSize : frame.minX,
      y: usesMaxY ? frame.maxY - clampedSize : frame.minY,
      width: clampedSize,
      height: clampedSize
    )
  }
}
