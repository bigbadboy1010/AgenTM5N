import Foundation

/// Installs AgenTM5N-maintained command tools into the existing Toolsmith
/// sandbox. Bundled tools deliberately reuse the same permission, audit,
/// capability, timeout and secret-isolation path as user-authored tools.
/// Existing records are never overwritten, so local user changes remain
/// authoritative.
public enum BundledToolPackInstaller {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var installedForProcess = false

  public static var bundledToolNames: Set<String> {
    Set(specifications.map(\.name))
  }

  public static func isBundledToolName(_ name: String) -> Bool {
    bundledToolNames.contains(name.lowercased())
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
          "Bundled tool install failed for \(specification.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
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

  private static func booleanParameter(
    _ name: String,
    _ description: String,
    required: Bool = false
  ) -> SelfBuiltToolParameter {
    .init(name: name, type: .boolean, description: description, required: required)
  }

  private static let cliResolver = #"""
    find_cli() {
      local name="$1"
      local candidate
      for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name" "/usr/bin/$name" "/bin/$name" "/usr/sbin/$name" "/sbin/$name"; do
        if [[ -x "$candidate" ]]; then
          print -r -- "$candidate"
          return 0
        fi
      done
      print -u2 -- "Required CLI not found: $name"
      return 127
    }
    """#

  private static let safeRelativePath = #"""
    require_safe_relative_path() {
      local value="$1"
      if [[ -z "$value" || "$value" == /* || "$value" == ".." || "$value" == ../* || "$value" == */../* || "$value" == */.. || "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        print -u2 -- "Path must stay inside AGENTM5N_WORKSPACE: $value"
        return 64
      fi
    }
    """#

  private static var specifications: [Specification] {
    filesystemSpecifications
      + gitSpecifications
      + dockerSpecifications
      + podmanSpecifications
      + kubernetesSpecifications
      + openShiftSpecifications
      + networkSpecifications
      + mcpSpecifications
  }

  private static var filesystemSpecifications: [Specification] {
    [
      Specification(
        name: "custom_builtin_fs_stat",
        description: "[AgenTM5N Built-in / Filesystem] Inspect metadata and disk usage for a workspace-relative file or directory.",
        parameters: [stringParameter("path", "Workspace-relative path.")],
        source: cliResolver + safeRelativePath + #"""
          path="$AGENTM5N_ARG_PATH"
          require_safe_relative_path "$path"
          target="$AGENTM5N_WORKSPACE/$path"
          [[ -e "$target" ]] || { print -u2 -- "Path not found: $path"; exit 66; }
          /usr/bin/stat -f 'path=%N%ntype=%HT%nmode=%Sp%nsize=%z%nmodified=%Sm%nowner=%Su:%Sg' "$target"
          /usr/bin/du -sh "$target" 2>/dev/null || true
          """#
      ),
      Specification(
        name: "custom_builtin_fs_sha256",
        description: "[AgenTM5N Built-in / Filesystem] Calculate SHA-256 for a workspace-relative file without modifying it.",
        parameters: [stringParameter("path", "Workspace-relative file path.")],
        source: safeRelativePath + #"""
          path="$AGENTM5N_ARG_PATH"
          require_safe_relative_path "$path"
          target="$AGENTM5N_WORKSPACE/$path"
          [[ -f "$target" ]] || { print -u2 -- "File not found: $path"; exit 66; }
          /usr/bin/shasum -a 256 "$target"
          """#
      ),
      Specification(
        name: "custom_builtin_fs_mkdir",
        description: "[AgenTM5N Built-in / Filesystem] Create a directory tree inside the active workspace.",
        parameters: [stringParameter("path", "Workspace-relative directory path.")],
        source: safeRelativePath + #"""
          path="$AGENTM5N_ARG_PATH"
          require_safe_relative_path "$path"
          /bin/mkdir -p -- "$AGENTM5N_WORKSPACE/$path"
          print -r -- "created: $path"
          """#
      ),
      Specification(
        name: "custom_builtin_fs_copy",
        description: "[AgenTM5N Built-in / Filesystem] Copy a file or directory between two workspace-relative paths.",
        parameters: [
          stringParameter("source", "Workspace-relative source path."),
          stringParameter("destination", "Workspace-relative destination path."),
        ],
        source: safeRelativePath + #"""
          src="$AGENTM5N_ARG_SOURCE"
          dst="$AGENTM5N_ARG_DESTINATION"
          require_safe_relative_path "$src"
          require_safe_relative_path "$dst"
          [[ -e "$AGENTM5N_WORKSPACE/$src" ]] || { print -u2 -- "Source not found: $src"; exit 66; }
          /bin/cp -R -- "$AGENTM5N_WORKSPACE/$src" "$AGENTM5N_WORKSPACE/$dst"
          print -r -- "copied: $src -> $dst"
          """#
      ),
      Specification(
        name: "custom_builtin_fs_move",
        description: "[AgenTM5N Built-in / Filesystem] Move or rename a file or directory inside the active workspace.",
        parameters: [
          stringParameter("source", "Workspace-relative source path."),
          stringParameter("destination", "Workspace-relative destination path."),
        ],
        source: safeRelativePath + #"""
          src="$AGENTM5N_ARG_SOURCE"
          dst="$AGENTM5N_ARG_DESTINATION"
          require_safe_relative_path "$src"
          require_safe_relative_path "$dst"
          [[ -e "$AGENTM5N_WORKSPACE/$src" ]] || { print -u2 -- "Source not found: $src"; exit 66; }
          /bin/mv -- "$AGENTM5N_WORKSPACE/$src" "$AGENTM5N_WORKSPACE/$dst"
          print -r -- "moved: $src -> $dst"
          """#
      ),
      Specification(
        name: "custom_builtin_archive_create",
        description: "[AgenTM5N Built-in / Filesystem] Create a ZIP archive from a workspace-relative file or directory.",
        parameters: [
          stringParameter("source", "Workspace-relative source path."),
          stringParameter("archive", "Workspace-relative .zip destination."),
        ],
        source: safeRelativePath + #"""
          src="$AGENTM5N_ARG_SOURCE"
          archive="$AGENTM5N_ARG_ARCHIVE"
          require_safe_relative_path "$src"
          require_safe_relative_path "$archive"
          [[ "$archive" == *.zip ]] || { print -u2 -- "Archive must end in .zip"; exit 64; }
          [[ -e "$AGENTM5N_WORKSPACE/$src" ]] || { print -u2 -- "Source not found: $src"; exit 66; }
          /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$AGENTM5N_WORKSPACE/$src" "$AGENTM5N_WORKSPACE/$archive"
          print -r -- "archive created: $archive"
          """#
      ),
      Specification(
        name: "custom_builtin_archive_extract",
        description: "[AgenTM5N Built-in / Filesystem] Extract a workspace-relative ZIP archive into a workspace-relative directory.",
        parameters: [
          stringParameter("archive", "Workspace-relative .zip source."),
          stringParameter("destination", "Workspace-relative destination directory."),
        ],
        source: safeRelativePath + #"""
          archive="$AGENTM5N_ARG_ARCHIVE"
          dst="$AGENTM5N_ARG_DESTINATION"
          require_safe_relative_path "$archive"
          require_safe_relative_path "$dst"
          [[ -f "$AGENTM5N_WORKSPACE/$archive" ]] || { print -u2 -- "Archive not found: $archive"; exit 66; }
          /bin/mkdir -p -- "$AGENTM5N_WORKSPACE/$dst"
          /usr/bin/ditto -x -k "$AGENTM5N_WORKSPACE/$archive" "$AGENTM5N_WORKSPACE/$dst"
          print -r -- "archive extracted: $archive -> $dst"
          """#
      ),
    ]
  }

  private static var gitSpecifications: [Specification] {
    [
      Specification(
        name: "custom_builtin_git_log",
        description: "[AgenTM5N Built-in / Git] Show a bounded decorated Git commit history for the active workspace repository.",
        parameters: [integerParameter("limit", "Commit count from 1 to 200.")],
        source: #"""
          limit="${AGENTM5N_ARG_LIMIT:-30}"
          limit="${limit%%.*}"
          (( limit < 1 )) && limit=1
          (( limit > 200 )) && limit=200
          /usr/bin/git log --oneline --decorate --graph --max-count="$limit"
          """#
      ),
      Specification(
        name: "custom_builtin_git_show",
        description: "[AgenTM5N Built-in / Git] Show one Git revision with bounded patch and metadata.",
        parameters: [stringParameter("revision", "Revision, tag, branch or commit SHA.")],
        source: #"""
          revision="$AGENTM5N_ARG_REVISION"
          [[ "$revision" != -* && "$revision" != *$'\n'* && "$revision" != *$'\r'* ]] || { print -u2 -- "Invalid revision"; exit 64; }
          /usr/bin/git show --stat --patch --no-ext-diff --format=fuller -- "$revision"
          """#
      ),
      Specification(
        name: "custom_builtin_git_fetch",
        description: "[AgenTM5N Built-in / Git] Fetch refs from a configured Git remote without merging them.",
        parameters: [stringParameter("remote", "Git remote name. Defaults to origin.", required: false)],
        source: #"""
          remote="${AGENTM5N_ARG_REMOTE:-origin}"
          [[ "$remote" =~ '^[A-Za-z0-9._-]+$' ]] || { print -u2 -- "Invalid remote"; exit 64; }
          /usr/bin/git fetch --prune -- "$remote"
          /usr/bin/git status --short --branch
          """#
      ),
      Specification(
        name: "custom_builtin_git_pull_ff",
        description: "[AgenTM5N Built-in / Git] Pull the current branch using fast-forward-only semantics.",
        parameters: [stringParameter("remote", "Git remote name. Defaults to origin.", required: false)],
        source: #"""
          remote="${AGENTM5N_ARG_REMOTE:-origin}"
          [[ "$remote" =~ '^[A-Za-z0-9._-]+$' ]] || { print -u2 -- "Invalid remote"; exit 64; }
          /usr/bin/git pull --ff-only -- "$remote"
          /usr/bin/git status --short --branch
          """#
      ),
      Specification(
        name: "custom_builtin_git_push",
        description: "[AgenTM5N Built-in / Git] Push the current branch to a configured Git remote. Never force-pushes.",
        parameters: [stringParameter("remote", "Git remote name. Defaults to origin.", required: false)],
        source: #"""
          remote="${AGENTM5N_ARG_REMOTE:-origin}"
          [[ "$remote" =~ '^[A-Za-z0-9._-]+$' ]] || { print -u2 -- "Invalid remote"; exit 64; }
          branch="$(/usr/bin/git branch --show-current)"
          [[ -n "$branch" ]] || { print -u2 -- "Detached HEAD cannot be pushed by this tool"; exit 65; }
          /usr/bin/git push --set-upstream "$remote" "$branch"
          """#
      ),
    ]
  }

  private static var dockerSpecifications: [Specification] {
    let prefix = cliResolver + #"""
      cli="$(find_cli docker)" || exit $?
      """#
    return [
      Specification(
        name: "custom_builtin_docker_ps",
        description: "[AgenTM5N Built-in / Docker] List Docker containers with names, images, status and ports.",
        parameters: [booleanParameter("all", "Include stopped containers.")],
        source: prefix + #"""
          if [[ "${AGENTM5N_ARG_ALL:-false}" == "true" ]]; then
            "$cli" ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
          else
            "$cli" ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
          fi
          """#
      ),
      Specification(
        name: "custom_builtin_docker_inspect",
        description: "[AgenTM5N Built-in / Docker] Inspect one Docker container, image, volume or network as JSON.",
        parameters: [stringParameter("target", "Docker object name or ID.")],
        source: prefix + #"""
          target="$AGENTM5N_ARG_TARGET"
          [[ "$target" != -* && "$target" != *$'\n'* ]] || { print -u2 -- "Invalid target"; exit 64; }
          "$cli" inspect -- "$target"
          """#
      ),
      Specification(
        name: "custom_builtin_docker_logs",
        description: "[AgenTM5N Built-in / Docker] Read bounded recent logs from a Docker container.",
        parameters: [
          stringParameter("container", "Container name or ID."),
          integerParameter("tail", "Number of log lines, default 200."),
        ],
        source: prefix + #"""
          container="$AGENTM5N_ARG_CONTAINER"
          tail="${AGENTM5N_ARG_TAIL:-200}"; tail="${tail%%.*}"
          (( tail < 1 )) && tail=1; (( tail > 5000 )) && tail=5000
          [[ "$container" != -* && "$container" != *$'\n'* ]] || { print -u2 -- "Invalid container"; exit 64; }
          "$cli" logs --tail "$tail" --timestamps "$container"
          """#
      ),
      Specification(
        name: "custom_builtin_docker_stats",
        description: "[AgenTM5N Built-in / Docker] Return one-shot Docker CPU, memory, network and block-I/O statistics.",
        parameters: [],
        source: prefix + #"""
          "$cli" stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}'
          """#
      ),
      Specification(
        name: "custom_builtin_docker_action",
        description: "[AgenTM5N Built-in / Docker] Start, stop, restart, pause or unpause one Docker container.",
        parameters: [
          stringParameter("container", "Container name or ID."),
          stringParameter("action", "start, stop, restart, pause or unpause."),
        ],
        source: prefix + #"""
          container="$AGENTM5N_ARG_CONTAINER"
          action="$AGENTM5N_ARG_ACTION"
          case "$action" in start|stop|restart|pause|unpause) ;; *) print -u2 -- "Unsupported action"; exit 64;; esac
          [[ "$container" != -* && "$container" != *$'\n'* ]] || { print -u2 -- "Invalid container"; exit 64; }
          "$cli" "$action" "$container"
          """#
      ),
      Specification(
        name: "custom_builtin_docker_exec",
        description: "[AgenTM5N Built-in / Docker] Execute a non-interactive shell command inside a Docker container. Execution remains approval-gated by AgenTM5N.",
        parameters: [
          stringParameter("container", "Container name or ID."),
          stringParameter("command", "Command executed through /bin/sh -lc inside the container."),
        ],
        source: prefix + #"""
          container="$AGENTM5N_ARG_CONTAINER"
          command="$AGENTM5N_ARG_COMMAND"
          [[ "$container" != -* && "$container" != *$'\n'* ]] || { print -u2 -- "Invalid container"; exit 64; }
          "$cli" exec "$container" /bin/sh -lc "$command"
          """#
      ),
    ]
  }

  private static var podmanSpecifications: [Specification] {
    let prefix = cliResolver + #"""
      cli="$(find_cli podman)" || exit $?
      """#
    return [
      Specification(
        name: "custom_builtin_podman_ps",
        description: "[AgenTM5N Built-in / Podman] List Podman containers.",
        parameters: [booleanParameter("all", "Include stopped containers.")],
        source: prefix + #"""
          if [[ "${AGENTM5N_ARG_ALL:-false}" == "true" ]]; then "$cli" ps -a; else "$cli" ps; fi
          """#
      ),
      Specification(
        name: "custom_builtin_podman_inspect",
        description: "[AgenTM5N Built-in / Podman] Inspect a Podman object as JSON.",
        parameters: [stringParameter("target", "Podman object name or ID.")],
        source: prefix + #"""
          target="$AGENTM5N_ARG_TARGET"
          [[ "$target" != -* && "$target" != *$'\n'* ]] || { print -u2 -- "Invalid target"; exit 64; }
          "$cli" inspect -- "$target"
          """#
      ),
      Specification(
        name: "custom_builtin_podman_logs",
        description: "[AgenTM5N Built-in / Podman] Read bounded recent logs from a Podman container.",
        parameters: [stringParameter("container", "Container name or ID."), integerParameter("tail", "Log line count.")],
        source: prefix + #"""
          tail="${AGENTM5N_ARG_TAIL:-200}"; tail="${tail%%.*}"
          (( tail < 1 )) && tail=1; (( tail > 5000 )) && tail=5000
          "$cli" logs --tail "$tail" "$AGENTM5N_ARG_CONTAINER"
          """#
      ),
      Specification(
        name: "custom_builtin_podman_action",
        description: "[AgenTM5N Built-in / Podman] Start, stop, restart, pause or unpause one Podman container.",
        parameters: [stringParameter("container", "Container name or ID."), stringParameter("action", "start, stop, restart, pause or unpause.")],
        source: prefix + #"""
          action="$AGENTM5N_ARG_ACTION"
          case "$action" in start|stop|restart|pause|unpause) ;; *) print -u2 -- "Unsupported action"; exit 64;; esac
          "$cli" "$action" "$AGENTM5N_ARG_CONTAINER"
          """#
      ),
    ]
  }

  private static var kubernetesSpecifications: [Specification] {
    let prefix = cliResolver + #"""
      cli="$(find_cli kubectl)" || exit $?
      """#
    return [
      Specification(
        name: "custom_builtin_kube_contexts",
        description: "[AgenTM5N Built-in / Kubernetes] Show current Kubernetes context and all configured contexts.",
        parameters: [],
        source: prefix + #"""
          print -r -- "CURRENT CONTEXT"
          "$cli" config current-context
          print -r -- "\nCONTEXTS"
          "$cli" config get-contexts
          """#
      ),
      Specification(
        name: "custom_builtin_kube_pods",
        description: "[AgenTM5N Built-in / Kubernetes] List Kubernetes pods, optionally in one namespace or across all namespaces.",
        parameters: [
          stringParameter("namespace", "Namespace. Defaults to current namespace.", required: false),
          booleanParameter("all_namespaces", "List pods across all namespaces."),
        ],
        source: prefix + #"""
          if [[ "${AGENTM5N_ARG_ALL_NAMESPACES:-false}" == "true" ]]; then
            "$cli" get pods -A -o wide
          elif [[ -n "${AGENTM5N_ARG_NAMESPACE:-}" ]]; then
            "$cli" get pods -n "$AGENTM5N_ARG_NAMESPACE" -o wide
          else
            "$cli" get pods -o wide
          fi
          """#
      ),
      Specification(
        name: "custom_builtin_kube_logs",
        description: "[AgenTM5N Built-in / Kubernetes] Read bounded pod logs with optional namespace and container selection.",
        parameters: [
          stringParameter("pod", "Pod name."),
          stringParameter("namespace", "Namespace.", required: false),
          stringParameter("container", "Container name.", required: false),
          integerParameter("tail", "Log line count, default 200."),
        ],
        source: prefix + #"""
          tail="${AGENTM5N_ARG_TAIL:-200}"; tail="${tail%%.*}"
          (( tail < 1 )) && tail=1; (( tail > 5000 )) && tail=5000
          args=(logs "$AGENTM5N_ARG_POD" --tail="$tail" --timestamps=true)
          [[ -n "${AGENTM5N_ARG_NAMESPACE:-}" ]] && args+=(-n "$AGENTM5N_ARG_NAMESPACE")
          [[ -n "${AGENTM5N_ARG_CONTAINER:-}" ]] && args+=(-c "$AGENTM5N_ARG_CONTAINER")
          "$cli" "${args[@]}"
          """#
      ),
      Specification(
        name: "custom_builtin_kube_describe",
        description: "[AgenTM5N Built-in / Kubernetes] Describe a Kubernetes resource.",
        parameters: [
          stringParameter("kind", "Resource kind such as pod, deployment, service or node."),
          stringParameter("name", "Resource name."),
          stringParameter("namespace", "Namespace when applicable.", required: false),
        ],
        source: prefix + #"""
          args=(describe "$AGENTM5N_ARG_KIND" "$AGENTM5N_ARG_NAME")
          [[ -n "${AGENTM5N_ARG_NAMESPACE:-}" ]] && args+=(-n "$AGENTM5N_ARG_NAMESPACE")
          "$cli" "${args[@]}"
          """#
      ),
      Specification(
        name: "custom_builtin_kube_rollout_status",
        description: "[AgenTM5N Built-in / Kubernetes] Check rollout status for a deployment, statefulset or daemonset.",
        parameters: [
          stringParameter("resource", "Resource reference such as deployment/api."),
          stringParameter("namespace", "Namespace.", required: false),
        ],
        source: prefix + #"""
          args=(rollout status "$AGENTM5N_ARG_RESOURCE" --timeout=45s)
          [[ -n "${AGENTM5N_ARG_NAMESPACE:-}" ]] && args+=(-n "$AGENTM5N_ARG_NAMESPACE")
          "$cli" "${args[@]}"
          """#
      ),
      Specification(
        name: "custom_builtin_kube_apply",
        description: "[AgenTM5N Built-in / Kubernetes] Apply one manifest file from inside the active workspace. The path cannot escape the workspace.",
        parameters: [stringParameter("path", "Workspace-relative YAML or JSON manifest path.")],
        source: prefix + safeRelativePath + #"""
          path="$AGENTM5N_ARG_PATH"
          require_safe_relative_path "$path"
          [[ -f "$AGENTM5N_WORKSPACE/$path" ]] || { print -u2 -- "Manifest not found: $path"; exit 66; }
          "$cli" apply -f "$AGENTM5N_WORKSPACE/$path"
          """#
      ),
    ]
  }

  private static var openShiftSpecifications: [Specification] {
    let prefix = cliResolver + #"""
      cli="$(find_cli oc)" || exit $?
      """#
    return [
      Specification(
        name: "custom_builtin_oc_project",
        description: "[AgenTM5N Built-in / OpenShift] Show the current OpenShift project and accessible project list.",
        parameters: [],
        source: prefix + #"""
          "$cli" project
          "$cli" projects
          """#
      ),
      Specification(
        name: "custom_builtin_oc_pods",
        description: "[AgenTM5N Built-in / OpenShift] List pods in the current or requested OpenShift project.",
        parameters: [stringParameter("project", "OpenShift project name.", required: false)],
        source: prefix + #"""
          if [[ -n "${AGENTM5N_ARG_PROJECT:-}" ]]; then "$cli" get pods -n "$AGENTM5N_ARG_PROJECT" -o wide; else "$cli" get pods -o wide; fi
          """#
      ),
      Specification(
        name: "custom_builtin_oc_routes",
        description: "[AgenTM5N Built-in / OpenShift] List OpenShift routes in the current or requested project.",
        parameters: [stringParameter("project", "OpenShift project name.", required: false)],
        source: prefix + #"""
          if [[ -n "${AGENTM5N_ARG_PROJECT:-}" ]]; then "$cli" get routes -n "$AGENTM5N_ARG_PROJECT"; else "$cli" get routes; fi
          """#
      ),
      Specification(
        name: "custom_builtin_oc_logs",
        description: "[AgenTM5N Built-in / OpenShift] Read bounded pod logs through the OpenShift CLI.",
        parameters: [stringParameter("pod", "Pod name."), stringParameter("project", "Project name.", required: false), integerParameter("tail", "Log line count.")],
        source: prefix + #"""
          tail="${AGENTM5N_ARG_TAIL:-200}"; tail="${tail%%.*}"
          (( tail < 1 )) && tail=1; (( tail > 5000 )) && tail=5000
          args=(logs "$AGENTM5N_ARG_POD" --tail="$tail")
          [[ -n "${AGENTM5N_ARG_PROJECT:-}" ]] && args+=(-n "$AGENTM5N_ARG_PROJECT")
          "$cli" "${args[@]}"
          """#
      ),
    ]
  }

  private static var networkSpecifications: [Specification] {
    [
      Specification(
        name: "custom_builtin_dns_lookup",
        description: "[AgenTM5N Built-in / Network] Resolve DNS records for a host using dig when available, with a native macOS fallback.",
        parameters: [stringParameter("host", "DNS hostname.")],
        source: cliResolver + #"""
          host="$AGENTM5N_ARG_HOST"
          [[ "$host" =~ '^[A-Za-z0-9._:-]+$' ]] || { print -u2 -- "Invalid host"; exit 64; }
          if cli="$(find_cli dig 2>/dev/null)"; then
            "$cli" +noall +answer "$host"
          else
            /usr/bin/dscacheutil -q host -a name "$host"
          fi
          """#
      ),
      Specification(
        name: "custom_builtin_ping",
        description: "[AgenTM5N Built-in / Network] Send a bounded number of ICMP echo requests to a host.",
        parameters: [stringParameter("host", "Hostname or IP address."), integerParameter("count", "Packet count from 1 to 10.")],
        source: #"""
          host="$AGENTM5N_ARG_HOST"
          count="${AGENTM5N_ARG_COUNT:-4}"; count="${count%%.*}"
          [[ "$host" =~ '^[A-Za-z0-9._:-]+$' ]] || { print -u2 -- "Invalid host"; exit 64; }
          (( count < 1 )) && count=1; (( count > 10 )) && count=10
          /sbin/ping -c "$count" "$host"
          """#
      ),
      Specification(
        name: "custom_builtin_traceroute",
        description: "[AgenTM5N Built-in / Network] Run a bounded traceroute to a host.",
        parameters: [stringParameter("host", "Hostname or IP address."), integerParameter("max_hops", "Maximum hops from 1 to 30.")],
        source: #"""
          host="$AGENTM5N_ARG_HOST"
          hops="${AGENTM5N_ARG_MAX_HOPS:-20}"; hops="${hops%%.*}"
          [[ "$host" =~ '^[A-Za-z0-9._:-]+$' ]] || { print -u2 -- "Invalid host"; exit 64; }
          (( hops < 1 )) && hops=1; (( hops > 30 )) && hops=30
          /usr/sbin/traceroute -m "$hops" "$host"
          """#
      ),
      Specification(
        name: "custom_builtin_port_probe",
        description: "[AgenTM5N Built-in / Network] Test one TCP port with macOS netcat without sending application data.",
        parameters: [stringParameter("host", "Hostname or IP address."), integerParameter("port", "TCP port from 1 to 65535.", required: true)],
        source: #"""
          host="$AGENTM5N_ARG_HOST"
          port="$AGENTM5N_ARG_PORT"; port="${port%%.*}"
          [[ "$host" =~ '^[A-Za-z0-9._:-]+$' ]] || { print -u2 -- "Invalid host"; exit 64; }
          (( port >= 1 && port <= 65535 )) || { print -u2 -- "Invalid port"; exit 64; }
          /usr/bin/nc -G 5 -vz "$host" "$port"
          """#
      ),
    ]
  }

  private static var mcpSpecifications: [Specification] {
    let parameters = [
      stringParameter("command", "MCP server executable name or absolute executable path."),
      stringParameter("server_arguments_json", "JSON array of server CLI arguments. Defaults to [].", required: false),
      stringParameter("protocol_version", "MCP protocol version. Defaults to 2025-06-18; 2026-07-28 uses stateless request mode.", required: false),
      integerParameter("timeout", "Response timeout in seconds from 1 to 45."),
    ]

    let pythonPrefix = #"""
      PYTHON=""
      for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
        if [[ -x "$candidate" ]]; then PYTHON="$candidate"; break; fi
      done
      [[ -n "$PYTHON" ]] || { print -u2 -- "python3 is required for MCP stdio transport"; exit 127; }
      """#

    let sharedPython = #"""
