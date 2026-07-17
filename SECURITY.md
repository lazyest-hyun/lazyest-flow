# Security Policy

LazyestFlow is distributed as source code. Review the checkout before running `bootstrap.sh`; this project does not publish executable downloads or include an automatic updater.

## Reporting

Report suspected vulnerabilities through GitHub's private vulnerability reporting for this repository. Do not include secrets, private screenshots, configuration files, or exploit details in a public issue.

Include the affected commit, macOS version, reproduction steps, expected behavior, actual behavior, and the smallest non-sensitive proof needed to understand the issue.

## Scope

Security-sensitive surfaces include:

- build, packaging, installation, and removal paths
- Accessibility event taps and synthetic input
- screenshot provenance and clipboard publication
- Karabiner configuration preservation
- path- and CDHash-pinned XPC client validation for the privileged sleep helper
- `pmset disablesleep` ownership, rollback, and watchdog behavior
- user configuration parsing and runtime state reporting

The privileged helper is installed only after an explicit macOS administrator authorization. Its executable and launchd plist are root-owned at fixed system paths. The plist pins the current `/Applications/Lazyest Flow.app` CDHash and console-user UID. Every XPC connection must match that user, path, bundle identifier, valid running code, and pinned hash. This supports local and ad-hoc source builds without trusting an Apple Team ID.

The helper owns only the `pmset disablesleep` state marked by its root-only ownership file, stores no credentials, and restores normal sleep after a 90-second heartbeat failure. Installation, refresh, and removal accept no user-provided paths or shell fragments.

The project has no network service, telemetry, credential store, binary update channel, or bundled third-party package dependency.
