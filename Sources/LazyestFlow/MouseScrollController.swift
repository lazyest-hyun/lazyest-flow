import AppKit
import ApplicationServices
import Foundation
import LazyestCore

final class MouseScrollController {
  private let config: Config
  private let preferences = MouseDevicePreferences.shared
  private var eventTapHost: EventTapHost?

  init(config: Config) {
    self.config = config
  }

  func reload() {
    config.reloadBootstrap()
    guard config.mouseScrollReverseEnabled || preferences.hasReversedOverride else {
      stop()
      postStatus(flowText("devices.mouse.status.off"))
      return
    }
    start()
  }

  func stop() {
    eventTapHost?.stop()
    eventTapHost = nil
  }

  private func start() {
    stop()
    guard AXIsProcessTrusted() else {
      postStatus(flowText("devices.mouse.status.needsPermission"))
      return
    }
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    let host = EventTapHost(eventMask: mask) { [weak self] type, event in
      self?.handle(type: type, event: event) ?? Unmanaged.passUnretained(event)
    }
    guard host.start() else {
      postStatus(flowText("devices.mouse.status.failed"))
      return
    }
    eventTapHost = host
    postStatus(flowText("devices.mouse.status.active"))
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
    let context = InputDeviceInventory.shared.recentScrollContext()
    guard context.source != .trackpad else { return Unmanaged.passUnretained(event) }
    let shouldReverse = preferences.shouldReverse(
      deviceID: context.deviceID,
      defaultValue: config.mouseScrollReverseEnabled
    )
    if shouldReverse {
      WheelScrollPolicy.applyVerticalReverse(to: event, source: context.source)
    }
    return Unmanaged.passUnretained(event)
  }

  private func postStatus(_ status: String) {
    NotificationCenter.default.post(name: mouseScrollStatusNotification, object: status)
  }

  deinit {
    stop()
  }
}
