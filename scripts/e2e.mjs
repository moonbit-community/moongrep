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
import { copyFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

/** Absolute directory containing this script. */
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));

/** Project root used as the working directory for every child process. */
const projectRoot = path.resolve(scriptDirectory, "..");

/** Directory containing common and platform-specific Moon Cram fixtures. */
const e2eDirectory = path.join(projectRoot, "e2etests");

/** Release-mode WebAssembly artifact produced by `moon build`. */
const wasmSource = path.join(
  projectRoot,
  "_build",
  "wasm",
  "release",
  "build",
  "moongrep.wasm",
);

/** Artifact location referenced by the Moon Cram test commands. */
const wasmDestination = path.join(e2eDirectory, "moongrep.wasm");

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
 * Finds Markdown tests directly inside a platform-specific fixture directory.
 * Results are sorted explicitly so execution order does not depend on the host
 * filesystem.
 *
 * @param {string} directory Absolute directory to inspect.
 * @param {boolean} [optional=false] Whether a missing directory represents an
 * empty test set instead of an error.
 * @returns {Promise<string[]>} Absolute paths of the discovered Markdown tests.
 * @throws {Error} If the directory cannot be read and is not optional.
 */
async function listMarkdownTests(directory, optional = false) {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (optional && error.code === "ENOENT") {
      return [];
    }
    throw error;
  }

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
  if (moonCramArguments.length === 0) {
    throw new CommandError(
      "Usage: node scripts/e2e.mjs <test|update> [moon-cram options]",
    );
  }

  const moonCramShell =
    process.env.MOON_CRAM_SHELL ??
    (process.platform === "win32" ? powershellAdapter : undefined);
  const shellArguments = moonCramShell
    ? ["--shell", moonCramShell]
    : [];

  run("moon", ["build", "--release", "--target", "wasm"]);
  console.log(
    `+ copy ${displayArgument(path.relative(projectRoot, wasmSource))} ` +
      displayArgument(path.relative(projectRoot, wasmDestination)),
  );
  await copyFile(wasmSource, wasmDestination);

  const platformDirectory = path.join(
    e2eDirectory,
    process.platform === "win32" ? "windows" : "unix",
  );
  const tests = [
    path.join(e2eDirectory, "BASIC.md"),
    ...(await listMarkdownTests(
      platformDirectory,
      process.platform === "win32",
    )),
  ];
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
