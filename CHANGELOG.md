# Changelog

All notable changes to AgenTM5N are documented in this file.

## [0.1.1] - 2026-08-06

### Fixed

- Build scripts now reject the incomplete Command Line Tools toolchain.
- Full Xcode installations are discovered automatically, including
  `~/Downloads/Xcode-beta.app`.
- The Metal compiler is verified before SwiftTerm is built.
- SwiftPM resource bundles are copied into the generated macOS application.

### Changed

- Product, executable, application bundle and persistence directory renamed
  from `MacAgentForge` to `AgenTM5N`.
- Project licensing aligned with Apache License 2.0.

## [0.1.0] - 2026-08-06

### Added

- SwiftUI desktop shell.
- Ollama Local and Ollama Cloud streaming providers.
- Apple Foundation Models provider.
- AES-256-GCM encrypted secret vault.
- Embedded SwiftTerm PTY and SSH host profiles.
- Core ML model loading with CPU and Apple Neural Engine compute units.
