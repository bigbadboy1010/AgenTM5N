import CryptoKit
import Foundation
import XCTest
@testable import AgenTM5N

final class AgentMeshTests: XCTestCase {
  func testFingerprintIsDeterministicAndKeyBound() {
    let signingA = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    let agreementA = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    let signingB = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation

    let first = AgentMeshIdentityStore.fingerprint(
      signingPublicKey: signingA,
      agreementPublicKey: agreementA
    )
    let second = AgentMeshIdentityStore.fingerprint(
      signingPublicKey: signingA,
      agreementPublicKey: agreementA
    )
    let changed = AgentMeshIdentityStore.fingerprint(
      signingPublicKey: signingB,
      agreementPublicKey: agreementA
    )

    XCTAssertEqual(first, second)
    XCTAssertNotEqual(first, changed)
    XCTAssertTrue(first.contains("-"))
  }

  func testPendingPeerRequiresExplicitTrustAndCanBeRevoked() async throws {
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("peers.json")
    defer { try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent()) }

    let store = AgentMeshPeerStore(fileURL: temporary)
    let descriptor = makeDescriptor(name: "Peer A")
    let pending = try await store.registerPending(
      descriptor: descriptor,
      endpoint: "http://127.0.0.1:8787"
    )

    XCTAssertEqual(pending.status, .pending)
    XCTAssertNil(try await store.trustedPeer(id: descriptor.nodeID))

    let trusted = try await store.trust(
      id: descriptor.nodeID,
      allowedCapabilities: [.workspace, .git]
    )
    XCTAssertEqual(trusted.status, .trusted)
    XCTAssertEqual(trusted.allowedCapabilities, [.workspace, .git])
    XCTAssertNotNil(try await store.trustedPeer(id: descriptor.nodeID))

