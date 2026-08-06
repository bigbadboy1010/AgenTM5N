import AppKit
import SwiftTerm
import SwiftUI

struct TerminalWorkspaceView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label(appState.terminalLaunch.title, systemImage: "terminal")
          .font(.headline)
        Spacer()
        Button {
          appState.openLocalTerminal()
        } label: {
          Label("Lokales Terminal", systemImage: "plus.rectangle.on.rectangle")
        }
      }
      .padding(12)

      Divider()

      EmbeddedTerminalView(launch: appState.terminalLaunch)
        .id(appState.terminalLaunch.id)
        .background(Color.black)
    }
    .navigationTitle("Terminal")
  }
}

private struct EmbeddedTerminalView: NSViewRepresentable {
  let launch: TerminalLaunch

  func makeCoordinator() -> Coordinator {
    Coordinator(cleanupPaths: launch.cleanupPaths)
  }

  func makeNSView(context: Context) -> LocalProcessTerminalView {
    let terminal = LocalProcessTerminalView(frame: .zero)
    terminal.wantsLayer = true
    terminal.processDelegate = context.coordinator
    terminal.nativeForegroundColor = .white
    terminal.nativeBackgroundColor = NSColor(
      calibratedRed: 0.08,
      green: 0.09,
      blue: 0.11,
      alpha: 1
    )
    terminal.layer?.backgroundColor = terminal.nativeBackgroundColor.cgColor
    terminal.caretColor = .systemGreen
    terminal.getTerminal().setCursorStyle(.steadyBlock)
    terminal.metalBufferingMode = .perFrameAggregated

    do {
      try terminal.setUseMetal(true)
    } catch {
      AppLogger.terminal.error(
        "SwiftTerm Metal renderer failed: \(error.localizedDescription, privacy: .public)")
    }

    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let executable = FileManager.default.isExecutableFile(atPath: shell) ? shell : "/bin/zsh"
    let execName = "-" + URL(fileURLWithPath: executable).lastPathComponent
    terminal.startProcess(executable: executable, execName: execName)

    var commands = [
      "cd " + ShellEscaping.singleQuoted(FileManager.default.homeDirectoryForCurrentUser.path)
    ]
    if let initialCommand = launch.initialCommand,
      !initialCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      commands.append(initialCommand)
    }
    let commandText = commands.joined(separator: "\n") + "\n"

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      let bytes = Array(commandText.utf8)
      terminal.send(source: terminal, data: bytes[...])
    }
    return terminal
  }

  func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

  static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
    coordinator.cleanup()
  }

  final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
    private let cleanupPaths: [URL]
    private var cleanedUp = false

    init(cleanupPaths: [URL]) {
      self.cleanupPaths = cleanupPaths
    }

    func sizeChanged(
      source: LocalProcessTerminalView,
      newCols: Int,
      newRows: Int
    ) {}

    func setTerminalTitle(
      source: LocalProcessTerminalView,
      title: String
    ) {}

    func hostCurrentDirectoryUpdate(
      source: TerminalView,
      directory: String?
    ) {}

    func processTerminated(
      source: TerminalView,
      exitCode: Int32?
    ) {
      cleanup()
    }

    func cleanup() {
      guard !cleanedUp else { return }
      cleanedUp = true
      for path in cleanupPaths {
        do {
          try FileManager.default.removeItem(at: path)
        } catch {
          AppLogger.security.error(
            "Runtime secret cleanup failed for \(path.path, privacy: .private): \(error.localizedDescription, privacy: .public)"
          )
        }
      }
    }
  }
}
