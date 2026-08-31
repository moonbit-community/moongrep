# Windows rule loading behavior

## Rule-directory normalization

Rule directory lookup is case-insensitive and accepts mixed separators and dot
components. Recursive discovery ignores the uppercase `.YAML` fixture and
keeps slash-separated rule ids for the root and nested rules.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan --rules '.\TESTDATA//recursive-rule-discovery-rules\.\' testdata/recursive-rule-discovery-src
testdata\recursive-rule-discovery-src\hits.mbt:2:14-2:28
rule: example
description:
  Repeated equality.
source:
1 | fn sample {
2 >   let same = value == value
3 |   let x = get_user_input()
4 |   sink(x)

testdata\recursive-rule-discovery-src\hits.mbt:4:8-4:9
rule: nested/example
description:
  User input reaches sink.
source:
2 |   let same = value == value
3 |   let x = get_user_input()
4 >   sink(x)
5 | }
```

## Single-rule normalization

A normalized single-rule path loads only that file. Its rule id comes directly
from the YAML document and has no directory prefix.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; moonrun e2etests/moongrep.wasm -- scan --rule '.\testdata//recursive-rule-discovery-rules\nested\.\..\nested\\b.yml' testdata/recursive-rule-discovery-src
testdata\recursive-rule-discovery-src\hits.mbt:4:8-4:9
rule: example
description:
  User input reaches sink.
source:
2 |   let same = value == value
3 |   let x = get_user_input()
4 >   sink(x)
5 | }
```

## Case-sensitive rule suffix

Directory discovery ignores an uppercase `.YAML` suffix. Selecting the same
file explicitly rejects the suffix as invalid rule content with status 5
before its invalid pattern is compiled.

```mooncram
$ Set-Location "$env:TESTDIR/../.."; $ruleOutput = @(moonrun e2etests/moongrep.wasm -- scan --rule '.\testdata/recursive-rule-discovery-rules\ignored.YAML' testdata/recursive-rule-discovery-src 2>&1); $ruleStatus = $LASTEXITCODE; $ruleOutput | ForEach-Object { [Console]::Out.WriteLine([string]$_) }; $global:LASTEXITCODE = $ruleStatus
error: invalid rule
  source: testdata\recursive-rule-discovery-rules\ignored.YAML
  reason: unsupported rule file suffix
  help: fix the rule and try again
[5]
```
