# Token search

Repeated patterns retain separate results, shared prefixes and overlapping
matches. Starts sort before pattern input order, regardless of match length.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --pattern 'a a' --pattern='a a a' --pattern 'a a' testdata/tokscan/overlap.mbt
testdata/tokscan/overlap.mbt:1:1-1:4
pattern:
  a a
source:
1 > a a a

testdata/tokscan/overlap.mbt:1:1-1:6
pattern:
  a a a
source:
1 > a a a

testdata/tokscan/overlap.mbt:1:1-1:4
pattern:
  a a
source:
1 > a a a

testdata/tokscan/overlap.mbt:1:3-1:6
pattern:
  a a
source:
1 > a a a

testdata/tokscan/overlap.mbt:1:3-1:6
pattern:
  a a
source:
1 > a a a
```

Token search follows the same sorted depth-first traversal as scan and lint.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --pattern 'target()' testdata/stream-order
testdata/stream-order/a/hit.mbt:2:3-2:11
pattern:
  target()
source:
1 | fn nested {
2 >   target()
3 | }

testdata/stream-order/a.mbt:2:3-2:11
pattern:
  target()
source:
1 | fn flat {
2 >   target()
3 | }
```

An omitted root searches the current directory.

```mooncram
$ cd "$TESTDIR"/../../testdata/stream-order && diff -u <(moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --pattern 'target()') <(moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --pattern 'target()' .)
```

Matches cannot cross source blocks, even if a semicolon would join them.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --pattern 'a;b' testdata/tokscan/blocks.mbt
no match hits
```

Skip attributes are ordinary searchable tokens. Unicode columns and dot spans
are preserved when locations are rebased into the complete file.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --pattern 'target(1)' --pattern '#moongrep.skip' --pattern '.field' testdata/tokscan/blocks.mbt
testdata/tokscan/blocks.mbt:5:1-5:15
pattern:
  #moongrep.skip
source:
3 | b
4 | ///|
5 > #moongrep.skip
6 | target(1)
7 | ///|

testdata/tokscan/blocks.mbt:6:1-6:10
pattern:
  target(1)
source:
4 | ///|
5 | #moongrep.skip
6 > target(1)
7 | ///|
8 | "😀".field

testdata/tokscan/blocks.mbt:8:4-8:10
pattern:
  .field
source:
6 | target(1)
7 | ///|
8 > "😀".field
```

Top-level and nested lexical errors discard whole blocks and warn on stderr.
The final block is searched despite invalid syntax, and completion returns 0.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --pattern 'target(1)' --pattern 'let = + )' testdata/tokscan/warnings.mbt
testdata/tokscan/warnings.mbt:10:1-10:10
pattern:
  let = + )
source:
 8 | "\{$bad}"
 9 | ///|
10 > let = + )
11 | target ( 1 )

testdata/tokscan/warnings.mbt:11:1-11:13
pattern:
  target(1)
source:
 9 | ///|
10 | let = + )
11 > target ( 1 )
```

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --pattern 'absent' testdata/tokscan/warnings.mbt 2>&1 >/dev/null
warning: skipping testdata/tokscan/warnings.mbt block starting at line 1: lexing failed: line 2, column 1: unrecognized character u32: $
warning: skipping testdata/tokscan/warnings.mbt block starting at line 3: lexing failed: attribute #tag: line 1, column 2: unrecognized character u32: $
warning: skipping testdata/tokscan/warnings.mbt block starting at line 6: lexing failed: interpolation: line 1, column 1: unrecognized character u32: $
```

Validation happens before opening the root and reports the first bad pattern.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --pattern a --pattern '#tag($bad)' --pattern '' missing-root 2>&1
error: invalid tokscan pattern 2
  source: --pattern 2
  pattern:
    #tag($bad)
  reason: attribute #tag: line 1, column 2: unrecognized character u32: $
