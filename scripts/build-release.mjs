/**
 * Falcon Cleaner — Developer ID release pipeline.
 *
 * Produces a signed, notarized and stapled DMG suitable for public distribution
 * outside the Mac App Store. Falcon Cleaner cannot ship on the App Store: its
 * core features (uninstalling apps, removing LaunchDaemons, killing processes,
 * driving Homebrew) are all forbidden by the mandatory App Store sandbox.
 *
 * Usage:  npm run release
 *         npm run release -- --skip-notarize     (local smoke test)
 */

import { mkdir, rm, cp, access, readFile, writeFile, symlink } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");

// Bundle name (PRODUCT_NAME) differs from the scheme/target name.
const appName = "Falcon Cleaner";
const dmgName = "FalconCleaner";
const volumeName = "Falcon Cleaner";
const scheme = "FalconCleaner";
const project = join(root, "FalconCleaner.xcodeproj");

const buildDir = join(root, "build");
const archivePath = join(buildDir, `${dmgName}.xcarchive`);
const exportDir = join(buildDir, "export");
const exportedApp = join(exportDir, `${appName}.app`);
const dmgStaging = join(buildDir, "dmg");
const dmgPath = join(buildDir, `${dmgName}.dmg`);
const exportOptionsPath = join(buildDir, "ExportOptions.plist");

const teamId = "W37L5728Y6";
const signingIdentity = `Developer ID Application: Dzmitry Sharko (${teamId})`;
const notaryProfile = process.env.NOTARY_PROFILE || "falcon-notary";

const skipNotarize = process.argv.includes("--skip-notarize");

function run(command, args, options = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, { cwd: root, stdio: "inherit", ...options });
    child.on("exit", (code) => {
      if (code === 0) return resolvePromise();
      reject(new Error(`${command} ${args.join(" ")} failed with code ${code}`));
    });
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

console.log("=== Falcon Cleaner — Developer ID Release ===");

// --- Preflight -------------------------------------------------------------

step("0", "Preflight checks...");

const identities = await capture("security", ["find-identity", "-v", "-p", "codesigning"]);
if (!identities.includes(signingIdentity)) {
  console.error(`ERROR: signing identity not found in keychain:\n  ${signingIdentity}`);
  console.error(`\nInstall your Developer ID Application certificate from`);
  console.error(`https://developer.apple.com/account/resources/certificates`);
  process.exit(1);
}
console.log(`   ✓ ${signingIdentity}`);

if (!skipNotarize) {
  try {
    await capture("xcrun", ["notarytool", "history", "--keychain-profile", notaryProfile]);
    console.log(`   ✓ notary profile "${notaryProfile}"`);
  } catch {
    console.error(`ERROR: no notarytool keychain profile named "${notaryProfile}".`);
    console.error(`\nCreate one once with an app-specific password from appleid.apple.com:`);
    console.error(
      `\n  xcrun notarytool store-credentials "${notaryProfile}" \\\n` +
        `    --apple-id "your@appleid.com" \\\n` +
        `    --team-id ${teamId} \\\n` +
        `    --password "xxxx-xxxx-xxxx-xxxx"\n`
    );
    console.error(`Or run with --skip-notarize to produce an unnotarized local build.`);
    process.exit(1);
  }
}

// --- Archive ---------------------------------------------------------------

await rm(archivePath, { recursive: true, force: true });
await rm(exportDir, { recursive: true, force: true });
await mkdir(buildDir, { recursive: true });

step(1, "Archiving Release build...");
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
  "ENABLE_HARDENED_RUNTIME=YES",
]);

// --- Export ----------------------------------------------------------------

step(2, "Exporting Developer ID app...");
await writeFile(
  exportOptionsPath,
  `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${teamId}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>${signingIdentity}</string>
  <key>destination</key><string>export</string>
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

await access(exportedApp);

// --- Verify signature ------------------------------------------------------

step(3, "Verifying signature and hardened runtime...");
await run("codesign", ["--verify", "--deep", "--strict", "--verbose=2", exportedApp]);

const signInfo = await capture("codesign", ["-d", "--verbose=4", exportedApp]);
if (!/flags=.*runtime/.test(signInfo)) {
  console.error("ERROR: hardened runtime flag missing — notarization would be rejected.");
  process.exit(1);
}
console.log("   ✓ hardened runtime enabled");

// Apple Silicon only — guard against ARCHS regressing back to universal.
const archs = (
  await capture("lipo", ["-archs", join(exportedApp, "Contents", "MacOS", scheme)])
).trim();
if (archs !== "arm64") {
  console.error(`ERROR: expected an arm64-only binary, got "${archs}".`);
  process.exit(1);
}
console.log("   ✓ arm64 only");

await run("codesign", ["-d", "--entitlements", "-", "--xml", exportedApp]);

// --- DMG -------------------------------------------------------------------

step(4, "Building DMG...");
await rm(dmgStaging, { recursive: true, force: true });
await rm(dmgPath, { force: true });
await mkdir(dmgStaging, { recursive: true });
await cp(exportedApp, join(dmgStaging, `${appName}.app`), { recursive: true });
await symlink("/Applications", join(dmgStaging, "Applications"));

await run("hdiutil", [
  "create",
  "-volname", volumeName,
  "-srcfolder", dmgStaging,
  "-ov",
  "-format", "UDZO",
  dmgPath,
]);
await rm(dmgStaging, { recursive: true, force: true });

step(5, "Signing DMG...");
await run("codesign", ["--force", "--sign", signingIdentity, dmgPath]);

// --- Notarize --------------------------------------------------------------

if (skipNotarize) {
  console.log("\n=== Done (unnotarized) ===");
  console.log(`DMG: ${dmgPath}`);
  console.log("\nWARNING: this build is NOT notarized and Gatekeeper will block it");
  console.log("on other Macs. Use it for local testing only.");
} else {
  step(6, "Submitting to Apple notary service (this can take several minutes)...");
  await run("xcrun", [
    "notarytool", "submit", dmgPath,
    "--keychain-profile", notaryProfile,
    "--wait",
  ]);

  step(7, "Stapling notarization ticket...");
  await run("xcrun", ["stapler", "staple", dmgPath]);

  step(8, "Validating Gatekeeper acceptance...");
  await run("xcrun", ["stapler", "validate", dmgPath]);
  await run("spctl", ["-a", "-vvv", "-t", "install", exportedApp]);

  const version = JSON.parse(await readFile(join(root, "package.json"), "utf8")).version;
  console.log("\n=== Done ===");
  console.log(`Signed, notarized, stapled DMG (v${version}):`);
  console.log(`  ${dmgPath}`);
  console.log("\nThis DMG is ready to publish. Users can open it without Gatekeeper warnings.");
}
