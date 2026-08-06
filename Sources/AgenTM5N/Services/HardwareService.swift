import Darwin
import Foundation

public enum HardwareService {
  public static func makeProfile(
    appleFoundationModelStatus: String
  ) -> HardwareProfile {
    HardwareProfile(
      chipName: sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon",
      memoryBytes: ProcessInfo.processInfo.physicalMemory,
      operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
      appleFoundationModelStatus: appleFoundationModelStatus
    )
  }

  private static func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
      return nil
    }

    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
      return nil
    }
    return String(cString: buffer)
  }
}
