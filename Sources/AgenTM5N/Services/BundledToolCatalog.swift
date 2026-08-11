import Foundation

/// Provider-neutral metadata for AgenTM5N-maintained Toolsmith tools.
///
/// The scripts themselves live in `BundledToolPackInstaller`. Keeping catalog
/// metadata outside the installer lets the central registry apply the same
/// capability, approval, telemetry and caching policy used by native tools.
public enum BundledToolCatalog {
  public static func entry(named name: String) -> AgentToolCatalogEntry? {
    let normalized = name.lowercased()

    switch normalized {
    case "custom_builtin_fs_stat", "custom_builtin_fs_sha256":
      return .init(name: normalized, capability: .workspace, risk: .read, cacheable: false)
    case "custom_builtin_fs_mkdir", "custom_builtin_fs_copy", "custom_builtin_fs_move",
      "custom_builtin_archive_create", "custom_builtin_archive_extract":
      return .init(name: normalized, capability: .workspace, risk: .write)

    case "custom_builtin_git_log", "custom_builtin_git_show":
      return .init(name: normalized, capability: .git, risk: .read)
    case "custom_builtin_git_fetch", "custom_builtin_git_pull_ff", "custom_builtin_git_push":
      return .init(name: normalized, capability: .git, risk: .execute)

    case "custom_builtin_docker_ps", "custom_builtin_docker_inspect",
      "custom_builtin_docker_logs", "custom_builtin_docker_stats",
      "custom_builtin_podman_ps", "custom_builtin_podman_inspect",
      "custom_builtin_podman_logs":
      return .init(name: normalized, capability: .system, risk: .read)
    case "custom_builtin_docker_action", "custom_builtin_docker_exec",
      "custom_builtin_podman_action":
      return .init(name: normalized, capability: .system, risk: .execute)

    case "custom_builtin_kube_contexts", "custom_builtin_kube_pods",
      "custom_builtin_kube_logs", "custom_builtin_kube_describe",
      "custom_builtin_kube_rollout_status", "custom_builtin_oc_project",
      "custom_builtin_oc_pods", "custom_builtin_oc_routes", "custom_builtin_oc_logs":
      return .init(name: normalized, capability: .system, risk: .read)
    case "custom_builtin_kube_apply":
      return .init(name: normalized, capability: .system, risk: .execute)

    case "custom_builtin_dns_lookup":
      return .init(name: normalized, capability: .system, risk: .read)
    case "custom_builtin_ping", "custom_builtin_traceroute", "custom_builtin_port_probe":
      return .init(name: normalized, capability: .system, risk: .execute)

    case "custom_builtin_mcp_stdio_list", "custom_builtin_mcp_stdio_call":
      return .init(name: normalized, capability: .terminal, risk: .execute)

    default:
      return nil
    }
  }
}
