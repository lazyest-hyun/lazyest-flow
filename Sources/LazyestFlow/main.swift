import Darwin

if CommandLine.arguments.contains("--register-power-helper") {
  exit(PowerHelperMaintenance.register())
}

if CommandLine.arguments.contains("--install-power-helper-as-root") {
  exit(PowerHelperMaintenance.installAsRoot())
}

if CommandLine.arguments.contains("--remove-power-helper-as-root") {
  exit(PowerHelperMaintenance.removeAsRoot())
}

if CommandLine.arguments.contains("--unregister-power-helper") {
  exit(PowerHelperMaintenance.uninstall())
}

if CommandLine.arguments.contains("--disable-power-helper") {
  exit(PowerHelperMaintenance.disable())
}

if CommandLine.arguments.contains("--power-helper-is-registered") {
  exit(PowerHelperMaintenance.isRegistered())
}

if CommandLine.arguments.contains("--enable-login-launch") {
  exit(LoginLaunchMaintenance.setEnabled(true))
}

if CommandLine.arguments.contains("--refresh-login-launch") {
  exit(LoginLaunchMaintenance.setEnabled(true, refreshRegistration: true))
}

if CommandLine.arguments.contains("--disable-login-launch") {
  exit(LoginLaunchMaintenance.setEnabled(false))
}

if CommandLine.arguments.contains("--login-launch-is-enabled") {
  exit(LoginLaunchMaintenance.isEnabled())
}

if CommandLine.arguments.contains("--login-launch-status") {
  print(LoginLaunchMaintenance.statusText())
  exit(0)
}

let supportedRuntimeArguments: Set<String> = ["--login-launch"]
if let unsupported = CommandLine.arguments.dropFirst().first(where: {
  $0.hasPrefix("--") && !supportedRuntimeArguments.contains($0)
}) {
  fputs("Unknown option: \(unsupported)\n", stderr)
  exit(2)
}

let hotkeyPath = applicationSupportPath("hotkeys.conf")
let bootstrapPath = applicationSupportPath("bootstrap.conf")
let config = Config(hotkeyPath: hotkeyPath, bootstrapPath: bootstrapPath)
let launchedAtLogin = CommandLine.arguments.contains("--login-launch")
Flow(config: config, launchedAtLogin: launchedAtLogin).run()