import json
import os
import select
import shutil
import subprocess
import sys
import time

SEARCH_PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
command = os.environ["AGENTM5N_ARG_COMMAND"]
if "/" in command:
    executable = os.path.realpath(os.path.expanduser(command))
    allowed_roots = ("/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/", "/bin/", "/usr/sbin/", "/sbin/")
    if not any(executable.startswith(root) for root in allowed_roots):
        raise SystemExit("MCP executable path is outside approved CLI roots")
else:
    executable = shutil.which(command, path=SEARCH_PATH)
if not executable:
    raise SystemExit(f"MCP executable not found: {command}")

server_args = json.loads(os.environ.get("AGENTM5N_ARG_SERVER_ARGUMENTS_JSON", "[]") or "[]")
if not isinstance(server_args, list) or not all(isinstance(item, str) for item in server_args):
    raise SystemExit("server_arguments_json must be a JSON string array")
protocol = os.environ.get("AGENTM5N_ARG_PROTOCOL_VERSION", "2025-06-18") or "2025-06-18"
timeout_text = os.environ.get("AGENTM5N_ARG_TIMEOUT", "15").split(".", 1)[0]
timeout = max(1, min(int(timeout_text or "15"), 45))

process = subprocess.Popen(
    [executable, *server_args],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    text=True,
    bufsize=1,
    env={"PATH": SEARCH_PATH, "HOME": os.environ.get("HOME", "/tmp"), "TMPDIR": os.environ.get("TMPDIR", "/tmp")},
)

