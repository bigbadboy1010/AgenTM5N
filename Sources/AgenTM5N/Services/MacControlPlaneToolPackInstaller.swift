import Foundation

/// Installs macOS control-plane tools into the existing Toolsmith runtime.
/// The tools intentionally reuse AgenTM5N's central capability, permission,
/// audit, timeout, stagnation-guard and secret-isolation path.
public enum MacControlPlaneToolPackInstaller {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var installedForProcess = false

  public static var toolNames: Set<String> {
    Set(specifications.map(\.name))
  }

  public static func isControlPlaneToolName(_ name: String) -> Bool {
    toolNames.contains(name.lowercased())
  }

  public static func ensureInstalled(
    library: SelfBuiltToolLibrary = .shared
  ) {
    lock.lock()
    defer { lock.unlock() }
    guard !installedForProcess else { return }
    installedForProcess = true

    for specification in specifications {
      if (try? library.resolve(specification.name)) != nil {
        continue
      }
      do {
        _ = try library.createOrReplace(
          name: specification.name,
          description: specification.description,
          language: .zsh,
          parameters: specification.parameters,
          source: specification.source
        )
      } catch {
        AppLogger.app.error(
          "Mac control-plane tool install failed for \(specification.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  private struct Specification {
    let name: String
    let description: String
    let parameters: [SelfBuiltToolParameter]
    let source: String
  }

  private static func stringParameter(
    _ name: String,
    _ description: String,
    required: Bool = true
  ) -> SelfBuiltToolParameter {
    .init(name: name, type: .string, description: description, required: required)
  }

  private static func integerParameter(
    _ name: String,
    _ description: String,
    required: Bool = false
  ) -> SelfBuiltToolParameter {
    .init(name: name, type: .integer, description: description, required: required)
  }

  private static var specifications: [Specification] {
    [
      Specification(
        name: "custom_mac_apps_list",
        description: "[AgenTM5N Mac Control Plane] List visible macOS application processes through System Events.",
        parameters: [],
        source: #"""
          /usr/bin/osascript <<'APPLESCRIPT'
          tell application "System Events"
            set appNames to name of every application process whose background only is false
          end tell
          set AppleScript's text item delimiters to linefeed
          return appNames as text
          APPLESCRIPT
          """#
      ),
      Specification(
        name: "custom_mac_app_open",
        description: "[AgenTM5N Mac Control Plane] Launch or activate an installed macOS application by its visible application name.",
        parameters: [
          stringParameter("app_name", "Visible macOS application name, for example Safari, Mail, Xcode, or Finder.")
        ],
        source: #"""
          app_name="${AGENTM5N_ARG_APP_NAME:?missing app_name}"
          /usr/bin/open -a "$app_name"
          printf 'Opened application: %s\n' "$app_name"
          """#
      ),
      Specification(
        name: "custom_mac_app_focus",
        description: "[AgenTM5N Mac Control Plane] Bring one running macOS application to the foreground through System Events. Accessibility/Automation permission may be required.",
        parameters: [
          stringParameter("app_name", "Exact visible name of a running macOS application process.")
        ],
        source: #"""
          app_name="${AGENTM5N_ARG_APP_NAME:?missing app_name}"
          /usr/bin/osascript - "$app_name" <<'APPLESCRIPT'
          on run argv
            set appName to item 1 of argv
            tell application "System Events"
              if not (exists application process appName) then error "Application is not running: " & appName
              set frontmost of application process appName to true
            end tell
            return "Focused application: " & appName
          end run
          APPLESCRIPT
          """#
      ),
      Specification(
        name: "custom_mac_windows_list",
        description: "[AgenTM5N Mac Control Plane] List visible windows for foreground-capable macOS applications through the Accessibility/System Events layer.",
        parameters: [],
        source: #"""
          /usr/bin/osascript <<'APPLESCRIPT'
          set outputLines to {}
          tell application "System Events"
            repeat with p in (every application process whose background only is false)
              set processName to name of p
              try
                repeat with w in windows of p
                  set windowName to name of w
                  set end of outputLines to processName & "\t" & windowName
                end repeat
              end try
            end repeat
          end tell
          set AppleScript's text item delimiters to linefeed
          return outputLines as text
          APPLESCRIPT
          """#
      ),
      Specification(
        name: "custom_mac_spotlight_search",
        description: "[AgenTM5N Mac Control Plane] Search the local Spotlight metadata index across locations that macOS permits AgenTM5N to access.",
        parameters: [
          stringParameter("query", "Spotlight search expression or text query."),
          integerParameter("limit", "Maximum results to return. Defaults to 50.")
        ],
        source: #"""
          query="${AGENTM5N_ARG_QUERY:?missing query}"
          limit="${AGENTM5N_ARG_LIMIT:-50}"
          if ! [[ "$limit" =~ '^[0-9]+$' ]] || (( limit < 1 || limit > 500 )); then
            print -u2 -- "limit must be between 1 and 500"
            exit 64
          fi
          /usr/bin/mdfind "$query" | /usr/bin/head -n "$limit"
          """#
      ),
      Specification(
        name: "custom_mac_file_metadata",
        description: "[AgenTM5N Mac Control Plane] Read Spotlight metadata for an arbitrary local path that macOS permits AgenTM5N to access.",
        parameters: [
          stringParameter("path", "Absolute path or workspace-relative path.")
        ],
        source: #"""
          value="${AGENTM5N_ARG_PATH:?missing path}"
          if [[ "$value" == /* ]]; then
            target="$value"
          else
            target="$AGENTM5N_WORKSPACE/$value"
          fi
          /usr/bin/mdls "$target"
          """#
      ),
      Specification(
        name: "custom_mac_open_path",
        description: "[AgenTM5N Mac Control Plane] Open a local file, folder, application, URL file, or document with the default macOS application.",
        parameters: [
          stringParameter("path", "Absolute path or workspace-relative path to open.")
        ],
        source: #"""
          value="${AGENTM5N_ARG_PATH:?missing path}"
          if [[ "$value" == /* ]]; then
            target="$value"
          else
            target="$AGENTM5N_WORKSPACE/$value"
          fi
          /usr/bin/open "$target"
          printf 'Opened path: %s\n' "$target"
          """#
      ),
      Specification(
        name: "custom_mac_screenshot",
        description: "[AgenTM5N Mac Control Plane] Capture the current macOS screen to a PNG file. macOS Screen Recording permission is required.",
        parameters: [
          stringParameter("output", "Absolute output path or workspace-relative PNG path, for example artifacts/screen.png.")
        ],
        source: #"""
          value="${AGENTM5N_ARG_OUTPUT:?missing output}"
          if [[ "$value" == /* ]]; then
            target="$value"
          else
            target="$AGENTM5N_WORKSPACE/$value"
          fi
          if [[ "$target" != *.png ]]; then
            print -u2 -- "output must end in .png"
            exit 64
          fi
          /bin/mkdir -p "${target:h}"
          /usr/sbin/screencapture -x "$target"
          printf 'Screenshot saved: %s\n' "$target"
          """#
      ),
      Specification(
        name: "custom_mac_shortcut_run_text",
        description: "[AgenTM5N Mac Control Plane] Run a named macOS Shortcut with plain-text input and return its textual output when available.",
        parameters: [
          stringParameter("name", "Exact Shortcut name."),
          stringParameter("input", "Plain-text input passed to the Shortcut.", required: false)
        ],
        source: #"""
          shortcut_name="${AGENTM5N_ARG_NAME:?missing name}"
          input_text="${AGENTM5N_ARG_INPUT:-}"
          input_file="$TMPDIR/shortcut-input.txt"
          printf '%s' "$input_text" > "$input_file"
          /usr/bin/shortcuts run "$shortcut_name" --input-path "$input_file"
          """#
      )
    ]
  }
}
