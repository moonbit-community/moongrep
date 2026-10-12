#!/usr/bin/env node

/**
 * Run the common and current platform's e2e tests with pinned mooncram.
 * Test blocks start in their Markdown file's directory and use ../testdata
 * and ../rules to access the shared fixtures from unix/ or windows/.
 */
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readdir, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
);
const e2eDirectory = path.join(projectRoot, "e2etests");
const skippedDirectories = [
  ".git", ".mooncakes", ".xx", "_build", "node_modules", "target",
];

async function listMarkdownTests(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
    .map((entry) => path.join(directory, entry.name))
    .sort();
}

/** Build the filesystem fixtures previously created by shell test commands. */
async function prepareFixtures() {
  const skipRoot = path.join(e2eDirectory, "testdata", "skip-dirs");
  for (const name of skippedDirectories) {
    const directory = path.join(skipRoot, name);
    await mkdir(directory, { recursive: true });
    await writeFile(path.join(directory, "ignored.mbt"), "fn sample { target() }\n");
  }
  if (process.platform === "win32") {
    const scanRoot = path.join(e2eDirectory, "windows", "fs-walk-scan.tmp");
    const rulesRoot = path.join(e2eDirectory, "windows", "fs-walk-rules.tmp");
    await mkdir(scanRoot, { recursive: true });
    await writeFile(
      path.join(scanRoot, "hit.mbt"),
      "///|\nfn sample {\n  target()\n}\n",
    );
    await symlink(scanRoot, path.join(scanRoot, "again"), "junction");
    await mkdir(rulesRoot, { recursive: true });
    await writeFile(
      path.join(rulesRoot, "example.yaml"),
      "id: example\ndescription: Windows junction rule.\npatterns:\n  - shape: target()\n",
    );
    await symlink(rulesRoot, path.join(rulesRoot, "again"), "junction");
  }
}

async function cleanFixtures() {
  for (const name of skippedDirectories) {
    await rm(path.join(e2eDirectory, "testdata", "skip-dirs", name), {
      recursive: true,
      force: true,
    });
  }
  if (process.platform === "win32") {
    for (const name of ["fs-walk-scan.tmp", "fs-walk-rules.tmp"]) {
      const directory = path.join(e2eDirectory, "windows", name);
      await rm(path.join(directory, "again"), { force: true });
      await rm(directory, { recursive: true, force: true });
    }
  }
}

async function main() {
  const arguments_ = process.argv.slice(2);
  if (!["test", "update"].includes(arguments_[0])) {
    throw new Error("Usage: node scripts/e2e.mjs <test|update> [mooncram options]");
  }
  const platformDirectory = path.join(
    e2eDirectory,
    process.platform === "win32" ? "windows" : "unix",
  );
  const tests = [
    path.join(e2eDirectory, "BASIC.md"),
    ...(await listMarkdownTests(platformDirectory)),
  ].map((file) => path.relative(projectRoot, file));
  const temporaryDirectory = await mkdtemp(
    path.join(os.tmpdir(), "moongrep-e2e-"),
  );
  try {
    await cleanFixtures();
    await prepareFixtures();
    const command = ["moonbit-community/mooncram@0.0.4", ...arguments_, ...tests];
    console.log(`+ moonx ${command.join(" ")}`);
    const result = spawnSync("moonx", command, {
      cwd: projectRoot,
      env: { ...process.env, NO_COLOR: "1", E2E_TEMP: temporaryDirectory },
      stdio: "inherit",
      windowsHide: true,
    });
    if (result.error) throw result.error;
    if (result.signal) throw new Error(`mooncram terminated by ${result.signal}`);
    process.exitCode = result.status ?? 1;
  } finally {
    await cleanFixtures();
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
