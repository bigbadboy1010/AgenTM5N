import Foundation
import OSLog

public enum AppLogger {
  public static let app = Logger(
    subsystem: AppPaths.bundleIdentifier,
    category: "application"
  )

  public static let network = Logger(
    subsystem: AppPaths.bundleIdentifier,
    category: "network"
  )

  public static let security = Logger(
    subsystem: AppPaths.bundleIdentifier,
    category: "security"
  )

  public static let terminal = Logger(
    subsystem: AppPaths.bundleIdentifier,
    category: "terminal"
  )
}
