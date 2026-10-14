#!/usr/bin/env node

/** Prepare filesystem fixtures for the e2e tests. */
import { mkdir, rm, symlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const e2eDirectory = fileURLToPath(new URL("../e2etests/", import.meta.url));

for (const name of [
  ".git", ".mooncakes", ".xx", "_build", "node_modules", "target",
]) {
  const directory = path.join(e2eDirectory, "testdata", "skip-dirs", name);
  await mkdir(directory, { recursive: true });
  await writeFile(path.join(directory, "ignored.mbt"), "fn sample { target() }\n");
}

if (process.platform === "win32") {
  for (const [name, filename, content] of [
    ["fs-walk-scan.tmp", "hit.mbt", "///|\nfn sample {\n  target()\n}\n"],
    [
      "fs-walk-rules.tmp",
      "example.yaml",
      "id: example\ndescription: Windows junction rule.\npatterns:\n  - shape: target()\n",
    ],
  ]) {
    const directory = path.join(e2eDirectory, "windows", name);
    await rm(path.join(directory, "again"), { force: true });
    await rm(directory, { recursive: true, force: true });
    await mkdir(directory, { recursive: true });
    await writeFile(path.join(directory, filename), content);
    await symlink(directory, path.join(directory, "again"), "junction");
  }
}