def send(message):
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()

def receive(request_id):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        remaining = max(0.05, deadline - time.monotonic())
        ready, _, _ = select.select([process.stdout], [], [], remaining)
        if not ready:
            continue
        line = process.stdout.readline()
        if not line:
            break
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("id") == request_id:
            return message
    raise TimeoutError(f"MCP request {request_id} timed out")

def initialize_if_needed():
    if protocol == "2026-07-28":
        return
    send({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": protocol,
            "capabilities": {},
            "clientInfo": {"name": "AgenTM5N", "version": "1.2.0"},
        },
    })
    response = receive(1)
    if "error" in response:
        raise RuntimeError(json.dumps(response["error"], ensure_ascii=False))
    send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

initialize_if_needed()
"""#

    let cleanupPython = #"""
finally:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            process.kill()
"""#

    let listSource = pythonPrefix + #"""
      "$PYTHON" - <<'PY'
"""# + sharedPython + #"""
try:
    request_id = 2
    params = {}
    if protocol == "2026-07-28":
        params["_meta"] = {"io.modelcontextprotocol/clientInfo": {"name": "AgenTM5N", "version": "1.2.0"}}
    send({"jsonrpc": "2.0", "id": request_id, "method": "tools/list", "params": params})
    response = receive(request_id)
    print(json.dumps(response, ensure_ascii=False, indent=2))
