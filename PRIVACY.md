# Privacy Policy

**Falcon Cleaner**

*Last updated: August 15, 2026*

## Overview

Falcon Cleaner is a macOS utility that uninstalls applications, removes their leftover
files, manages Homebrew packages and startup items, and reports disk usage. This policy
explains how the app handles your data.

## Data Collection

Falcon Cleaner **does not collect, store, transmit, or share any personal data**. Specifically:

- **No analytics or tracking** — the app contains no analytics frameworks, telemetry, or tracking code.
- **No network requests** — the app never connects to the internet. It operates entirely offline on your Mac.
- **No accounts or sign-in** — no registration or authentication is required.

## Local Processing

To do its job, Falcon Cleaner reads information that stays entirely on your Mac:

- Installed applications in `/Applications` and your user Applications folder
- Application support, cache and preference files under `~/Library`
- LaunchAgents and LaunchDaemons (startup items)
- Homebrew packages and services, when Homebrew is installed
- Running processes and their CPU and memory usage
- File and folder sizes on disks you choose to scan

This information is read on demand, used only to render the interface, and never written to
disk by the app or sent anywhere. Nothing is retained after you quit.

## Files You Delete

When you remove an application or file, Falcon Cleaner moves it to the Trash so the action
stays reversible. Some protected items — such as system-level LaunchDaemons or certain
Homebrew packages — require your administrator password, which macOS prompts for directly.
Falcon Cleaner never stores, records, or transmits your password.

## Permissions

Falcon Cleaner requests permission to send Apple events to Finder, which macOS uses to move
items to the Trash on your behalf. It may also request Full Disk Access so it can find
leftover files across your system. These permissions are granted by you in System Settings
and can be revoked at any time.

## Third-Party Services

Falcon Cleaner does not integrate with or send data to any third-party services.

## Children's Privacy

Falcon Cleaner does not collect any data from any users, including children under the age of 13.

## Changes to This Policy

If this privacy policy changes, the updated version will be posted here with a new
"Last updated" date.

## Contact

If you have questions about this privacy policy, please open an issue at
[github.com/viplance/falcon-cleaner](https://github.com/viplance/falcon-cleaner/issues).
