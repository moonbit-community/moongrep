# moongrep

An experimental Moonbit code structural search library (based on AST pattern matching).

**Note**: moongrep is designed as a programmable MoonBit structured search tool for Coding Agents. Since LLMs aren't that picky about exact location, the locations it returns might be a bit wider/narrower than they actually are.

## Usage

**Warning**: Due to the current AST structure lacking some source location information, this library is not yet ready for practical use.

For example usage, please see: [example](./src/astgrep_wbtest.mbt)