[2]
```

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --pattern= 2>&1
error: invalid tokscan pattern 1
  source: --pattern 1
  pattern:
  reason: pattern contains no tokens
[2]
```

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- tokscan src 2>&1
error: tokscan requires at least one --pattern
[2]
```

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --pattern a missing-tokscan-root 2>&1
error: could not access scan path
  source: missing-tokscan-root
  reason: No such file or directory
  help: check that the scan path exists and is readable
[6]
```

No arguments prints help successfully.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- tokscan >/dev/null && diff -u <(moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --help) <(moonrun "$TESTDIR"/../moongrep.wasm -- tokscan)
```

Symlink roots use their supplied path and cycles are visited only once.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --pattern 'target()' testdata/symlink/scan-dir-link
testdata/symlink/scan-dir-link/hit.mbt:3:3-3:11
pattern:
  target()
source:
1 | ///|
2 | fn sample {
3 >   target()
4 | }
```

For a fixed pattern, traversal visits the same files as scan with its
default exclusions.

```mooncram
$ cd "$TESTDIR"/../.. && diff -u <(moonrun e2etests/moongrep.wasm -- scan --pattern 'target()' testdata/exclude-dirs | sed -n '/^testdata.*:[0-9]/p') <(moonrun e2etests/moongrep.wasm -- tokscan --pattern 'target()' testdata/exclude-dirs | sed -n '/^testdata.*:[0-9]/p')
```

An output failure keeps status 7.

```mooncram
$ cd "$TESTDIR"/../.. && bash -o pipefail -c 'moonrun e2etests/moongrep.wasm -- tokscan --pattern "a" testdata/tokscan/overlap.mbt | head -n 0' 2>&1 >/dev/null
error: could not write output
  source: standard output
  reason: Broken pipe
  help: check the output destination or downstream command
[7]
```

Default exclusions skip hidden entries and build/dependency directories.
Explicit roots still search excluded names.

```mooncram
$ root="$TESTDIR/tokscan-walk.tmp"; mkdir -p "$root"/{.hidden,_build,node_modules,target}; trap 'rm -rf "$root"' EXIT; for name in hit.mbt .hidden.mbt .hidden/hit.mbt _build/hit.mbt node_modules/hit.mbt target/hit.mbt; do printf 'fn sample { target() }\n' > "$root/$name"; done; moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --pattern 'target()' "$root" | sed -n '/^pattern:$/p'; moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --pattern 'target()' "$root/.hidden.mbt" | sed -n '/^pattern:$/p'; moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --pattern 'target()' "$root/target" | sed -n '/^pattern:$/p'
pattern:
pattern:
pattern:
```

JSON preserves duplicate and overlapping findings on separate lines.

```mooncram
$ cd "$TESTDIR"/../.. && NO_COLOR=0 moonrun e2etests/moongrep.wasm -- tokscan --json --pattern 'a a' --pattern 'a a a' --pattern 'a a' testdata/tokscan/overlap.mbt
{"type":"finding","file":"testdata/tokscan/overlap.mbt","pattern":"a a","range":{"start":{"line":1,"column":1},"end":{"line":1,"column":4}},"matched_source":"a a","source_context":[{"line":1,"text":"a a a","is_match":true}]}
{"type":"finding","file":"testdata/tokscan/overlap.mbt","pattern":"a a a","range":{"start":{"line":1,"column":1},"end":{"line":1,"column":6}},"matched_source":"a a a","source_context":[{"line":1,"text":"a a a","is_match":true}]}
{"type":"finding","file":"testdata/tokscan/overlap.mbt","pattern":"a a","range":{"start":{"line":1,"column":1},"end":{"line":1,"column":4}},"matched_source":"a a","source_context":[{"line":1,"text":"a a a","is_match":true}]}
{"type":"finding","file":"testdata/tokscan/overlap.mbt","pattern":"a a","range":{"start":{"line":1,"column":3},"end":{"line":1,"column":6}},"matched_source":"a a","source_context":[{"line":1,"text":"a a a","is_match":true}]}
{"type":"finding","file":"testdata/tokscan/overlap.mbt","pattern":"a a","range":{"start":{"line":1,"column":3},"end":{"line":1,"column":6}},"matched_source":"a a","source_context":[{"line":1,"text":"a a a","is_match":true}]}
```

