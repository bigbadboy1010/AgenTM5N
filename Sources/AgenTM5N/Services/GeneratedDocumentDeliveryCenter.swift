import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class GeneratedDocumentDeliveryCenter: ObservableObject {
  public static let shared = GeneratedDocumentDeliveryCenter()

  @Published public private(set) var pendingDocument: GeneratedDocumentSummary?
  @Published public private(set) var isPresenting = false

  private let service: GeneratedDocumentService

  public init(service: GeneratedDocumentService = .shared) {
    self.service = service
  }

  public func queue(_ document: GeneratedDocumentSummary) {
    pendingDocument = document
  }

  public func dismissPending() {
    guard !isPresenting else { return }
    pendingDocument = nil
  }

  public func presentPending() async {
    guard let pendingDocument else { return }
    await present(document: pendingDocument)
  }

  public func present(documentID: UUID) async {
    do {
      let document = try await service.resolve(documentID.uuidString)
      await present(document: document)
    } catch {
      presentError(error)
    }
  }

  private func present(document: GeneratedDocumentSummary) async {
    guard !isPresenting else { return }
    isPresenting = true
    defer { isPresenting = false }

    NSApp.activate(ignoringOtherApps: true)

    let panel = NSSavePanel()
    panel.title = L10n.text(
      de: "Generiertes Dokument speichern",
      en: "Save Generated Document",
      fr: "Enregistrer le document généré"
    )
    panel.prompt = L10n.text(de: "Speichern", en: "Save", fr: "Enregistrer")
    panel.nameFieldStringValue = document.fileName
    panel.canCreateDirectories = true
    if let type = UTType(filenameExtension: document.format.fileExtension) {
      panel.allowedContentTypes = [type]
    }

    let response = await modalResponse(for: panel)
    guard response == .OK, let destination = panel.url else {
      return
    }

    do {
      try await service.export(id: document.id, to: destination)
      if pendingDocument?.id == document.id {
        pendingDocument = nil
      }
    } catch {
      presentError(error)
    }
  }

  private func modalResponse(
    for panel: NSSavePanel
  ) async -> NSApplication.ModalResponse {
    if let window = NSApp.keyWindow ?? NSApp.mainWindow {
      return await withCheckedContinuation { continuation in
        panel.beginSheetModal(for: window) { response in
          continuation.resume(returning: response)
        }
      }
    }
    return panel.runModal()
  }

  private func presentError(_ error: Error) {
    let alert = NSAlert(error: error)
    alert.alertStyle = .warning
    alert.runModal()
  }
}
