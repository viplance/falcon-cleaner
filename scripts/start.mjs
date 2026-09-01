import { access } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFile, spawn } from "node:child_process";
import { promisify } from "node:util";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, "..");
const executableName = "FalconCleaner";
const appBundle = join(root, "build", "Release", "Falcon Cleaner.app");
const execFileAsync = promisify(execFile);

function runCommand(command, args) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, {
      cwd: root,
      stdio: "inherit",
      env: process.env
    });

    child.on("exit", (code) => {
      if (code === 0) {
        resolvePromise();
      } else {
        reject(new Error(`${command} ${args.join(" ")} exited with code ${code}`));
      }
    });
    child.on("error", reject);
  });
}

async function main() {
  console.log("\n=== Falcon Cleaner: start ===\n");

  console.log("1) Stopping any running instance…");
  try {
    // Match the executable exactly so similarly named processes are left alone.
    await execFileAsync("pkill", ["-x", executableName]);
  } catch {
    // pkill returns 1 when FalconCleaner is not running.
  }

  console.log("2) Building…");
  await runCommand("npm", ["run", "build:app"]);

  try {
    await access(appBundle);
  } catch {
    throw new Error(`App bundle not found: ${appBundle}`);
  }

  console.log("\n3) Launching app…\n   → " + appBundle);
  await runCommand("open", [appBundle]);

  console.log("\nFalcon Cleaner is running.\n");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
