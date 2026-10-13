# Subcommands without arguments

```mooncram-import
tee : cli/tee@0.2.0
cmp : cli/cmp@0.2.0
```

## moongrep subcommands without arguments

The `docs` and `dump` subcommands print their help when invoked without
arguments. `scan` and `lint` instead treat an omitted scan root as the current
directory. `scan` uses its default rules directory, while `lint` enables
builtin rules automatically.

The docs subcommand uses the same no-argument help behavior.

```mooncram moonbit-community/moongrep
$ moongrep docs --help | tee "${E2E_TEMP}/docs"
@STDOUT (ignore)
@STDERR (ignore)

$ moongrep docs | cmp "${E2E_TEMP}/docs" -
```

The dump subcommand also prints help instead of attempting to parse an empty
input.

```mooncram moonbit-community/moongrep
$ moongrep dump --help | tee "${E2E_TEMP}/dump"
@STDOUT (ignore)
@STDERR (ignore)

$ moongrep dump | cmp "${E2E_TEMP}/dump" -
```

Running bare `lint` from a fixture directory produces the same output as an
explicit current-directory lint target.

```mooncram moonbit-community/moongrep
$ set-current-working-directory ../testdata/builtin-rules
$ moongrep lint | tee "${E2E_TEMP}/lint"
@STDOUT (ignore)
@STDERR (ignore)

$ moongrep lint . | cmp "${E2E_TEMP}/lint" -
```
