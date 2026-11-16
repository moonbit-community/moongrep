# Project guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

## Project structure

- Each MoonBit package has its own directory and a `moon.pkg` file listing its
  dependencies. Blackbox tests use the `_test.mbt` suffix; whitebox tests use
  `_wbtest.mbt`.

- The root `moon.mod` file contains the module metadata.

## Coding convention

- Separate top-level MoonBit blocks with `///|`. Block order does not affect
  behavior, so some refactorings can handle each block independently.

- Keep deprecated blocks in each package's `deprecated.mbt` file when practical.

## Documentation style

- Use plain, straightforward prose.

## Tooling

- Use `moon fmt` to format code.

- Use `moon info` to update each package's generated `.mbti` interface file.
  An unchanged `.mbti` means the package's public interface has not changed,
  which is usually expected for a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check the tests. If a deliberate behavior change affects
  snapshots, run `moon test --update` to update them.

- Run the e2e tests from the project root (Bash):

  ```sh
  node scripts/setup-e2e.mjs
  export NO_COLOR=1 E2E_TEMP="$(mktemp -d)"
  moonx moonbit-community/mooncram@0.0.7 check e2etests/common e2etests/unix
  moonx moonbit-community/mooncram@0.0.7 test e2etests/common e2etests/unix
  rm -rf "$E2E_TEMP"
  ```

  Use `e2etests/windows` instead of `e2etests/unix` on Windows. Replace `test`
  with `update` to update the cram snapshots when the expected output changes.
  Each pipeline segment must use `moonx` with the full local package name,
  a pinned remote package coordinate, or a `.mbtx` script path. Set the working
  directory with `#cwd(path)` at the start of a block. Environment variables
  are inherited but are not expanded in command arguments.

- Run `moon check` to check for compiler diagnostics.

- Prefer `inspect` in tests, then run `moon test --update` to update snapshots.
  Use assertions such as `assert_eq` in loops where snapshots may vary. Run
  `moon coverage analyze > uncovered.log` to find code without test coverage.