"""# + cleanupPython + #"""
PY
"""#

    let callSource = pythonPrefix + #"""
      "$PYTHON" - <<'PY'
"""# + sharedPython + #"""
try:
    tool_name = os.environ["AGENTM5N_ARG_TOOL"]
    tool_arguments = json.loads(os.environ.get("AGENTM5N_ARG_TOOL_ARGUMENTS_JSON", "{}") or "{}")
    if not isinstance(tool_arguments, dict):
        raise SystemExit("tool_arguments_json must be a JSON object")
    request_id = 2
    params = {"name": tool_name, "arguments": tool_arguments}
    if protocol == "2026-07-28":
        params["_meta"] = {"io.modelcontextprotocol/clientInfo": {"name": "AgenTM5N", "version": "1.2.0"}}
    send({"jsonrpc": "2.0", "id": request_id, "method": "tools/call", "params": params})
    response = receive(request_id)
    print(json.dumps(response, ensure_ascii=False, indent=2))
"""# + cleanupPython + #"""
PY
"""#

    return [
      Specification(
        name: "custom_builtin_mcp_stdio_list",
        description: "[AgenTM5N Built-in / MCP] Launch a local MCP stdio server without a shell and list its tools. Supports the 2025-06-18 initialization flow and the 2026-07-28 stateless request mode.",
        parameters: parameters,
        source: listSource
      ),
      Specification(
        name: "custom_builtin_mcp_stdio_call",
        description: "[AgenTM5N Built-in / MCP] Launch a local MCP stdio server without a shell and call one named MCP tool with JSON arguments.",
        parameters: parameters + [
          stringParameter("tool", "Exact MCP tool name."),
          stringParameter("tool_arguments_json", "JSON object passed as MCP tool arguments. Defaults to {}.", required: false),
        ],
        source: callSource
      ),
    ]
  }
}
