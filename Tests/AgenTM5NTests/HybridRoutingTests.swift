import CryptoKit
import Foundation
import XCTest
@testable import AgenTM5N

final class HybridRoutingTests: XCTestCase {
  private let router = HybridInferenceRouter()

  func testManualModeAlwaysKeepsActiveProvider() {
    let decision = router.decide(
      prompt: "Delegiere diese Aufgabe an einen anderen Agenten",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: AgentOperatingLayerConfiguration(localInferenceRuntime: .anemll),
      routingConfiguration: HybridRoutingConfiguration(mode: .manual, allowMesh: true),
      appleFoundationModelsAvailable: true,
      peers: [trustedPeer(capabilities: [.workspace])],
      modelProfiles: [profile(name: "MLX Fast", runtime: .mlx, priority: 900)]
    )

    XCTAssertEqual(decision.kind, .activeProvider)
    XCTAssertNil(decision.peerID)
    XCTAssertNil(decision.profileID)
  }

  func testAdaptiveSelectsHighestPriorityCompatibleLocalProfile() {
    let mlx = profile(name: "MLX Fast", runtime: .mlx, priority: 700)
    let anemll = profile(name: "ANEMLL Preferred", runtime: .anemll, priority: 900)

    let decision = router.decide(
      prompt: "Erkläre kurz, was ein Actor in Swift ist.",
      activeConfiguration: ollamaLocalConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(mode: .adaptive, preferLocal: true),
      appleFoundationModelsAvailable: true,
      peers: [],
      modelProfiles: [mlx, anemll, ModelProfileCatalog.appleBuiltIn]
    )

    XCTAssertEqual(decision.kind, .modelProfile)
    XCTAssertEqual(decision.profileID, anemll.id)
    XCTAssertEqual(decision.profileRuntime, .anemll)
    XCTAssertFalse(decision.isRemote)
  }

  func testEquivalentActiveProfileDoesNotCreateTemporaryRoute() {
    let active = profile(
      name: "Current ANEMLL",
      runtime: .anemll,
      modelIdentifier: "Qwen3",
      baseURL: "anemll://neural-engine",
      priority: 900
    )

    let decision = router.decide(
      prompt: "Erkläre Actor Isolation.",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: AgentOperatingLayerConfiguration(localInferenceRuntime: .anemll),
      routingConfiguration: HybridRoutingConfiguration(mode: .adaptive),
      appleFoundationModelsAvailable: true,
      peers: [],
      modelProfiles: [active, ModelProfileCatalog.appleBuiltIn]
    )

    XCTAssertEqual(decision.kind, .activeProvider)
    XCTAssertEqual(decision.profileID, active.id)
  }

  func testLocalFirstDoesNotReplaceActiveLocalPathWithCloudOnlyProfile() {
    let cloud = profile(
      name: "Cloud High",
      runtime: .ollamaCloud,
      priority: 1_000,
      secretID: UUID()
    )

    let decision = router.decide(
      prompt: "Normale Wissensfrage ohne Cloud-Wunsch",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: AgentOperatingLayerConfiguration(localInferenceRuntime: .anemll),
      routingConfiguration: HybridRoutingConfiguration(mode: .adaptive, preferLocal: true),
      appleFoundationModelsAvailable: true,
      peers: [],
      modelProfiles: [cloud, ModelProfileCatalog.appleBuiltIn]
    )

    XCTAssertEqual(decision.kind, .activeProvider)
  }

  func testExplicitCloudIntentSelectsUsableCloudProfile() {
    let cloud = profile(
      name: "Cloud Reasoner",
      runtime: .ollamaCloud,
      priority: 500,
      secretID: UUID()
    )

    let decision = router.decide(
      prompt: "Beantworte das mit dem Cloud Model.",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: AgentOperatingLayerConfiguration(localInferenceRuntime: .anemll),
      routingConfiguration: HybridRoutingConfiguration(mode: .adaptive, preferLocal: true),
      appleFoundationModelsAvailable: true,
      peers: [],
      modelProfiles: [cloud, ModelProfileCatalog.appleBuiltIn]
    )

    XCTAssertEqual(decision.kind, .modelProfile)
    XCTAssertEqual(decision.profileID, cloud.id)
    XCTAssertEqual(decision.profileRuntime, .ollamaCloud)
    XCTAssertTrue(decision.isRemote)
  }

  func testCloudProfileWithoutVaultReferenceIsNeverAutomaticCandidate() {
    let invalidCloud = profile(
      name: "Cloud Missing Secret",
      runtime: .ollamaCloud,
      priority: 1_000,
      secretID: nil
    )

    let decision = router.decide(
      prompt: "Nutze das Cloud Model.",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: AgentOperatingLayerConfiguration(localInferenceRuntime: .anemll),
      routingConfiguration: HybridRoutingConfiguration(mode: .adaptive),
      appleFoundationModelsAvailable: false,
      peers: [],
      modelProfiles: [invalidCloud]
    )

    XCTAssertEqual(decision.kind, .activeProvider)
    XCTAssertNil(decision.profileID)
  }