Unicode ranges use code point columns and context retains surrounding blocks.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --json --pattern '.field' testdata/tokscan/blocks.mbt
{"type":"finding","file":"testdata/tokscan/blocks.mbt","pattern":".field","range":{"start":{"line":8,"column":4},"end":{"line":8,"column":10}},"matched_source":".field","source_context":[{"line":6,"text":"target(1)","is_match":false},{"line":7,"text":"///|","is_match":false},{"line":8,"text":"\"😀\".field","is_match":true}]}
```

Recursive exclusions support names, paths, repeated options, and both value forms.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --exclude a --pattern 'target()' --json testdata/stream-order --exclude=./testdata/stream-order/a.mbt/
```

Explicit file and directory roots remain searchable even when excluded.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --exclude a.mbt --json --pattern 'target()' testdata/stream-order/a.mbt
{"type":"finding","file":"testdata/stream-order/a.mbt","pattern":"target()","range":{"start":{"line":2,"column":3},"end":{"line":2,"column":11}},"matched_source":"target()","source_context":[{"line":1,"text":"fn flat {","is_match":false},{"line":2,"text":"  target()","is_match":true},{"line":3,"text":"}","is_match":false}]}
```

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --exclude=./testdata/stream-order/a/ --json --pattern 'target()' testdata/stream-order/a
{"type":"finding","file":"testdata/stream-order/a/hit.mbt","pattern":"target()","range":{"start":{"line":2,"column":3},"end":{"line":2,"column":11}},"matched_source":"target()","source_context":[{"line":1,"text":"fn nested {","is_match":false},{"line":2,"text":"  target()","is_match":true},{"line":3,"text":"}","is_match":false}]}
```

Excluding the malformed file suppresses its warnings. With no findings, both
streams are empty.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --json --pattern absent --exclude warnings.mbt testdata/tokscan 2>&1
```

Lexical warnings stay on stderr while subsequent valid blocks produce findings
on stdout. Warnings without findings still exit successfully.

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --json --pattern 'target(1)' testdata/tokscan/warnings.mbt 2>/dev/null
{"type":"finding","file":"testdata/tokscan/warnings.mbt","pattern":"target(1)","range":{"start":{"line":11,"column":1},"end":{"line":11,"column":13}},"matched_source":"target ( 1 )","source_context":[{"line":9,"text":"///|","is_match":false},{"line":10,"text":"let = + )","is_match":false},{"line":11,"text":"target ( 1 )","is_match":true}]}
```

```mooncram
$ cd "$TESTDIR"/../.. && moonrun e2etests/moongrep.wasm -- tokscan --json --pattern absent testdata/tokscan/warnings.mbt 2>&1 >/dev/null
{"type":"warning","category":"lexical","message":"skipping testdata/tokscan/warnings.mbt block starting at line 1: lexing failed: line 2, column 1: unrecognized character u32: $","file":"testdata/tokscan/warnings.mbt","reason":"lexing failed: line 2, column 1: unrecognized character u32: $","block_start_line":1}
{"type":"warning","category":"lexical","message":"skipping testdata/tokscan/warnings.mbt block starting at line 3: lexing failed: attribute #tag: line 1, column 2: unrecognized character u32: $","file":"testdata/tokscan/warnings.mbt","reason":"lexing failed: attribute #tag: line 1, column 2: unrecognized character u32: $","block_start_line":3}
{"type":"warning","category":"lexical","message":"skipping testdata/tokscan/warnings.mbt block starting at line 6: lexing failed: interpolation: line 1, column 1: unrecognized character u32: $","file":"testdata/tokscan/warnings.mbt","reason":"lexing failed: interpolation: line 1, column 1: unrecognized character u32: $","block_start_line":6}
```

