/**
 * Falcon Cleaner — App Store (.pkg) build for Transporter.
 *
 * IMPORTANT — read before submitting:
 * The App Store requires the App Sandbox, under which Falcon Cleaner's core
 * features cannot work: uninstalling other applications, terminating processes,
 * running brew/du/launchctl, and requesting administrator privileges are all
 * denied. Those paths are compiled out via -DAPPSTORE. The resulting build is a
 * heavily reduced app and is very likely to be rejected under App Review
 * guideline 2.4.5 / 4.2 (minimum functionality). Ship build-release.mjs
 * (Developer ID + notarization) for the full-featured product.
 *
 * Build sequence and validation fixes follow the checklist learned from the
 * Openator submissions (Transporter errors 90788 / 90886 / 91109).
 *
 * Usage:  npm run build:appstore
 */

import { mkdir, rm, cp, access, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");

const appName = "Falcon Cleaner";
const scheme = "FalconCleaner";
const bundleId = "enotix.FalconCleaner";
const teamId = "W37L5728Y6";
const project = join(root, "FalconCleaner.xcodeproj");

const distDir = join(root, "dist");
const archivePath = join(distDir, "FalconCleaner-AppStore.xcarchive");
const exportDir = join(distDir, "appstore");
const exportedApp = join(exportDir, `${appName}.app`);
const pkgPath = join(distDir, "FalconCleaner.pkg");
const exportOptionsPath = join(distDir, "ExportOptions-AppStore.plist");
const entitlements = join(root, "FalconCleaner.AppStore.entitlements");

const signingIdentity = `Apple Distribution: Dzmitry Sharko (${teamId})`;
const installerIdentity = `3rd Party Mac Developer Installer: Dzmitry Sharko (${teamId})`;
const provisioningProfile = join(
  process.env.HOME,
  "Library/MobileDevice/Provisioning Profiles/FalconCleaner_App_Store.provisionprofile"
);

function run(command, args, options = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, { cwd: root, stdio: "inherit", ...options });
    child.on("exit", (code) =>
      code === 0
        ? resolvePromise()
        : reject(new Error(`${command} ${args.join(" ")} failed with code ${code}`))
    );
    child.on("error", reject);
  });
}

function capture(command, args) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, { cwd: root });
    let out = "";
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (out += d));
    child.on("exit", (code) =>
      code === 0 ? resolvePromise(out) : reject(new Error(out || `exit ${code}`))
    );
    child.on("error", reject);
  });
}

function step(n, label) {
  console.log(`\n${n}) ${label}`);
}

console.log("=== Falcon Cleaner — App Store (.pkg) Build ===");
console.log(
  "\nNOTE: the App Sandbox disables this app's privileged features.\n" +
    "      This package is very likely to be rejected under guideline 2.4.5 / 4.2.\n"
);

// --- Preflight -------------------------------------------------------------

step(0, "Preflight checks...");

const identities = await capture("security", ["find-identity", "-v"]);
for (const id of [signingIdentity, installerIdentity]) {
  if (!identities.includes(id)) {
    console.error(`ERROR: certificate not found in keychain:\n  ${id}`);
    console.error(`\nCreate it at https://developer.apple.com/account/resources/certificates`);
    process.exit(1);
  }
  console.log(`   ✓ ${id}`);
}

try {
  await access(provisioningProfile);
  console.log(`   ✓ provisioning profile`);
} catch {
  console.error(`\nERROR: App Store provisioning profile not found:\n  ${provisioningProfile}`);
  console.error(`\nCreate one at https://developer.apple.com/account/resources/profiles:`);
  console.error(`  1. Register an App ID for "${bundleId}" (team ${teamId})`);
  console.error(`  2. Create a "Mac App Store Connect" distribution profile for it`);
  console.error(`  3. Download it and save to the path above`);
  console.error(`\nThe bundle identifier in the profile must match exactly.`);
  process.exit(1);
}

await mkdir(distDir, { recursive: true });
await rm(archivePath, { recursive: true, force: true });
await rm(exportDir, { recursive: true, force: true });

// Transporter error 91109: quarantined files anywhere in the package are rejected.
step(1, "Stripping quarantine from provisioning profile...");
await run("xattr", ["-c", provisioningProfile]).catch(() => {});

// --- Archive ---------------------------------------------------------------

step(2, "Archiving sandboxed Release build (-DAPPSTORE)...");
await run("xcodebuild", [
  "-project", project,
  "-scheme", scheme,
  "-configuration", "Release",
  "-destination", "generic/platform=macOS",
  "-archivePath", archivePath,
  "archive",
  `DEVELOPMENT_TEAM=${teamId}`,
  "CODE_SIGN_STYLE=Manual",
  `CODE_SIGN_IDENTITY=${signingIdentity}`,
  `CODE_SIGN_ENTITLEMENTS=${entitlements}`,
  `PROVISIONING_PROFILE_SPECIFIER=FalconCleaner App Store`,
  "ENABLE_APP_SANDBOX=YES",
  "OTHER_SWIFT_FLAGS=$(inherited) -DAPPSTORE",
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) APPSTORE",
]);

// --- Export ----------------------------------------------------------------

step(3, "Exporting for App Store distribution...");
await writeFile(
  exportOptionsPath,
  `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>${teamId}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${bundleId}</key><string>FalconCleaner App Store</string>
  </dict>
</dict>
</plist>
`
);
await run("xcodebuild", [
  "-exportArchive",
  "-archivePath", archivePath,
  "-exportOptionsPlist", exportOptionsPath,
  "-exportPath", exportDir,
]);
const exportedPkg = join(exportDir, `${appName}.pkg`);
await access(exportedPkg);

step(4, "Stripping extended attributes from package (error 91109)...");
await run("xattr", ["-cr", exportedPkg]);

step(5, "Copying package to dist/...");
await rm(pkgPath, { force: true });
await cp(exportedPkg, pkgPath);

console.log("\n=== Done ===");
console.log(`Package: ${pkgPath}`);
console.log("\nUpload with Transporter, or:");
console.log(`  xcrun notarytool ... / xcrun altool --upload-app -f "${pkgPath}" -t macos \\`);
console.log(`    -u YOUR_APPLE_ID -p @keychain:AC_PASSWORD`);
console.log("\nBump CURRENT_PROJECT_VERSION before each new upload (must increase).");
