import SwiftUI

struct AgentMeshView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var mesh = AgentMeshController.shared
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        nodeCard
        enrollmentCard
        peersCard
        delegatedTaskCard
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Agent Mesh")
    .task {
      await mesh.bootstrap(configuration: appState.configuration)
    }
    .onChange(of: appState.configuration) { _, configuration in
      Task { await mesh.updateConfiguration(configuration) }
    }
    .alert("Agent Mesh", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 10) {
        Image(systemName: "point.3.connected.trianglepath.dotted")
          .font(.title2)
          .foregroundStyle(.tint)
        Text("AgenTM5N Agent Mesh · Build 40")
          .font(.title2.bold())
      }
      Text(
        "Federation fuer AgenTM5N ↔ AgenTM5N ↔ AgentNexus. Requests werden mit einer persistenten Ed25519-Maschinenidentitaet signiert; vertrauliche Task-Payloads werden per X25519 + ChaCha20-Poly1305 verschluesselt. Neue Peers bleiben bis zur lokalen Fingerprint-Freigabe gesperrt."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
    }
  }

  private var nodeCard: some View {
    GroupBox("Dieser Node") {
      VStack(alignment: .leading, spacing: 12) {
        if let node = mesh.node {
          Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
            GridRow { Text("Name").foregroundStyle(.secondary); Text(node.name) }
            GridRow { Text("Node ID").foregroundStyle(.secondary); Text(node.nodeID.uuidString).textSelection(.enabled) }
            GridRow { Text("Fingerprint").foregroundStyle(.secondary); Text(node.fingerprint).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
            GridRow { Text("Protocol").foregroundStyle(.secondary); Text(AgentMeshProtocol.name) }
            GridRow { Text("Status").foregroundStyle(.secondary); Text(mesh.statusMessage) }
          }
        }

        Divider()

        HStack {
          TextField("Port", value: $mesh.port, format: .number)
            .frame(width: 100)
          TextField("Advertised endpoint, z.B. http://192.168.1.20:8787", text: $mesh.advertisedEndpoint)
            .textFieldStyle(.roundedBorder)
          if mesh.listenerRunning {
            Button("Stop") { mesh.stop() }
          } else {
            Button("Start") {
              Task {
                do {
                  try await mesh.start(configuration: appState.configuration)
                } catch {
                  errorMessage = error.localizedDescription
                }
              }
            }
            .buttonStyle(.borderedProminent)
          }
        }

        Text(
          "Der Listener wird nur nach explizitem Start oder gespeichertem Auto-Start aktiviert. Das advertised endpoint muss von anderen Nodes erreichbar sein; fuer den Zwei-Mac-Test deshalb die LAN-IP dieses Macs verwenden."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding(8)
    }
  }

  private var enrollmentCard: some View {
    GroupBox("Peer Enrollment") {
      VStack(alignment: .leading, spacing: 10) {
        TextField("Remote endpoint, z.B. http://192.168.1.21:8787", text: $mesh.peerEndpoint)
          .textFieldStyle(.roundedBorder)
        HStack {
          Button("AgenTM5N Peer anfragen") {
            enroll(.agentM5N)
          }
          Button("AgentNexus Adapter anfragen") {
            enroll(.agentNexus)
          }
          Button("Aktualisieren") {
            Task { await mesh.refresh() }
          }
        }
        Text(
          "Enrollment tauscht ausschliesslich oeffentliche Maschinenidentitaeten aus. Ein eingehender oder ausgehender Peer bleibt pending, bis der angezeigte Fingerprint lokal geprueft und freigegeben wurde."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding(8)
    }
  }

  private var peersCard: some View {
    GroupBox("Peers") {
      VStack(alignment: .leading, spacing: 12) {
        if mesh.peers.isEmpty {
          Text("Noch keine Peers registriert.")
            .foregroundStyle(.secondary)
        }
        ForEach(mesh.peers) { peer in
          VStack(alignment: .leading, spacing: 7) {
            HStack {
              VStack(alignment: .leading, spacing: 3) {
                Text(peer.name).font(.headline)
                Text(peer.endpoint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
              }
              Spacer()
              Text(peer.status.rawValue.uppercased())
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
            }

            Text("Fingerprint: \(peer.fingerprint)")
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)

            if !peer.allowedCapabilities.isEmpty {
              Text("Scope: " + peer.allowedCapabilities.map(\.rawValue).sorted().joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
              if peer.status == .pending {
                Button("Trust: Read + lokale Approval") {
                  Task {
                    do { try await mesh.trustReadOnly(peer.id) }
                    catch { errorMessage = error.localizedDescription }
                  }
                }
                Button("Trust: DevOps + lokale Approval") {
                  Task {
                    do { try await mesh.trustDevOps(peer.id) }
                    catch { errorMessage = error.localizedDescription }
                  }
                }
              }
              if peer.status == .trusted {
                Button("Test-Task an diesen Peer") {
                  Task {
                    do { try await mesh.submitTask(to: peer.id) }
                    catch { errorMessage = error.localizedDescription }
                  }
                }
              }
              if peer.status != .revoked {
                Button("Widerrufen", role: .destructive) {
                  Task {
                    do { try await mesh.revoke(peer.id) }
                    catch { errorMessage = error.localizedDescription }
                  }
                }
              }
            }
          }
          .padding(10)
          .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }
      }
      .padding(8)
    }
  }

  private var delegatedTaskCard: some View {
    GroupBox("Delegierter Task") {
      VStack(alignment: .leading, spacing: 10) {
        TextEditor(text: $mesh.taskPrompt)
          .font(.body)
          .frame(minHeight: 90)
          .overlay {
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.primary.opacity(0.12))
          }

        if let snapshot = mesh.remoteTaskSnapshot {
          HStack {
            Text("Task \(snapshot.id.uuidString.prefix(8))")
              .font(.headline)
            Text(snapshot.status.rawValue)
              .foregroundStyle(.secondary)
            Spacer()
          }
          if let result = snapshot.result, !result.isEmpty {
            Text(result)
              .textSelection(.enabled)
              .padding(8)
              .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
          }
          if let error = snapshot.error, !error.isEmpty {
            Text(error).foregroundStyle(.red).textSelection(.enabled)
          }
        }

        if !mesh.remoteTaskEvents.isEmpty {
          Divider()
          ForEach(mesh.remoteTaskEvents.suffix(30)) { event in
            HStack(alignment: .top, spacing: 8) {
              Text("#\(event.id)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
              Text(event.kind.rawValue)
                .font(.caption.bold())
              if !event.message.isEmpty {
                Text(event.message)
                  .font(.caption)
                  .lineLimit(4)
                  .textSelection(.enabled)
              }
            }
          }
        }
      }
      .padding(8)
    }
  }

  private func enroll(_ kind: AgentMeshPeerKind) {
    Task {
      do {
        _ = try await mesh.enrollPeer(kind: kind)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