A malformed single-block file has no block_start_line field.

```mooncram
$ root="$TESTDIR/tokscan-single.tmp"; mkdir -p "$root"; trap 'rm -rf "$root"' EXIT; printf '$bad\n' > "$root/bad.mbt"; cd "$root" && moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --json --pattern a bad.mbt 2>&1
{"type":"warning","category":"lexical","message":"skipping bad.mbt: lexing failed: line 1, column 1: unrecognized character u32: $","file":"bad.mbt","reason":"lexing failed: line 1, column 1: unrecognized character u32: $"}
```

JSON mode applies to missing patterns, invalid patterns, and argparse failures.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --json 2>&1 >/dev/null
{"type":"error","category":"usage","exit_code":2,"message":"tokscan requires at least one --pattern"}
[2]
```

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --json --pattern a --pattern '$bad' missing-root 2>&1 >/dev/null
{"type":"error","category":"usage","exit_code":2,"message":"invalid tokscan pattern 2","source":"--pattern 2","pattern":"$bad","reason":"line 1, column 1: unrecognized character u32: $"}
[2]
```

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --unknown --json 2>&1 >/dev/null
{"type":"error","category":"usage","exit_code":2,"message":"error: unexpected argument '--unknown' found\n\nUsage: moongrep tokscan [options] [scan-root]\n\nScan MoonBit source files with token-level matching.\n\nArguments:\n  scan-root  Directory or .mbt file to scan.\n\nOptions:\n  -h, --help           Show help information.\n  --json               Write JSON Lines findings to stdout and diagnostics to stderr.\n  --pattern <pattern>  Token pattern to match. May be repeated.\n  --exclude <exclude>  File or directory name or path to skip while recursively scanning. May be repeated.\n"}
[2]
```

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --json --exclude 2>&1 >/dev/null
{"type":"error","category":"usage","exit_code":2,"message":"error: a value is required for '--exclude' but none was supplied\n\nUsage: moongrep tokscan [options] [scan-root]\n\nScan MoonBit source files with token-level matching.\n\nArguments:\n  scan-root  Directory or .mbt file to scan.\n\nOptions:\n  -h, --help           Show help information.\n  --json               Write JSON Lines findings to stdout and diagnostics to stderr.\n  --pattern <pattern>  Token pattern to match. May be repeated.\n  --exclude <exclude>  File or directory name or path to skip while recursively scanning. May be repeated.\n"}
[2]
```

Help stays ordinary text, and --json after the option terminator is a path.

```mooncram
$ diff -u <(moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --help) <(moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --json --help)
```

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- tokscan -- --json 2>&1 >/dev/null
error: tokscan requires at least one --pattern
[2]
```

File access failures and broken stdout/stderr pipes retain status 6 and 7.

```mooncram
$ moonrun "$TESTDIR"/../moongrep.wasm -- tokscan --json --pattern a missing-tokscan-root 2>&1 >/dev/null
{"type":"error","category":"scan_input","exit_code":6,"message":"could not access scan path","source":"missing-tokscan-root","reason":"No such file or directory","help":"check that the scan path exists and is readable"}
[6]
```

```mooncram
$ cd "$TESTDIR"/../.. && bash -o pipefail -c 'moonrun e2etests/moongrep.wasm -- tokscan --json --pattern a testdata/tokscan/overlap.mbt | head -n 0' 2>&1 >/dev/null
{"type":"error","category":"output","exit_code":7,"message":"could not write output","source":"standard output","reason":"Broken pipe","help":"check the output destination or downstream command"}
[7]
```

```mooncram
$ cd "$TESTDIR"/../.. && bash -o pipefail -c 'moonrun e2etests/moongrep.wasm -- tokscan --json --pattern absent testdata/tokscan/warnings.mbt 2>&1 >/dev/null | head -n 0'
[7]
```
