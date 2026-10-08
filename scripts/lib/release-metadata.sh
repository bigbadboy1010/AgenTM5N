#!/bin/bash

# Single source of truth for AgenTM5N release metadata.
# Callers may override these values explicitly through AGENTM5N_VERSION and
# AGENTM5N_BUILD_NUMBER for controlled release experiments.
AGENTM5N_DEFAULT_VERSION="1.4.2"
AGENTM5N_DEFAULT_BUILD_NUMBER="42"

agentm5n_release_version() {
  printf '%s\n' "${AGENTM5N_VERSION:-$AGENTM5N_DEFAULT_VERSION}"
}

agentm5n_release_build_number() {
  printf '%s\n' "${AGENTM5N_BUILD_NUMBER:-$AGENTM5N_DEFAULT_BUILD_NUMBER}"
}

agentm5n_validate_release_metadata() {
  local version build
  version="$(agentm5n_release_version)"
  build="$(agentm5n_release_build_number)"

  case "$version" in
    ''|*[!0-9.]*|.*|*..*|*.)
      printf 'Ungültige AgenTM5N-Version: %s\n' "$version" >&2
      return 2
      ;;
  esac

  case "$build" in
    ''|*[!0-9]*)
      printf 'Ungültige AgenTM5N-Buildnummer: %s\n' "$build" >&2
      return 2
      ;;
  esac

  if [ "$build" -lt 1 ]; then
    printf 'AgenTM5N-Buildnummer muss größer als 0 sein: %s\n' "$build" >&2
    return 2
  fi
}
