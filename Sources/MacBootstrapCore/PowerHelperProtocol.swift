import Foundation

public enum MacBootstrapPowerHelper {
  public static let label = "com.estaid.mac-bootstrap-agent.power-helper"
  public static let agentBundleIdentifier = "com.estaid.mac-bootstrap-agent"
  public static let plistName = "\(label).plist"
  public static let executableName = "MacBootstrapPowerHelper"
  public static let protocolVersion = "1"
  public static let watchdogTimeout: TimeInterval = 90
  public static let installedAppPath = "/Applications/MacBootstrapAgent.app"
  public static let installedAgentExecutablePath =
    "\(installedAppPath)/Contents/MacOS/MacBootstrapAgent"
  public static let embeddedHelperPath =
    "\(installedAppPath)/Contents/MacOS/\(executableName)"
  public static let installedExecutablePath =
    "/Library/PrivilegedHelperTools/\(label)"
  public static let installedPlistPath = "/Library/LaunchDaemons/\(label).plist"
  public static let ownedSleepMarkerPath =
    "/var/db/\(label).owns-sleep-disabled"
  public static let clientAppPathEnvironment = "MAC_BOOTSTRAP_CLIENT_APP_PATH"
  public static let clientCDHashEnvironment = "MAC_BOOTSTRAP_CLIENT_CDHASH"
  public static let clientUserIDEnvironment = "MAC_BOOTSTRAP_CLIENT_UID"
}

@objc public protocol MacBootstrapPowerHelperProtocol {
  func setSleepDisabled(
    _ enabled: Bool,
    withReply reply: @escaping (Bool, String?) -> Void
  )
  func getSleepDisabled(withReply reply: @escaping (Bool) -> Void)
  func heartbeat(withReply reply: @escaping (Bool) -> Void)
  func version(withReply reply: @escaping (String) -> Void)
}
