import CryptoKit
import Foundation
import XCTest
@testable import AgenTM5N

final class AgentMeshResourceGuardTests: XCTestCase {
  func testRemoteExecutionFailsClosedBeforeProviderWhenHeavyTurnIsAlreadyActive() async throws {
    let service = AgentMeshExecutionService()
    var configuration = AppConfiguration.default
    configuration.providerKind = .ollamaLocal
    configuration.baseURL = "http://127.0.0.1:1"
    configuration.model = "mesh-resource-guard-test"
    await service.configure(configuration)

    let blocker = try await InferenceResourceGovernor.shared.acquire(
      runtime: .appleFoundationModels,
      ownerID: UUID()
    )

    let signing = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    let agreement = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    let peer = AgentMeshPeerRecord(
      id: UUID(),
      name: "Resource Guard Peer",
      kind: .agentM5N,
      endpoint: "http://127.0.0.1:8787",
      signingPublicKey: signing,
      agreementPublicKey: agreement,
      fingerprint: AgentMeshIdentityStore.fingerprint(
        signingPublicKey: signing,
        agreementPublicKey: agreement
      ),
      status: .trusted,
      allowedCapabilities: [.workspace]
    )
    let request = AgentMeshTaskRequest(
      prompt: "This must never reach the provider while the resource guard is busy.",
      requestedCapabilities: [.workspace]
    )

    do {
      _ = try await service.execute(
        request: request,
        peer: peer,
        effectiveCapabilities: [.workspace]
      ) { _, _ in }
      await InferenceResourceGovernor.shared.release(blocker)
      XCTFail("Remote Mesh inference must fail closed before provider execution")
    } catch let error as InferenceResourceGovernorError {
      await InferenceResourceGovernor.shared.release(blocker)
      switch error {
      case .busy(let active, _):
        XCTAssertEqual(active, .appleFoundationModels)
      case .recoveryRequired:
        XCTFail("Fresh blocking lease must report busy, not recovery-required")
      }
    } catch {
      await InferenceResourceGovernor.shared.release(blocker)
      XCTFail("Unexpected error: \(error)")
    }

    let snapshot = await InferenceResourceGovernor.shared.snapshot()
    XCTAssertFalse(snapshot.isBusy)
  }
}
