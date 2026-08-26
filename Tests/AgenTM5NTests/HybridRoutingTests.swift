import CryptoKit
import Foundation
import XCTest
@testable import AgenTM5N

final class HybridRoutingTests: XCTestCase {
  private let router = HybridInferenceRouter()

  func testRouteDiagnosticLabelIncludesModeKindAndTarget() {
    let decision = HybridRouteDecision(
      kind: .activeProvider,
      targetName: "Ollama Cloud · gpt-oss:120b",
      reason: "Test",
      confidence: 1
    )

    XCTAssertEqual(
      decision.diagnosticLabel(mode: .adaptive),
      "Adaptive · activeProvider · Ollama Cloud · gpt-oss:120b"
    )
  }

  func testManualModeAlwaysKeepsActiveProvider() {
    let decision = router.decide(
      prompt: "Delegiere diese Aufgabe an einen anderen Agenten",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: AgentOperatingLayerConfiguration(localInferenceRuntime: .anemll),
      routingConfiguration: HybridRoutingConfiguration(mode: .manual, allowMesh: true),
      appleFoundationModelsAvailable: true,
      peers: [trustedPeer(capabilities: [.workspace])]
    )

    XCTAssertEqual(decision.kind, .activeProvider)
    XCTAssertNil(decision.peerID)
  }

  func testAdaptiveOrdinaryCloudChatKeepsSelectedCloudProvider() {
    let decision = router.decide(
      prompt: "so wir sind wieder da",
      activeConfiguration: cloudConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        preferLocal: true,
        allowAppleOnDevice: true,
        privacyLockEnabled: true
      ),
      appleFoundationModelsAvailable: true,
      peers: []
    )

