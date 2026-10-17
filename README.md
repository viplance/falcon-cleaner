# Falcon Cleaner 🦅

Falcon Cleaner is a native, lightweight, and powerful macOS utility built with SwiftUI designed to help you thoroughly uninstall applications and keep your Mac running efficiently. It goes beyond just deleting the `.app` file—it comprehensively finds and cleans up associated orphaned files and uninstalls Homebrew packages seamlessly.

**Requires a Mac with Apple Silicon (M1 or later) running macOS 13.0 Ventura or later.**

## ✨ Features

- **Standard App Cleanup**: Safely removes standard macOS `.app` applications along with all their hidden cache, preferences, and support files scattered throughout `~/Library`.
- **Homebrew Manager**: Detects installed Homebrew packages and services, allowing you to forcefully stop and cleanly uninstall them using your native `brew` environment.
- **Startup Script Control**: Scans for persistent LaunchAgents and LaunchDaemons (e.g., auto-updaters like Microsoft AutoUpdate) giving you back control to easily remove unwanted background services.
- **Deep Scanning**: Evaluates application footprints to give you a true calculation of the disk space that will be reclaimed.
- **Refresh Controls**: Refresh Applications and Disk manually while preserving selections for items that still exist. Disk refresh recalculates folder sizes; process polling pauses when its window is inactive or minimized.
- **Pointer Feedback**: Enabled buttons, navigation, checkboxes, and clickable rows show a pointing-hand cursor, including on macOS 13 and 14.
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

Developer ID releases are signed and notarized for distribution outside the Mac App Store.
App Store builds use a separate sandboxed archive and distribution signing, as described below.

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

### App Store build and upload

Before each upload, increase `CURRENT_PROJECT_VERSION` in both Xcode configurations.
For a new user-facing version, also update `MARKETING_VERSION` and `version` in `package.json`.

The build requires the **Apple Distribution** and **3rd Party Mac Developer Installer**
certificates for team `W37L5728Y6`, an App Store provisioning profile at
`~/Library/MobileDevice/Provisioning Profiles/FalconCleaner_App_Store.provisionprofile`,
and the developer account signed in under **Xcode → Settings → Accounts**.

```bash
npm run build:appstore
```

Produces the signed `dist/FalconCleaner.pkg`, `dist/FalconCleaner-AppStore.xcarchive`, and
`dist/ExportOptions-AppStore.plist`. The bundle ID is `enotix.FalconCleaner`; the build uses
`FalconCleaner.AppStore.entitlements` and the `APPSTORE` compilation condition.

**Use the saved Xcode account to upload the archive.** This working workflow does not require
an API key or Issuer ID. Run these commands from the repository root after building:

```bash
python3 - <<'PY'
from pathlib import Path
import plistlib

options = plistlib.loads(Path('dist/ExportOptions-AppStore.plist').read_bytes())
options['destination'] = 'upload'
options['uploadSymbols'] = True
Path('dist/UploadOptions-AppStore.plist').write_bytes(plistlib.dumps(options))
PY

xcodebuild -exportArchive \
  -archivePath dist/FalconCleaner-AppStore.xcarchive \
  -exportOptionsPlist dist/UploadOptions-AppStore.plist \
  -allowProvisioningUpdates
```

Confirmed on October 11, 2026: **1.2.2 (5)** and **1.2.3 (6)** uploaded successfully through this workflow.
Check for `Upload succeeded.` and `EXPORT SUCCEEDED` in the command output. Apple's
`ContentDelivery.log`, inside the printed `.xcdistributionlogs` directory, reported
`UPLOAD SUCCEEDED with no errors` and `Upload State: PROCESSING` for that upload.
After processing, select the build in App Store Connect for review submission.

Signing credentials remain in Keychain/Xcode; do not commit passwords or private API keys.

## 🔒 Permissions & Security

The Developer ID build runs **without the App Sandbox**, with Apple's **hardened runtime**,
Developer ID signing, and notarization. The App Store build enables the App Sandbox, which
restricts access to other applications, system files, and privileged operations.
When you clean applications, the App Store build asks you to select their containing
folders in a macOS Open dialog before moving them to the Trash. Canceling leaves
that application's files intact; previously cleaned applications remain in the Trash.
Use **Include App Data…** before cleaning to grant access to your user Library and
rescan for accessible related files. Without this access, only the app bundles are
included. Grants last until you quit Falcon Cleaner and must be renewed next session.
The App Store build does not offer Homebrew, Startup, or Processes management and
asks you to quit a running application before cleaning it. Files requiring administrator
privileges cannot be removed by this build; failures remain visible for review.

The Developer ID build uses AppleScript for operations requiring additional permissions. When uninstalling protected packages or background
LaunchDaemons, macOS will prompt you for your Administrator password to authorize the cleanup.
Applications, related files, and items removed in Disk are moved to the Trash. Permanent
deletion is temporarily disabled, including for users who previously enabled it. Homebrew
packages are always uninstalled directly. For the most complete
results, grant Falcon Cleaner **Full Disk Access** in System Settings → Privacy & Security.

See [PRIVACY.md](PRIVACY.md) for the full privacy policy. In short: the app makes no network
requests and collects no data whatsoever.

## 📄 License

Check the `LICENSE` file in the repository (if applicable) for more details.

## App Store cleanup verification

Run the filesystem regression checks (only temporary fixtures are removed):

```bash
xcrun swiftc -DAPPSTORE FalconCleaner/CleanupFiles.swift FalconCleaner/SandboxFileAccess.swift Tests/CleanupFilesRegression.swift -o /tmp/falcon-cleanup-tests
/tmp/falcon-cleanup-tests
```

Before resubmitting, test the signed sandboxed package on a separate Mac/user account:

1. Install a disposable, user-owned app in Applications. Select it and click Clean Up.
   Confirm, allow access to Applications, and check that the actual bundle is in the Trash.
2. Cancel the folder-access dialog in a new session: the app must remain on disk and selected.
3. Use Include App Data… to select your real user Library. Create a disposable app preference
   fixture, refresh, and verify that both the app and its matched preference reach the Trash.
4. Try a running app and an item you cannot delete: a persistent error must explain the failure.
   A failed related file must not be reported as complete, even if the app bundle was moved.
5. Quit and relaunch: folder access must be requested again. Repeat after installing as an
   update to the previous App Store build. Test on macOS 27.0, the review environment.
