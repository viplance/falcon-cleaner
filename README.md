# Falcon Cleaner 🦅

Falcon Cleaner is a native, lightweight, and powerful macOS utility built with SwiftUI designed to help you thoroughly uninstall applications and keep your Mac running efficiently. It goes beyond just deleting the `.app` file—it comprehensively finds and cleans up associated orphaned files and uninstalls Homebrew packages seamlessly.

## ✨ Features

- **Standard App Cleanup**: Safely removes standard macOS `.app` applications along with all their hidden cache, preferences, and support files scattered throughout `~/Library`.
- **Homebrew Manager**: Detects installed Homebrew packages and services, allowing you to forcefully stop and cleanly uninstall them using your native `brew` environment.
- **Startup Script Control**: Scans for persistent LaunchAgents and LaunchDaemons (e.g., auto-updaters like Microsoft AutoUpdate) giving you back control to easily remove unwanted background services.
- **Deep Scanning**: Evaluates application footprints to give you a true calculation of the disk space that will be reclaimed.
- **Native Experience**: Written fully in Swift using SwiftUI for a highly responsive, modern native interface.

## 🛠 Building from Source

The project comes with a convenient set of NPM build scripts to easily compile the source into a distributable installation image (`.dmg`).

### Prerequisites
- macOS with **Xcode** (and Xcode Command Line Tools) installed.
- **Node.js** & **npm** (for the automated build scripts).

### Building

1. Clone the repository:
   ```bash
   git clone https://github.com/viplance/falcon-cleaner.git
   cd falcon-cleaner
   ```
2. Build the Xcode project and generate the `.dmg` installer:
   ```bash
   npm run build
   ```

*(Alternatively, you can run `npm run build:app` to just build the `.app` binary or `npm run build:dmg` to just generate the image from a successful build).*

Once finished, you will find `FalconCleaner.dmg` inside the `/build` directory.

## 🔒 Permissions & Security

Because Falcon Cleaner analyzes local system configurations and removes applications, it occasionally interfaces with standard AppleScript commands. If uninstalling certain protected packages or background LaunchDaemons, you may be natively prompted by macOS to input your Administrator password to authorize the cleanup.

## 📄 License

Check the `LICENSE` file in the repository (if applicable) for more details.
