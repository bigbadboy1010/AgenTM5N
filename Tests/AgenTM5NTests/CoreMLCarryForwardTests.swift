import Foundation
import XCTest
@testable import AgenTM5N

final class CoreMLCarryForwardTests: XCTestCase {
  func testRegistryNormalizationMigratesLegacyComputePolicy() throws {
    let legacy = Data(
      """
      {
        "version": 1,
        "activeModelID": null,
        "models": [
          {
            "computeUnits": "CPU + Apple Neural Engine (angefordert)"
          }
        ]
      }
      """.utf8
    )

    let normalized = try CoreMLService.normalizeRegistryComputePolicy(in: legacy)
    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: normalized) as? [String: Any]
    )
    let models = try XCTUnwrap(root["models"] as? [[String: Any]])
    let first = try XCTUnwrap(models.first)
    let policy = try XCTUnwrap(first["computeUnits"] as? String)

    XCTAssertTrue(policy.contains("GPU"))
    XCTAssertTrue(policy.contains("Neural Engine"))
    XCTAssertFalse(policy.contains("angefordert"))
  }

  func testRegistryNormalizationLeavesCurrentPolicyStable() throws {
    let current = Data(
      """
      {
        "version": 1,
        "activeModelID": null,
        "models": [
          {
            "computeUnits": "All available Core ML compute units (CPU + GPU + Neural Engine)"
          }
        ]
      }
      """.utf8
    )

    let normalized = try CoreMLService.normalizeRegistryComputePolicy(in: current)
    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: normalized) as? [String: Any]
    )
    let models = try XCTUnwrap(root["models"] as? [[String: Any]])
    XCTAssertEqual(models.count, 1)
  }
}