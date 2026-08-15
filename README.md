# Falcon Cleaner 🦅

Falcon Cleaner is a native, lightweight, and powerful macOS utility built with SwiftUI designed to help you thoroughly uninstall applications and keep your Mac running efficiently. It goes beyond just deleting the `.app` file—it comprehensively finds and cleans up associated orphaned files and uninstalls Homebrew packages seamlessly.

**Requires a Mac with Apple Silicon (M1 or later) running macOS 13.0 Ventura or later.**

## ✨ Features

- **Standard App Cleanup**: Safely removes standard macOS `.app` applications along with all their hidden cache, preferences, and support files scattered throughout `~/Library`.
- **Homebrew Manager**: Detects installed Homebrew packages and services, allowing you to forcefully stop and cleanly uninstall them using your native `brew` environment.
- **Startup Script Control**: Scans for persistent LaunchAgents and LaunchDaemons (e.g., auto-updaters like Microsoft AutoUpdate) giving you back control to easily remove unwanted background services.
- **Deep Scanning**: Evaluates application footprints to give you a true calculation of the disk space that will be reclaimed.
- **Native Experience**: Written fully in Swift using SwiftUI for a highly responsive, modern native interface.

## 🛠 Building from Source

### Prerequisites
- A Mac with **Apple Silicon** running macOS 13.0 or later.
- **Xcode** and the Xcode Command Line Tools.
- **Node.js** & **npm** (for the automated build scripts).

### Building

1. Clone the repository:
   ```bash
   git clone https://github.com/viplance/falcon-cleaner.git
   cd falcon-cleaner
   ```
2. Build an unsigned local build for testing:
   ```bash
   npm run release:local
   ```

Once finished, you will find `FalconCleaner.dmg` inside the `/build` directory.

## 🚀 Releasing

Falcon Cleaner is distributed **outside the Mac App Store**, signed with a Developer ID
certificate and notarized by Apple. The App Store is not an option: its mandatory sandbox
forbids uninstalling other applications, removing LaunchDaemons, terminating processes and
invoking Homebrew — which is the entirety of what this app does. This is the same route
taken by comparable utilities such as AppCleaner and CleanMyMac.

### One-time setup

1. Install your **Developer ID Application** certificate from the
   [Apple Developer portal](https://developer.apple.com/account/resources/certificates).
2. Create an [app-specific password](https://appleid.apple.com) and store notary credentials:
   ```bash
   xcrun notarytool store-credentials "falcon-notary" \
     --apple-id "your@appleid.com" \
     --team-id W37L5728Y6 \
     --password "xxxx-xxxx-xxxx-xxxx"
   ```

### Cutting a release

```bash
npm run release
```

This archives an Apple Silicon (arm64) Release build, exports it with Developer ID signing
and the hardened runtime, verifies the signature, architecture and entitlements, packages a DMG,
submits it to Apple's notary service, and staples the resulting ticket. The output DMG in
`/build` opens on any Mac without Gatekeeper warnings.

Bump `MARKETING_VERSION` (user-facing) and `CURRENT_PROJECT_VERSION` (build number) in the
Xcode project, along with `version` in `package.json`, before each release.

### App Store package (experimental)

```bash
npm run build:appstore
```

Produces `dist/FalconCleaner.pkg` for Transporter. **This build is heavily reduced.** The App
Store requires the App Sandbox, under which uninstalling applications, terminating processes,
running `brew`/`du`/`launchctl` and requesting administrator privileges are all denied. Those
paths are compiled out via `-DAPPSTORE` and the app is very likely to be rejected under App
Review guideline 2.4.5 / 4.2. Use the Developer ID flow above for the real product.

Requires an App Store provisioning profile for the bundle ID at
`~/Library/MobileDevice/Provisioning Profiles/FalconCleaner_App_Store.provisionprofile`, and
uses `FalconCleaner.AppStore.entitlements` (sandbox enabled, with the identifier entitlements
Transporter requires).

## 🔒 Permissions & Security

Falcon Cleaner runs **without the App Sandbox**, which its core features require. It is built
with Apple's **hardened runtime**, signed with a Developer ID certificate and notarized by
Apple, so macOS verifies on every launch that the app comes from a known developer and has not
been tampered with.

Because the app analyzes local system configurations and removes applications, it interfaces
with standard AppleScript commands. When uninstalling protected packages or background
LaunchDaemons, macOS will prompt you for your Administrator password to authorize the cleanup.
Deleted items are moved to the Trash, so removals remain reversible. For the most complete
results, grant Falcon Cleaner **Full Disk Access** in System Settings → Privacy & Security.

See [PRIVACY.md](PRIVACY.md) for the full privacy policy. In short: the app makes no network
requests and collects no data whatsoever.

## 📄 License

Check the `LICENSE` file in the repository (if applicable) for more details.
