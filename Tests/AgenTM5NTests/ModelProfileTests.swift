import Foundation
import XCTest
@testable import AgenTM5N

final class ModelProfileTests: XCTestCase {
  func testCurrentANEMLLConfigurationImportsAsLocalProfile() {
    var operating = AgentOperatingLayerConfiguration.default
    operating.localInferenceRuntime = .anemll
    operating.numContext = 512

    var app = AppConfiguration.default
    app.providerKind = .ollamaLocal
    app.baseURL = LocalInferenceRuntime.anemll.defaultBaseURL
    app.model = "Qwen3-0.6B-ANE"
    app.agentEnabled = true

    let profile = ModelProfile.fromCurrentConfiguration(app: app, operating: operating)

    XCTAssertEqual(profile.runtime, .anemll)
    XCTAssertEqual(profile.contextWindow, 512)
    XCTAssertTrue(profile.runtime.isLocal)
    XCTAssertTrue(profile.capabilities.contains(.toolCalling))
    XCTAssertTrue(profile.capabilities.contains(.neuralEngineOptimized))
    XCTAssertNil(profile.apiKeySecretID)
  }

  func testCloudProfileStoresOnlySecretReferenceNotSecretValue() throws {
    let secretID = UUID()
    let profile = ModelProfile(
      name: "Cloud",
      runtime: .ollamaCloud,
      modelIdentifier: "qwen3:cloud",
      apiKeySecretID: secretID,
      contextWindow: 32_768
    )

    let data = try JSONEncoder().encode(profile)
    let json = String(decoding: data, as: UTF8.self)

    XCTAssertTrue(json.contains(secretID.uuidString))
    XCTAssertFalse(json.localizedCaseInsensitiveContains("apiKeyValue"))
    XCTAssertFalse(json.localizedCaseInsensitiveContains("password"))
    XCTAssertFalse(json.localizedCaseInsensitiveContains("bearer"))
  }

  func testLocalProfileDropsCloudSecretReference() {
    let profile = ModelProfile(
      name: "Local",
      runtime: .mlx,
      modelIdentifier: "mlx-model",
      apiKeySecretID: UUID(),
      contextWindow: 8_192
    )

    XCTAssertNil(profile.apiKeySecretID)
  }

  func testActivationPlanMapsMLXWithoutChangingSecuritySettings() {
    let profile = ModelProfile(
      name: "MLX",
      runtime: .mlx,
      modelIdentifier: "mlx-community/test",
      baseURL: "http://127.0.0.1:8080",
      contextWindow: 16_384
    )

    let plan = profile.activationPlan

    XCTAssertEqual(plan.providerKind, .ollamaLocal)
    XCTAssertEqual(plan.localInferenceRuntime, .mlxServer)
    XCTAssertEqual(plan.baseURL, "http://127.0.0.1:8080")
    XCTAssertEqual(plan.model, "mlx-community/test")
    XCTAssertEqual(plan.contextWindow, 16_384)
  }

  func testLocalFirstCandidateOrderingIsDeterministic() {
    let cloud = ModelProfile(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
      name: "A Cloud",
      runtime: .ollamaCloud,
      modelIdentifier: "cloud",
      priority: 1000
    )
    let localLow = ModelProfile(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
      name: "Local Low",
      runtime: .ollamaLocal,
      modelIdentifier: "local-low",
      priority: 20
    )
    let localHigh = ModelProfile(
      id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
      name: "Local High",
      runtime: .anemll,
      modelIdentifier: "local-high",
      priority: 80
    )

    let result = ModelProfileCatalog.routingCandidates(
      from: [cloud, localLow, localHigh],
      preferLocal: true
    )

    XCTAssertEqual(result.map(\.id), [localHigh.id, localLow.id, cloud.id])
  }

  func testDisabledProfilesAreExcludedFromRoutingCandidates() {
    let disabled = ModelProfile(
      name: "Disabled",
      runtime: .ollamaLocal,
      modelIdentifier: "disabled",
      priority: 1000,
      enabled: false
    )
    let enabled = ModelProfile(
      name: "Enabled",
      runtime: .ollamaLocal,
      modelIdentifier: "enabled",
      priority: 10,
      enabled: true
    )

    let result = ModelProfileCatalog.routingCandidates(
      from: [disabled, enabled],
      preferLocal: true
    )

    XCTAssertEqual(result.map(\.id), [enabled.id])
  }

  func testStorePersistsActiveProfileAndRemovalClearsIt() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-model-profile-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("profiles.json")
    let store = ModelProfileStore(fileURL: url)
    let profile = ModelProfile(
      name: "Persisted",
      runtime: .anemll,
      modelIdentifier: "qwen",
      contextWindow: 512
    )

    _ = try await store.upsert(profile)
    try await store.setActive(id: profile.id)
    let activeBefore = try await store.activeProfile()
    XCTAssertEqual(activeBefore?.id, profile.id)

    try await store.remove(id: profile.id)
    let activeAfter = try await store.activeProfile()
    XCTAssertNil(activeAfter)
  }

  func testAppleBuiltInCannotBeRemoved() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("agentm5n-model-profile-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = ModelProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
    _ = try await store.load()
    try await store.remove(id: ModelProfileCatalog.appleBuiltIn.id)
    let profiles = try await store.all()

    XCTAssertTrue(profiles.contains(where: { $0.id == ModelProfileCatalog.appleBuiltIn.id }))
  }
}