    XCTAssertEqual(decision.kind, .activeProvider)
    XCTAssertEqual(decision.targetName, "Ollama Cloud · glm-5.2")
    XCTAssertFalse(decision.privacyLocked)
  }

  func testAdaptiveOrdinaryCloudAnalysisKeepsSelectedCloudProvider() {
    let decision = router.decide(
      prompt: "Analysiere die Vor- und Nachteile dieser Architektur.",
      activeConfiguration: cloudConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        preferLocal: true,
        allowAppleOnDevice: true,
        privacyLockEnabled: true
      ),
      appleFoundationModelsAvailable: true,
      peers: []
    )

    XCTAssertEqual(decision.kind, .activeProvider)
    XCTAssertEqual(decision.targetName, "Ollama Cloud · glm-5.2")
  }

  func testPrivacyLockRoutesPersonalCloudPromptToAppleWhenAvailable() {
    let decision = router.decide(
      prompt: "Welche Termine habe ich heute im Kalender?",
      activeConfiguration: cloudConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        preferLocal: true,
        allowAppleOnDevice: true,
        privacyLockEnabled: true
      ),
      appleFoundationModelsAvailable: true,
      peers: []
    )

    XCTAssertEqual(decision.kind, .appleOnDevice)
    XCTAssertTrue(decision.privacyLocked)
    XCTAssertTrue(decision.requiredCapabilities.contains(.macPersonal))
  }

  func testPrivacyLockFailsClosedWhenCloudIsActiveAndNoLocalAlternativeExists() {
    let decision = router.decide(
      prompt: "Lies meine letzten E-Mails",
      activeConfiguration: cloudConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        allowAppleOnDevice: true,
        privacyLockEnabled: true
      ),
      appleFoundationModelsAvailable: false,
      peers: [trustedPeer(capabilities: [.macPersonal])]
    )

    XCTAssertEqual(decision.kind, .blocked)
    XCTAssertTrue(decision.privacyLocked)
    XCTAssertNil(decision.peerID)
  }

  func testExplicitMeshIntentSelectsTrustedCapablePeer() {
    let peer = trustedPeer(
      name: "Mac Studio",
      capabilities: [.workspace, .git, .system]
    )
    let decision = router.decide(
      prompt: "Delegiere an einen Peer auf einem anderen Mac und lies die Datei README.md",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        allowMesh: true,
        requireExplicitMeshIntent: true
      ),
      appleFoundationModelsAvailable: true,
      peers: [peer]
    )

    XCTAssertEqual(decision.kind, .meshPeer)
    XCTAssertEqual(decision.peerID, peer.id)
    XCTAssertTrue(decision.isRemote)
    XCTAssertTrue(decision.requiredCapabilities.contains(.workspace))
  }

  func testMeshDisabledNeverDelegatesEvenWithExplicitIntent() {
    let decision = router.decide(
      prompt: "Delegiere an einen Peer auf einem anderen Mac und lies README.md",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        allowMesh: false,
        requireExplicitMeshIntent: true
      ),
      appleFoundationModelsAvailable: true,
      peers: [trustedPeer(capabilities: [.workspace])]
    )

    XCTAssertEqual(decision.kind, .activeProvider)
  }

  func testMeshRequiresExplicitIntentByDefault() {
    let decision = router.decide(
      prompt: "Lies die Datei README.md",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        allowMesh: true,
        requireExplicitMeshIntent: true
      ),
      appleFoundationModelsAvailable: true,
      peers: [trustedPeer(capabilities: [.workspace])]
    )

    XCTAssertEqual(decision.kind, .activeProvider)
  }

  func testUnsupportedRemoteCapabilityFailsBackToActiveProvider() {
    let decision = router.decide(
      prompt: "Delegiere an einen Peer auf einem anderen Mac und verbinde dich per SSH zum Server",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        allowMesh: true,
        requireExplicitMeshIntent: true
      ),
      appleFoundationModelsAvailable: true,
      peers: [trustedPeer(capabilities: [.workspace, .system, .ssh])]
    )

    XCTAssertEqual(decision.kind, .activeProvider)
    XCTAssertTrue(decision.requiredCapabilities.contains(.ssh))
  }

  func testExplicitAppleIntentUsesAppleOnDevice() {
    let decision = router.decide(
      prompt: "Beantworte das ausdrücklich mit Apple Foundation Models on-device",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        preferLocal: true,
        allowAppleOnDevice: true
      ),
      appleFoundationModelsAvailable: true,
      peers: []
    )

    XCTAssertEqual(decision.kind, .appleOnDevice)
  }

  func testMostRecentlySeenCompatiblePeerWinsDeterministically() {
    let old = trustedPeer(
      name: "Old Peer",
      capabilities: [.workspace],
      lastSeenAt: Date(timeIntervalSince1970: 100)
    )
    let recent = trustedPeer(
      name: "Recent Peer",
      capabilities: [.workspace],
      lastSeenAt: Date(timeIntervalSince1970: 200)
    )

    let decision = router.decide(
      prompt: "Auf einem anderen Mac: lies die Datei README.md",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        allowMesh: true,
        requireExplicitMeshIntent: true
      ),
      appleFoundationModelsAvailable: false,
      peers: [old, recent]
    )

    XCTAssertEqual(decision.peerID, recent.id)
  }

  func testSavedDecisionMetadataDoesNotContainPromptContents() throws {
    let secretMarker = "DO-NOT-PERSIST-THIS-PROMPT"
    let decision = router.decide(
      prompt: "\(secretMarker) lies README.md",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(mode: .adaptive),
      appleFoundationModelsAvailable: false,
      peers: []
    )

    let data = try JSONEncoder().encode(decision)
    let encoded = String(decoding: data, as: UTF8.self)
    XCTAssertFalse(encoded.contains(secretMarker))
  }

  private func localConfiguration() -> AppConfiguration {
    AppConfiguration(
      providerKind: .ollamaLocal,
      baseURL: "anemll://neural-engine",
      model: "Qwen3",
      apiKeySecretID: nil,
      systemPrompt: "",
      thinkingEnabled: false
    )
  }

  private func cloudConfiguration() -> AppConfiguration {
    AppConfiguration(
      providerKind: .ollamaCloud,
      baseURL: "https://ollama.com",
      model: "glm-5.2",
      apiKeySecretID: nil,
      systemPrompt: "",
      thinkingEnabled: false
    )
  }

  private func trustedPeer(
    name: String = "Peer",
    capabilities: Set<AgentToolCapability>,
    lastSeenAt: Date? = nil
  ) -> AgentMeshPeerRecord {
    let signing = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    let agreement = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    return AgentMeshPeerRecord(
      id: UUID(),
      name: name,
      kind: .agentM5N,
      endpoint: "http://127.0.0.1:8787",
      signingPublicKey: signing,
      agreementPublicKey: agreement,
      fingerprint: AgentMeshIdentityStore.fingerprint(
        signingPublicKey: signing,
        agreementPublicKey: agreement
      ),
      status: .trusted,
      allowedCapabilities: capabilities,
      lastSeenAt: lastSeenAt
    )
  }
}
