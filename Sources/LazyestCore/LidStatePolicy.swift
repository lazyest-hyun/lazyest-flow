public enum LidStatePolicy {
  /// IOPM encodes the physical lid state in bit zero of the clamshell message argument.
  public static func isClosed(clamshellMessageArgument: UInt) -> Bool {
    clamshellMessageArgument & 1 != 0
  }
}
