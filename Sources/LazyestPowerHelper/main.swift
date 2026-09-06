import Darwin
import Foundation
import LazyestCore

guard geteuid() == 0 else {
  fputs("The power helper must be started by the system service manager.\n", stderr)
  exit(EX_NOPERM)
}

// Restore any owned override before checking a replaced or removed app identity.
let delegate = PowerHelperListenerDelegate()

guard PowerHelperConnectionValidator.runtimeConfigurationIsValid else {
  fputs("Invalid power helper installation or client identity.\n", stderr)
  exit(EX_CONFIG)
}

let listener = NSXPCListener(machServiceName: LazyestPowerHelper.label)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
