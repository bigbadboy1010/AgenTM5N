# Security model

AgenTM5N is designed for a trusted personal workstation and intentionally
supports powerful local and remote operations. It does not treat unrestricted
access as equivalent to unprotected credential storage.

## Secret vault

- The complete vault payload is encrypted with AES-256-GCM.
- The encryption key is derived with PBKDF2-HMAC-SHA256.
- The KDF uses 600,000 iterations and a random 256-bit salt.
- The master password is retained only in process memory.
- Vault files and runtime credential files use restrictive POSIX permissions.

## SSH materialization

SSH private keys and ASKPASS helpers are materialized only for a session. The
runtime directory is purged during startup and session cleanup removes created
files. Unexpected process termination can still leave data until the next app
start, which is why the runtime directory is mode `0700`.

## Current limitations

- Clipboard copies are not automatically expired.
- Local JSON configuration and chat history are not encrypted.
- Ad-hoc app signing is intended only for local development.
- The application has no sandbox in the current MVP.
- Agent tool permissions are not implemented yet.

## Planned controls

- Confirm, Workspace Trusted and Full Access profiles
- tool-level allow, ask and deny rules
- structured audit events
- command timeout and output limits
- secret redaction before model requests and logs
- optional vault auto-lock
