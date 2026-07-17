import ApplicationServices
import Foundation

final class EventTapHost {
  typealias Handler = (CGEventType, CGEvent) -> Unmanaged<CGEvent>?

  private let eventMask: CGEventMask
  private let handler: Handler
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  init(eventMask: CGEventMask, handler: @escaping Handler) {
    self.eventMask = eventMask
    self.handler = handler
  }

  var isValid: Bool {
    guard let eventTap else { return false }
    return CFMachPortIsValid(eventTap)
  }

  func start() -> Bool {
    stop()
    let callback: CGEventTapCallBack = { _, type, event, context in
      guard let context else { return Unmanaged.passUnretained(event) }
      let host = Unmanaged<EventTapHost>.fromOpaque(context).takeUnretainedValue()
      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        host.enable()
        return Unmanaged.passUnretained(event)
      }
      return host.handler(type, event)
    }
    eventTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: eventMask,
      callback: callback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    )
    guard let eventTap else { return false }
    runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    guard let runLoopSource else {
      self.eventTap = nil
      return false
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    return true
  }

  func stop() {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil
  }

  private func enable() {
    guard let eventTap else { return }
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  deinit {
    stop()
  }
}
