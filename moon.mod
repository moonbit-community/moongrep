name = "moonbit-community/moongrep"

version = "0.1.12"

preferred_target = "wasm"

import {
  "moonbitlang/parser@0.3.7",
  "moonbit-community/yaml@0.0.4",
  "moonbit-community/chalk@0.0.1",
  "moonbitlang/lexer@0.3.7",
  "moonbitlang/async@0.20.1",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/moongrep"

license = "Apache-2.0"

keywords = [ "linter", "grep", "refactoring", "static-analysis" ]

description = "Experimental MoonBit structural search and taint-analysis tool"

options(
  exclude: [ "testdata", "e2etest" ],
)
