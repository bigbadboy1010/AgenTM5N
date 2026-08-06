import Foundation

public enum ShellEscaping {
  public static func singleQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }
}
