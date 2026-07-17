import Darwin
import Foundation
import LazyestCore

guard PowerHelperConnectionValidator.runtimeConfigurationIsValid else {
  fputs("Invalid power helper installation or client identity.\n", stderr)
  exit(EX_CONFIG)
}

let delegate = PowerHelperListenerDelegate()
let listener = NSXPCListener(machServiceName: LazyestPowerHelper.label)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