  func testImageInputRequiresProfileImageCapability() {
    let textOnly = profile(name: "Text Only", runtime: .anemll, priority: 1_000)
    let vision = profile(
      name: "Vision Local",
      runtime: .ollamaLocal,
      priority: 700,
      capabilities: [.textGeneration, .streaming, .imageInput, .onDevice]
    )

    let decision = router.decide(
      prompt: "Beschreibe dieses Bild.",
      activeConfiguration: localConfiguration(),
      operatingConfiguration: AgentOperatingLayerConfiguration(localInferenceRuntime: .anemll),
      routingConfiguration: HybridRoutingConfiguration(mode: .adaptive),
      appleFoundationModelsAvailable: true,
      peers: [],
      modelProfiles: [textOnly, vision, ModelProfileCatalog.appleBuiltIn],
      hasImageInput: true
    )

    XCTAssertEqual(decision.kind, .modelProfile)
    XCTAssertEqual(decision.profileID, vision.id)
  }

  func testTaskLocalOperatingOverrideChangesRuntimeWithoutPersistingThroughProfileSchema() {
    var override = AgentOperatingLayerConfiguration.default
    override.localInferenceRuntime = .mlxServer
    override.numContext = 32_768

    AgentOperatingLayerExecutionContext.$configurationOverride.withValue(override) {
      let current = AgentOperatingLayerStore.load()
      XCTAssertEqual(current.localInferenceRuntime, .mlxServer)
      XCTAssertEqual(current.numContext, 32_768)
    }
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

  func testPrivacyLockPrefersCompatibleLocalProfileOverHigherPriorityCloudProfile() {
    let cloud = profile(
      name: "Cloud Personal",
      runtime: .ollamaCloud,
      priority: 1_000,
      secretID: UUID(),
      capabilities: [.textGeneration, .streaming, .toolCalling]
    )
    let local = profile(
      name: "Local Personal",
      runtime: .anemll,
      priority: 600,
      capabilities: [.textGeneration, .streaming, .toolCalling, .onDevice]
    )

    let decision = router.decide(
      prompt: "Welche Termine habe ich heute im Kalender?",
      activeConfiguration: cloudConfiguration(),
      operatingConfiguration: .default,
      routingConfiguration: HybridRoutingConfiguration(
        mode: .adaptive,
        preferLocal: false,
        allowAppleOnDevice: true,
        privacyLockEnabled: true
      ),
      appleFoundationModelsAvailable: true,
      peers: [],
      modelProfiles: [cloud, local, ModelProfileCatalog.appleBuiltIn]
    )

    XCTAssertEqual(decision.kind, .modelProfile)
    XCTAssertEqual(decision.profileID, local.id)
    XCTAssertTrue(decision.privacyLocked)
    XCTAssertFalse(decision.isRemote)
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
      peers: [peer],
      modelProfiles: [profile(name: "ANEMLL", runtime: .anemll, priority: 1_000)]
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
    XCTAssertEqual(decision.profileID, ModelProfileCatalog.appleBuiltIn.id)
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
      peers: [],
      modelProfiles: [profile(name: "ANEMLL", runtime: .anemll, priority: 900)]
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

  private func ollamaLocalConfiguration() -> AppConfiguration {
    AppConfiguration(
      providerKind: .ollamaLocal,
      baseURL: "http://localhost:11434",
      model: "qwen3:8b",
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

  private func profile(
    name: String,
    runtime: ModelProfileRuntime,
    modelIdentifier: String? = nil,
    baseURL: String? = nil,
    priority: Int,
    secretID: UUID? = nil,
    capabilities: Set<ModelProfileCapability> = [.textGeneration, .streaming, .toolCalling]
  ) -> ModelProfile {
    ModelProfile(
      name: name,
      runtime: runtime,
      modelIdentifier: modelIdentifier ?? defaultModel(for: runtime),
      baseURL: baseURL,
      apiKeySecretID: secretID,
      contextWindow: 16_384,
      priority: priority,
      enabled: true,
      capabilities: capabilities
    )
  }

  private func defaultModel(for runtime: ModelProfileRuntime) -> String {
    switch runtime {
    case .ollamaLocal: "qwen3:8b"
    case .ollamaCloud: "glm-5.2"
    case .mlx: "mlx-community/Qwen3"
    case .anemll: "Qwen3"
    case .appleFoundationModels: "SystemLanguageModel.default"
    }
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
