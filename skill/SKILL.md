---
name: moongrep
description: Create MoonBIt AST pattern matchers by generating JSON from MoonBit expressions with dump_expr and turning that JSON into match patterns. Use when building new AST queries
---

# Moongrep

## Overview

## Workflow

### 1. Write a pattern template

### 2. Dump JSON from the template

### 3. Convert JSON into a match pattern

Turn the JSON into a MoonBit pattern used in `match`:

- Keep the `kind` checks you care about.
- Replace literal meta names (e.g., `_ARRAY`) with pattern binds, usually `String(name)` for identifiers.
- Use `..` to ignore extra fields and `children` you do not need.
- Use `Null` to match JSON nulls (do not write `null`, which becomes a variable bind).
- Capture `loc` if you want to return locations.

### 4. Implement the matcher

## Notes
