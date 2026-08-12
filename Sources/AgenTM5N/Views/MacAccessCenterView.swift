import AppKit
import ApplicationServices
import Contacts
import CoreGraphics
import EventKit
import SwiftUI

struct MacAccessCenterView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss

  @State private var calendarStatus = ""
  @State private var remindersStatus = ""
  @State private var contactsStatus = ""
  @State private var accessibilityStatus = ""
  @State private var screenRecordingStatus = ""

  private var auditRecords: [ToolExecutionRecord] {
    appState.messages
      .flatMap { $0.toolExecutions ?? [] }
      .sorted { $0.startedAt > $1.startedAt }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Mac Access Center 2.0")
            .font(.title2.bold())
          Text("Native macOS-Zugriffe, Control-Plane-Berechtigungen und gemeinsamer Agent-Audit")
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Aktualisieren", action: refresh)
        Button("Schließen") { dismiss() }
      }

      GroupBox("Gemeinsamer Agent-Router") {
        VStack(alignment: .leading, spacing: 8) {
          accessRow(
            title: "Apple On-Device",
            detail: "Foundation-Models-Tools laufen über denselben AppState Permission-/Audit-Pfad.",
            state: "Aktiv"
          )
          Divider()
          accessRow(
            title: "Ollama / MLX / Cloud",
            detail: "Tool Calls verwenden denselben Risiko-, Freigabe-, Capability- und Audit-Mechanismus.",
            state: "Aktiv"
          )
          Divider()
          accessRow(
            title: "Mac Control Plane",
            detail: "Apps, Fenster, Spotlight, Screenshots, Finder und Shortcuts werden als zentral klassifizierte Agent-Tools ausgeführt.",
            state: "Aktiv"
          )
          Divider()
          accessRow(
            title: "Berechtigungsmodus",
            detail: appState.configuration.permissionMode.explanation,
            state: appState.configuration.permissionMode.displayName
          )
        }
        .padding(.vertical, 6)
      }

      GroupBox("macOS Datenschutz & Steuerung") {
        VStack(alignment: .leading, spacing: 10) {
          permissionRow(
            systemImage: "calendar",
            title: "Kalender",
            status: calendarStatus,
            settingsAnchor: "Privacy_Calendars"
          )
          Divider()
          permissionRow(
            systemImage: "checklist",
            title: "Erinnerungen",
            status: remindersStatus,
            settingsAnchor: "Privacy_Reminders"
          )
          Divider()
          permissionRow(
            systemImage: "person.crop.circle",
            title: "Kontakte",
            status: contactsStatus,
            settingsAnchor: "Privacy_Contacts"
          )
          Divider()
          permissionRow(
            systemImage: "hand.point.up.left",
            title: "Bedienungshilfen / Accessibility",
            status: accessibilityStatus,
            settingsAnchor: "Privacy_Accessibility"
          )
          Divider()
          permissionRow(
            systemImage: "rectangle.dashed.badge.record",
            title: "Bildschirmaufnahme",
            status: screenRecordingStatus,
            settingsAnchor: "Privacy_ScreenCapture"
          )
          Divider()
          permissionRow(
            systemImage: "externaldrive.fill",
            title: "Festplattenvollzugriff",
            status: "Von macOS verwaltet – kein verlässlicher öffentlicher Preflight-Status",
            settingsAnchor: "Privacy_AllFiles"
          )
          Divider()
          permissionRow(
            systemImage: "gearshape.2",
            title: "Automation / Apple Events",
            status: "Pro Ziel-App durch macOS geschützt",
            settingsAnchor: "Privacy_Automation"
          )
          Divider()
          permissionRow(
            systemImage: "envelope",
            title: "Apple Mail",
            status: "Über Automation / Apple Events",
            settingsAnchor: "Privacy_Automation"
          )
        }
        .padding(.vertical, 6)
      }

      GroupBox("Control-Plane-Fähigkeiten") {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
          controlPlaneRow("Apps", "auflisten · starten · fokussieren")
          controlPlaneRow("Fenster", "auflisten über Accessibility/System Events")
          controlPlaneRow("Spotlight", "systemweite Metadatensuche im von macOS erlaubten Bereich")
          controlPlaneRow("Finder / Dateien", "anzeigen · öffnen · Metadaten")
          controlPlaneRow("Screen", "Screenshot für Agent/Vision-Pipelines")
          controlPlaneRow("Shortcuts", "auflisten · ausführen · Text-Input")
          controlPlaneRow("Persönliche Daten", "Kalender · Kontakte · Mail · Erinnerungen")
        }
        .padding(.vertical, 6)
      }

      GroupBox("Audit") {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Gespeicherte Tool-Ausführungen")
            Spacer()
            Text("\(auditRecords.count)")
              .monospacedDigit()
          }
          if let latest = auditRecords.first {
            Divider()
            Text("Letzte Aktion: \(latest.toolName) · \(latest.risk.displayName) · \(latest.status.rawValue)")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 6)
      }

      Spacer()
    }
    .padding(24)
    .frame(minWidth: 820, minHeight: 760)
    .onAppear(perform: refresh)
  }

  @ViewBuilder
  private func accessRow(title: String, detail: String, state: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "checkmark.shield.fill")
        .foregroundStyle(.green)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).fontWeight(.semibold)
        Text(detail).font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Text(state)
        .font(.callout.monospaced())
    }
  }

  @ViewBuilder
  private func permissionRow(
    systemImage: String,
    title: String,
    status: String,
    settingsAnchor: String
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).fontWeight(.semibold)
        Text(status).font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Button("Systemeinstellungen") {
        openPrivacySettings(anchor: settingsAnchor)
      }
    }
  }

  @ViewBuilder
  private func controlPlaneRow(_ capability: String, _ detail: String) -> some View {
    GridRow {
      Text(capability).fontWeight(.semibold)
      Text(detail).foregroundStyle(.secondary)
    }
  }

  private func refresh() {
    calendarStatus = Self.calendarAuthorizationDescription()
    remindersStatus = Self.remindersAuthorizationDescription()
    contactsStatus = Self.contactsAuthorizationDescription()
    accessibilityStatus = AXIsProcessTrusted()
      ? "Erlaubt"
      : "Nicht erlaubt / noch nicht freigegeben"
    screenRecordingStatus = CGPreflightScreenCaptureAccess()
      ? "Erlaubt"
      : "Nicht erlaubt / noch nicht freigegeben"
  }

  private static func calendarAuthorizationDescription() -> String {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess: "Vollzugriff erlaubt"
    case .writeOnly: "Nur Schreibzugriff"
    case .notDetermined: "Noch nicht angefragt"
    case .denied: "Abgelehnt"
    case .restricted: "Eingeschränkt"
    @unknown default: "Unbekannt"
    }
  }

  private static func remindersAuthorizationDescription() -> String {
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .fullAccess: "Vollzugriff erlaubt"
    case .authorized: "Erlaubt"
    case .notDetermined: "Noch nicht angefragt"
    case .denied: "Abgelehnt"
    case .restricted: "Eingeschränkt"
    case .writeOnly: "Nur Schreibzugriff"
    @unknown default: "Unbekannt"
    }
  }

  private static func contactsAuthorizationDescription() -> String {
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .authorized: "Erlaubt"
    case .limited: "Eingeschränkt erlaubt"
    case .notDetermined: "Noch nicht angefragt"
    case .denied: "Abgelehnt"
    case .restricted: "Eingeschränkt"
    @unknown default: "Unbekannt"
    }
  }

  private func openPrivacySettings(anchor: String) {
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
    ) else { return }
    NSWorkspace.shared.open(url)
  }
}
