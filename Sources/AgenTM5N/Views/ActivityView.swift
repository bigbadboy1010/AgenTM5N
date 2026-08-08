import SwiftUI

struct ActivityView: View {
  @ObservedObject private var telemetry = ToolTelemetryStore.shared

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        summary
        Divider()
        if telemetry.entries.isEmpty {
          ContentUnavailableView(
            L10n.text(de: "Noch keine Werkzeugaktivität", en: "No Tool Activity Yet", fr: "Aucune activité d’outil"),
            systemImage: "waveform.path.ecg",
            description: Text(
              L10n.text(
                de: "Ausgeführte AgenTM5N-Werkzeuge erscheinen hier ohne Secret-Werte oder Tool-Argumente.",
                en: "Executed AgenTM5N tools appear here without secret values or tool arguments.",
                fr: "Les outils AgenTM5N exécutés apparaissent ici sans valeurs secrètes ni arguments d’outil."
              )
            )
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(telemetry.entries) { entry in
            VStack(alignment: .leading, spacing: 7) {
              HStack {
                Label(entry.toolName, systemImage: entry.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                  .font(.system(.body, design: .monospaced))
                Spacer()
                Text(entry.startedAt, style: .time)
                  .foregroundStyle(.secondary)
              }
              HStack(spacing: 12) {
                Text(entry.provider)
                Text(entry.capability)
                Text(entry.risk.displayName)
                Text(entry.durationMilliseconds.formatted(.number.precision(.fractionLength(1))) + " ms")
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.outputBytes), countStyle: .file))
                if entry.cacheHit {
                  Label("Cache", systemImage: "bolt.fill")
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
          }
        }
      }
      .navigationTitle(L10n.text(de: "Aktivität", en: "Activity", fr: "Activité"))
      .toolbar {
        ToolbarItem {
          Button(role: .destructive) {
            telemetry.clear()
          } label: {
            Label(
              L10n.text(de: "Protokoll leeren", en: "Clear Log", fr: "Effacer le journal"),
              systemImage: "trash"
            )
          }
          .disabled(telemetry.entries.isEmpty)
        }
      }
    }
    .frame(minWidth: 920, minHeight: 620)
  }

  private var summary: some View {
    let value = telemetry.summary
    return HStack(spacing: 18) {
      metric(L10n.text(de: "Aufrufe", en: "Calls", fr: "Appels"), value: "\(value.total)")
      metric(L10n.text(de: "Erfolgreich", en: "Succeeded", fr: "Réussis"), value: "\(value.succeeded)")
      metric(L10n.text(de: "Fehler", en: "Failed", fr: "Échecs"), value: "\(value.failed)")
      metric("Cache", value: "\(value.cacheHits)")
      metric(
        "Ø",
        value: value.averageMilliseconds.formatted(.number.precision(.fractionLength(1))) + " ms"
      )
      Spacer()
    }
    .padding(16)
  }

  private func metric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title3.monospacedDigit())
    }
  }
}
