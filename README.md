# WinSysAuto
PowerShell module for Windows Server: inventory, patching, hardening, monitoring — one command, no agents.

## Security baselines

`functions/Set-SecurityBaseline.ps1` adds an idempotent entry point that reads a JSON or YAML baseline profile from the `baselines/` directory (or an explicit path) and enforces the desired firewall, Remote Desktop, password policy, and Microsoft Defender settings. The function honours `-WhatIf`/`-Confirm` semantics and returns a compliance summary so you can track which areas were already in the desired state.

### Usage

```powershell
Import-Module "$PSScriptRoot/functions/Set-SecurityBaseline.ps1"

# Apply the included sample baseline
Set-SecurityBaseline -Baseline 'SampleBaseline.json' -Verbose

# Apply a custom baseline file stored elsewhere
Set-SecurityBaseline -Baseline 'C:\Security\production-baseline.yaml' -WhatIf
```

### Baseline schema

Each baseline file is expected to follow this schema:

- `Name` / `Version` *(optional)*: metadata for your own tracking.
- `Firewall`: object with optional `Domain`, `Private`, and `Public` profiles. Each profile accepts any parameter supported by `Set-NetFirewallProfile` (for example `Enabled`, `DefaultInboundAction`, `DefaultOutboundAction`).
- `RemoteDesktop`: object controlling Terminal Services registry keys.
  - `Enable` *(boolean)*: enable (`true`) or disable (`false`) Remote Desktop connections.
  - `AllowOnlySecureConnections` *(boolean)*: enforce Network Level Authentication when `true`.
- `PasswordPolicy`: object mapped to `secedit.exe` `System Access` settings.
  - `MinimumPasswordLength`, `MaximumPasswordAgeDays`, `MinimumPasswordAgeDays`, `PasswordHistorySize` *(integers)*.
  - `ComplexityEnabled` *(boolean)*: toggles password complexity enforcement.
  - `LockoutThreshold`, `LockoutDurationMinutes`, `ResetLockoutCounterMinutes` *(integers)*.
- `Defender`: object mapped to `Set-MpPreference` parameters.
  - `RealTimeMonitoring` *(boolean)*: when `true`, keeps real-time protection enabled.
  - `CloudProtection` *(string)*: one of `Disabled`, `Basic`, or `Advanced` (`Enabled` is treated as `Advanced`).
  - `SampleSubmission` *(string)*: one of `Never`, `Prompt`, `SafeSamples`, `Always`, `Automatic`.
  - `SignatureUpdateIntervalHours` *(integer)*: applies to `SignatureScheduleInterval`.

See [`baselines/SampleBaseline.json`](baselines/SampleBaseline.json) for a full example profile.
