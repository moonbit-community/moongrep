name = "moonbit-community/moongrep"

version = "0.1.18"

preferred_target = "wasm"

import {
  "moonbitlang/parser@0.3.18",
  "moonbit-community/yaml@0.0.6",
  "moonbit-community/chalk@0.0.1",
  "moonbitlang/lexer@0.3.15",
  "moonbitlang/async@0.20.2",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/moongrep"

license = "Apache-2.0"

keywords = [ "linter", "grep", "refactoring", "static-analysis" ]

description = "Experimental MoonBit structural search and taint-analysis tool"

options(
  exclude: [ "testdata", "e2etest" ],
)