    let revoked = try await store.revoke(id: descriptor.nodeID)
    XCTAssertEqual(revoked.status, .revoked)
    XCTAssertTrue(revoked.allowedCapabilities.isEmpty)
    XCTAssertNil(try await store.trustedPeer(id: descriptor.nodeID))
  }

  func testTrustedPeerKeyRotationFailsClosed() async throws {
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("peers.json")
    defer { try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent()) }

    let store = AgentMeshPeerStore(fileURL: temporary)
    let first = makeDescriptor(name: "Peer A")
    _ = try await store.registerPending(
      descriptor: first,
      endpoint: "http://127.0.0.1:8787"
    )
    _ = try await store.trust(id: first.nodeID, allowedCapabilities: [.workspace])

    let replacementSigning = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    let changed = AgentMeshNodeDescriptor(
      nodeID: first.nodeID,
      name: first.name,
      kind: first.kind,
      appVersion: first.appVersion,
      appBuild: first.appBuild,
      signingPublicKey: replacementSigning,
      agreementPublicKey: first.agreementPublicKey,
      fingerprint: AgentMeshIdentityStore.fingerprint(
        signingPublicKey: replacementSigning,
        agreementPublicKey: first.agreementPublicKey
      ),
      capabilities: first.capabilities,
      features: first.features
    )

    do {
      _ = try await store.registerPending(
        descriptor: changed,
        endpoint: "http://127.0.0.1:8787"
      )
      XCTFail("Trusted peer key rotation must fail closed")
    } catch let error as AgentMeshSecurityError {
      XCTAssertEqual(error, .invalidKeyMaterial)
    }
  }

  func testReplayProtectorRejectsSameNonceTwice() async throws {
    let protector = AgentMeshReplayProtector()
    let nodeID = UUID()
    let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)

    try await protector.validate(
      nodeID: nodeID,
      nonce: "nonce-1",
      timestampMilliseconds: timestamp
    )

    do {
      try await protector.validate(
        nodeID: nodeID,
        nonce: "nonce-1",
        timestampMilliseconds: timestamp
      )
      XCTFail("Replay must be rejected")
    } catch let error as AgentMeshSecurityError {
      XCTAssertEqual(error, .replayDetected)
    }
  }

  func testReplayProtectorRejectsExpiredRequest() async {
    let protector = AgentMeshReplayProtector()
    let expired = Date().addingTimeInterval(
      -(AgentMeshProtocol.maximumClockSkewSeconds + 60)
    )
    let timestamp = Int64(expired.timeIntervalSince1970 * 1_000)

    do {
      try await protector.validate(
        nodeID: UUID(),
        nonce: "expired",
        timestampMilliseconds: timestamp
      )
      XCTFail("Expired request must be rejected")
    } catch let error as AgentMeshSecurityError {
      XCTAssertEqual(error, .expiredRequest)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testTaskCoordinatorIntersectsCapabilitiesAndIsIdempotent() async throws {
    let coordinator = AgentMeshTaskCoordinator()
    let peer = makeTrustedPeer(
      allowedCapabilities: [.workspace, .git, .terminal]
    )
    await coordinator.installExecutor { request, _, capabilities, sink in
      await sink(.delta, "executed")
      return "OK \(request.id.uuidString) \(capabilities.count)"
    }

    let request = AgentMeshTaskRequest(
      prompt: "Inspect repository",
      requestedCapabilities: [.workspace, .macPersonal]
    )
    let first = try await coordinator.submit(request, from: peer)
    XCTAssertEqual(first.effectiveCapabilities, [.workspace])

    let duplicate = try await coordinator.submit(request, from: peer)
    XCTAssertEqual(duplicate.id, first.id)
    XCTAssertEqual(duplicate.peerID, first.peerID)

    let terminal = try await waitForTerminal(
      coordinator: coordinator,
      taskID: request.id,
      peerID: peer.id
    )
    XCTAssertEqual(terminal.status, .completed)
    XCTAssertTrue(terminal.result?.contains("OK") == true)

    let eventBatch = try await coordinator.eventBatch(
      taskID: request.id,
      peerID: peer.id,
      afterEventID: 0
    )
    XCTAssertTrue(eventBatch.terminal)
    XCTAssertEqual(
      eventBatch.events.filter { $0.kind == .accepted }.count,
      1,
      "Idempotent retry must not create a second accepted event"
    )
  }

  func testTaskCoordinatorRejectsRevokedPeer() async {
    let coordinator = AgentMeshTaskCoordinator()
    await coordinator.installExecutor { _, _, _, _ in "never" }
    var peer = makeTrustedPeer(allowedCapabilities: [.workspace])
    peer.status = .revoked

    do {
      _ = try await coordinator.submit(
        AgentMeshTaskRequest(prompt: "read"),
        from: peer
      )
      XCTFail("Revoked peer must be rejected")
    } catch let error as AgentMeshSecurityError {
      XCTAssertEqual(error, .peerNotTrusted)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testPeerEndpointRejectsNonHTTPTransport() async {
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("peers.json")
    defer { try? FileManager.default.removeItem(at: temporary.deletingLastPathComponent()) }

    let store = AgentMeshPeerStore(fileURL: temporary)
    do {
      _ = try await store.registerPending(
        descriptor: makeDescriptor(name: "Peer"),
        endpoint: "file:///tmp/mesh"
      )
      XCTFail("Non HTTP(S) endpoint must be rejected")
    } catch {
      XCTAssertTrue(error is URLError)
    }
  }

  private func makeDescriptor(name: String) -> AgentMeshNodeDescriptor {
    let signing = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    let agreement = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    return AgentMeshNodeDescriptor(
      nodeID: UUID(),
      name: name,
      appVersion: "1.4.0",
      appBuild: "40",
      signingPublicKey: signing,
      agreementPublicKey: agreement,
      fingerprint: AgentMeshIdentityStore.fingerprint(
        signingPublicKey: signing,
        agreementPublicKey: agreement
      ),
      capabilities: [.workspace, .git],
      features: ["test"]
    )
  }

  private func makeTrustedPeer(
    allowedCapabilities: Set<AgentToolCapability>
  ) -> AgentMeshPeerRecord {
    let descriptor = makeDescriptor(name: "Trusted Peer")
    return AgentMeshPeerRecord(
      id: descriptor.nodeID,
      name: descriptor.name,
      kind: .agentM5N,
      endpoint: "http://127.0.0.1:8787",
      signingPublicKey: descriptor.signingPublicKey,
      agreementPublicKey: descriptor.agreementPublicKey,
      fingerprint: descriptor.fingerprint,
      status: .trusted,
      allowedCapabilities: allowedCapabilities
    )
  }

  private func waitForTerminal(
    coordinator: AgentMeshTaskCoordinator,
    taskID: UUID,
    peerID: UUID
  ) async throws -> AgentMeshTaskSnapshot {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while clock.now < deadline {
      let snapshot = try await coordinator.snapshot(taskID: taskID, peerID: peerID)
      if [.completed, .failed, .cancelled].contains(snapshot.status) {
        return snapshot
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    XCTFail("Task did not reach terminal state")
    return try await coordinator.snapshot(taskID: taskID, peerID: peerID)
  }
}
