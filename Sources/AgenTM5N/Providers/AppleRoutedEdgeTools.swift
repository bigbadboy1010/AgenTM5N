import Foundation
import FoundationModels

/// Focused Apple on-device Edge control pack.
///
/// Edge operations deliberately reuse the already hardened SSH/Vault backend
/// instead of introducing a second credential or transport path. The pack is
/// kept at five tools to stay inside the small Foundation Models context budget.
public enum AppleRoutedEdgeTools {
  public static func makeTools(
    bridge: AgentToolExecutionBridge = .shared
  ) -> [any Tool] {
    AppleRoutedSSHTools.makeRunTools(bridge: bridge)
      + AppleRoutedSSHTools.makeBatchTools(bridge: bridge)
      + AppleRoutedSSHTools.makeTailTools(bridge: bridge)
      + AppleRoutedSSHTools.makeUploadTools(bridge: bridge)
      + AppleRoutedSSHTools.makeDownloadTools(bridge: bridge)
  }
}
