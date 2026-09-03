#!/usr/bin/env node

/**
 * Cross-platform entry point for the repository's Moon Cram end-to-end tests.
 *
 * The runner builds the WebAssembly CLI, copies it beside the test fixtures,
 * selects the current platform's Markdown tests, and forwards all command-line
 * arguments to `moon-cram`.
 *
 * @file
 */

import { spawnSync } from "node:child_process";
import { copyFile, mkdtemp, readdir, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Absolute directory containing this script. */
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));

/** Project root used as the working directory for every child process. */
const projectRoot = path.resolve(scriptDirectory, "..");

/** Directory containing common and platform-specific Moon Cram fixtures. */
const e2eDirectory = path.join(projectRoot, "e2etests");

/** Artifact location referenced by the Moon Cram test commands. */
const wasmDestination = path.join(e2eDirectory, "moongrep.wasm");

/** Prefix for isolated Moon target directories created by this runner. */
const buildDirectoryPrefix = path.join(os.tmpdir(), "moongrep-e2e-");

/** Windows shell adapter that translates Moon Cram's Bash-oriented protocol. */
const powershellAdapter = path.join(
  scriptDirectory,
  "moon-cram-powershell.cmd",
);

/**
 * Describes a child-process failure while retaining a suitable process exit
 * code for this runner.
 */
class CommandError extends Error {
  /**
   * @param {string} message Human-readable failure description.
   * @param {number} [exitCode=1] Exit code to return from this runner.
   */
  constructor(message, exitCode = 1) {
    super(message);
    this.exitCode = exitCode;
  }
}

/**
 * Formats one command argument for diagnostic output.
 *
 * This representation is only printed to the console. The original argument
 * is still passed directly to `spawnSync`, so quoting cannot change execution.
 *
 * @param {string} argument Argument to render.
 * @returns {string} Readable representation of the argument.
 */
function displayArgument(argument) {
  return /[\s"]/u.test(argument) ? JSON.stringify(argument) : argument;
}

/**
 * Runs a command synchronously from the project root and forwards its standard
 * streams to the current terminal.
 *
 * @param {string} command Executable name or path.
 * @param {string[]} arguments_ Arguments passed to the executable unchanged.
 * @param {Record<string, string | undefined>} [env=process.env] Environment for
 * the child process.
 * @returns {void}
 * @throws {CommandError} If the command cannot start or exits unsuccessfully.
 */
function run(command, arguments_, env = process.env) {
  const displayedCommand = [command, ...arguments_]
    .map(displayArgument)
    .join(" ");
  console.log(`+ ${displayedCommand}`);

  const result = spawnSync(command, arguments_, {
    cwd: projectRoot,
    env,
    stdio: "inherit",
    windowsHide: true,
  });

  if (result.error) {
    throw new CommandError(`Unable to run ${command}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const detail = result.signal
      ? `signal ${result.signal}`
      : `exit code ${result.status}`;
    throw new CommandError(
      `${command} failed with ${detail}`,
      result.status ?? 1,
    );
  }
}

/**
 * Recursively finds regular files with an exact name below a directory.
 *
 * Moon's output layout has changed between toolchain versions, so the runner
 * deliberately treats the target directory as opaque instead of duplicating
 * Moon's internal path construction.
 *
 * @param {string} directory Directory to search.
 * @param {string} fileName Exact file name to find.
 * @returns {Promise<string[]>} Matching absolute paths in stable order.
 */
async function findFilesNamed(directory, fileName) {
  const entries = await readdir(directory, { withFileTypes: true });
  entries.sort((left, right) =>
    left.name < right.name ? -1 : left.name > right.name ? 1 : 0,
  );

  const matches = [];
  for (const entry of entries) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      matches.push(...(await findFilesNamed(entryPath, fileName)));
    } else if (entry.isFile() && entry.name === fileName) {
      matches.push(entryPath);
    }
  }
  return matches;
}

/**
 * Builds and installs the WebAssembly CLI used by the Markdown fixtures.
 *
 * A fresh target directory prevents artifacts from an older Moon layout from
 * masking a broken clean build. Requiring exactly one matching executable also
 * turns unexpected build-layout changes into an actionable error.
 *
 * @returns {Promise<void>}
 * @throws {CommandError} If the build has no unique `moongrep.wasm` artifact.
 */
async function buildWasmFixture() {
  const buildDirectory = await mkdtemp(buildDirectoryPrefix);
  try {
    run("moon", [
      "build",
      "--release",
      "--target",
      "wasm",
      "--target-dir",
      buildDirectory,
    ]);

    const artifacts = await findFilesNamed(buildDirectory, "moongrep.wasm");
    if (artifacts.length !== 1) {
      const detail =
        artifacts.length === 0
          ? "none were found"
          : `found ${artifacts.length}: ${artifacts.join(", ")}`;
      throw new CommandError(
        `Expected exactly one moongrep.wasm after moon build; ${detail}`,
      );
    }

    const wasmSource = artifacts[0];
    console.log(
      `+ copy ${displayArgument(wasmSource)} ` +
        displayArgument(path.relative(projectRoot, wasmDestination)),
    );
    await copyFile(wasmSource, wasmDestination);
  } finally {
    await rm(buildDirectory, {
      force: true,
      maxRetries: 3,
      recursive: true,
      retryDelay: 100,
    });
  }
}

/**
 * Finds Markdown tests directly inside a platform-specific fixture directory.
 * Results are sorted explicitly so execution order does not depend on the host
 * filesystem.
 *
 * @param {string} directory Absolute directory to inspect.
 * @returns {Promise<string[]>} Absolute paths of the discovered Markdown tests.
 * @throws {Error} If the directory cannot be read.
 */
async function listMarkdownTests(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  return entries
    .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
    .sort((left, right) =>
      left.name < right.name ? -1 : left.name > right.name ? 1 : 0,
    )
    .map((entry) => path.join(directory, entry.name));
}

/**
 * Builds the test artifact and runs the common plus platform-specific suites.
 *
 * On Windows, Moon Cram uses the bundled PowerShell protocol adapter. On Unix,
 * Moon Cram selects its normal shell. `MOON_CRAM_SHELL` can override either
 * choice when a specific shell is required for local testing.
 *
 * @returns {Promise<void>}
 * @throws {CommandError} If arguments are missing or a child command fails.
 * @throws {Error} If artifact copying or fixture discovery fails.
 */
async function main() {
  const moonCramArguments = process.argv.slice(2);
  if (
    moonCramArguments.length === 0 ||
    !["test", "update"].includes(moonCramArguments[0])
  ) {
    throw new CommandError(
      "Usage: node scripts/e2e.mjs <test|update> [moon-cram options]",
    );
  }

  const platformDirectory = path.join(
    e2eDirectory,
    process.platform === "win32" ? "windows" : "unix",
  );
  const tests = [
    path.join(e2eDirectory, "BASIC.md"),
    ...(await listMarkdownTests(platformDirectory)),
  ];

  const moonCramShell =
    process.env.MOON_CRAM_SHELL ??
    (process.platform === "win32" ? powershellAdapter : undefined);
  const shellArguments = moonCramShell
    ? ["--shell", moonCramShell]
    : [];

  await buildWasmFixture();
  const env = { ...process.env, NO_COLOR: "1" };

  for (const test of tests) {
    run(
      "moon-cram",
      [
        ...shellArguments,
        ...moonCramArguments,
        path.relative(projectRoot, test),
      ],
      env,
    );
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = error.exitCode ?? 1;
});
