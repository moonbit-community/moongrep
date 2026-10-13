# Ellipsis metavariables

```mooncram-import
jq : cli/jq@0.2.1
```

The matching snapshots below print only the matched source to keep positive and
near-miss cases readable.

## Empty, single, and multiple items

An argument ellipsis accepts any number of complete arguments, including zero,
and preserves the entire matched call as the result.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'inspect($$$args)' ../testdata/ellipsis/sample.mbt | jq -r '.matched_source | @json | .[1:-1]'
inspect()
inspect(1)
inspect(1, content=\"1\")
```

Fixed items on both sides of an ellipsis remain exact anchors. The middle
capture may be empty or contain several arguments, while calls with a different
prefix or suffix do not match.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'anchored(prefix, $$$middle, suffix)' ../testdata/ellipsis/sample.mbt | jq -r '.matched_source | @json | .[1:-1]'
anchored(prefix, suffix)
anchored(prefix, first, second, suffix)
```

## Backtracking and binding equality

Later fixed items can force an ellipsis matcher to reconsider an earlier split.
Only the call that can consume both markers and the full argument list is
accepted.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'split($$$left, marker, $$$right, marker)' ../testdata/ellipsis/bindings.mbt | jq -r '.matched_source | @json | .[1:-1]'
split(a, marker, b, marker)
```

Repeated named ellipses must capture structurally equal sequences. Equality
holds for both empty and multi-item arrays; unequal sequences are omitted.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'repeated([$$$items], [$$$items])' ../testdata/ellipsis/bindings.mbt | jq -r '.matched_source | @json | .[1:-1]'
repeated([], [])
repeated([a, b], [a, b])
```

Argument labels are part of a captured sequence. Reusing the capture across
two calls succeeds only when positional values, labels, and values all agree.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'arguments_equal(left($$$args), right($$$args))' ../testdata/ellipsis/bindings.mbt | jq -r '.matched_source | @json | .[1:-1]'
arguments_equal(left(1, label=2), right(1, label=2))
```

The anonymous ellipsis `$$$_` does not bind a reusable value. Its two
occurrences can therefore consume different sequences.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'anonymous([$$$_], [$$$_])' ../testdata/ellipsis/bindings.mbt | jq -r '.matched_source | @json | .[1:-1]'
anonymous([a], [b, c])
```

Anonymous ellipses can still constrain item kinds independently. Here the
first array must contain constants and the second must contain identifiers.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'typed_anonymous([$$$(_:const)], [$$$(_:id)])' ../testdata/ellipsis/bindings.mbt | jq -r '.matched_source | @json | .[1:-1]'
typed_anonymous([1, 2], [a, b])
```

A kind declared on the first occurrence of a named ellipsis also applies when
the same name is reused in shorthand form. Only equal constant sequences
match.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'propagated([$$$(items:const)], [$$$items])' ../testdata/ellipsis/bindings.mbt | jq -r '.matched_source | @json | .[1:-1]'
propagated([1, 2], [1, 2])
```

Backtracking over an ellipsis must preserve ordinary metavariable bindings.
The final expression therefore has to equal the earlier captured `value`.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'restore($$$gap, $(value:exp), marker, $(value:exp))' ../testdata/ellipsis/bindings.mbt | jq -r '.matched_source | @json | .[1:-1]'
restore(first, selected, marker, selected)
```

## Typed call arguments

Bare and `arg` ellipses accept every complete argument kind. The `exp`, `id`,
and `const` forms accept only compatible positional argument values.

The explicit `arg` kind accepts positional, labelled, punned, and optional
arguments, as well as an empty argument list.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'any_args($$$(args:arg))' ../testdata/ellipsis/arguments.mbt | jq -r '.matched_source | @json | .[1:-1]'
any_args()
any_args(value, other)
any_args(value, label=other)
any_args(label~)
any_args(label?=other)
any_args(label?)
```

An `exp` argument ellipsis accepts only positional expression values. Labelled
and punned arguments in the fixture are not reported.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'exp_args($$$(args:exp))' ../testdata/ellipsis/arguments.mbt | jq -r '.matched_source | @json | .[1:-1]'
exp_args()
exp_args(value, other + 1)
```

An `id` argument ellipsis narrows positional values further to identifiers,
excluding constants and labelled arguments.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'id_args($$$(args:id))' ../testdata/ellipsis/arguments.mbt | jq -r '.matched_source | @json | .[1:-1]'
id_args()
id_args(value, other)
```

A `const` argument ellipsis accepts literal positional values, excluding
identifier values and labelled constants.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'const_args($$$(args:const))' ../testdata/ellipsis/arguments.mbt | jq -r '.matched_source | @json | .[1:-1]'
const_args()
const_args(1, \"two\")
```

## Ordered CST list positions

The array fixture also contains a spread element; both the bare and `exp`
patterns below intentionally match only the regular-element array.

Ellipses work in tuple element lists. A fixed trailing element anchors the
capture and prevents a tuple with a different tail from matching.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'tuple_expr(($$$(items:exp), tail))' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
tuple_expr((first, second, tail))
```

Block statements are ordered list items as well. The ellipsis consumes the
leading statements, while the final `tail` expression remains fixed.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'if condition { $$$items; tail }' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
if condition {\n    before()\n    middle()\n    tail\n  }
```

An `exp` ellipsis captures regular array elements. It does not consume the
spread element in the second array from the fixture.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'array_expr([$$$(items:exp)])' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
array_expr([first, second])
```

The bare array ellipsis has the same complete-item requirement, so it also
matches only the array made entirely of regular elements.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'array_expr([$$$items])' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
array_expr([first, second])
```

A `pat` ellipsis captures the leading tuple patterns before the fixed `tail`
pattern.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'match tuple_input { ($$$(items:pat), tail) => tuple_pattern }' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
match tuple_input { (first, second, tail) => tuple_pattern }
```

Constructor pattern arguments form another ordered pattern list and can be
captured together by a `pat` ellipsis.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'match constructor_input { Some($$$(items:pat)) => constructor_pattern }' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
match constructor_input { Some(first, second) => constructor_pattern }
```

Array pattern lists accept all pattern forms under the `pat` kind, including
identifiers, wildcards, and constants.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'match array_input { [$$$(items:pat)] => array_pattern }' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
match array_input { [first, _, 1] => array_pattern }
```

An `id` ellipsis in an array pattern accepts only identifier patterns. The
fixture containing a constant is excluded.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'match id_input { [$$$(items:id)] => id_patterns }' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
match id_input { [first, second] => id_patterns }
```

A `const` ellipsis in the same position accepts only constant patterns. The
fixture containing an identifier is excluded.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'match const_input { [$$$(items:const)] => const_patterns }' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
match const_input { [1, \"two\"] => const_patterns }
```

Type tuple elements can be captured with a `type` ellipsis while a fixed final
type anchors the end of the tuple.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'let value : ($$$(Types:type), Bool) = input' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
let value : (Int, String, Bool) = input
```

Function parameter lists support ellipses across positional, labelled,
defaulted, and optional parameters. The same pattern also accepts an empty
parameter list.

```mooncram moonbit-community/moongrep
$ moongrep scan --json --pattern 'fn($$$(params:id)) { body }' ../testdata/ellipsis/ordered_lists.mbt | jq -r '.matched_source | @json | .[1:-1]'
fn(\n    positional,\n    labelled~ : Int,\n    optional~ : Int = 1,\n    question? : String,\n  ) { body }
fn() { body }
```

## Validation errors

Ellipses must occupy a complete unnamed ordered-list item.

A standalone ellipsis is an expression position rather than an item inside an
ordered CST list, so it is rejected during rule validation.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '$$$items' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    $$$items
  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
  help: fix the pattern passed to --pattern and try again
[5]
```

Grouping parentheses do not make their single contents a replaceable ordered
list. Bare, typed, and nested grouped ellipses are rejected.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '($$$items)' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    ($$$items)
  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
  help: fix the pattern passed to --pattern and try again
[5]
```

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '($$$(values:exp))' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    ($$$(values:exp))
  reason: the pattern uses ellipsis metavar $$$(values:exp) outside a complete ordered CST list item
  help: fix the pattern passed to --pattern and try again
[5]
```

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern '(($$$items))' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    (($$$items))
  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
  help: fix the pattern passed to --pattern and try again
[5]
```

Embedding an ellipsis inside a larger arithmetic expression also makes it only
part of a list item and is invalid.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'wrap($$$items + 1)' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    wrap($$$items + 1)
  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
  help: fix the pattern passed to --pattern and try again
[5]
```

A labelled argument value is not an unnamed argument item. An ellipsis cannot
be used as only the value of that labelled argument.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'sink(label=$$$items)' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    sink(label=$$$items)
  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
  help: fix the pattern passed to --pattern and try again
[5]
```

The final expression of a block is not a replaceable statement sequence. A
bare ellipsis in that position must therefore be rejected.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'if condition { $$$items }' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    if condition { $$$items }
  reason: the pattern uses ellipsis metavar $$$items outside a complete ordered CST list item
  help: fix the pattern passed to --pattern and try again
[5]
```

Malformed spellings and unsupported kinds are rejected.

An ellipsis needs either a name or the explicit anonymous spelling `$$$_`.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'inspect($$$)' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    inspect($$$)
  reason: the pattern has invalid metavar syntax $$; use explicit typed syntax like $(value:exp)
  help: fix the pattern passed to --pattern and try again
[5]
```

Parenthesized ellipsis syntax must include a kind after the name; an untyped
`$$$(items)` form is not accepted.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'inspect($$$(items))' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    inspect($$$(items))
  reason: the pattern has invalid metavar syntax $$$(items); use explicit typed syntax like $(value:exp)
  help: fix the pattern passed to --pattern and try again
[5]
```

Typed ellipses validate their kind names and report an unsupported kind before
the scan starts.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'inspect($$$(items:unknown))' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    inspect($$$(items:unknown))
  reason: the pattern contains unsupported ellipsis metavar kind unknown
  help: fix the pattern passed to --pattern and try again
[5]
```

Typed ellipses must be compatible with their list slot.

A call argument list cannot contain a `type` ellipsis because its items are
arguments, not types.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'sink($$$(items:type))' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    sink($$$(items:type))
  reason: the pattern uses ellipsis kind type in an incompatible ordered-list item position
  help: fix the pattern passed to --pattern and try again
[5]
```

A function parameter list cannot contain an `exp` ellipsis because parameters
are not expression items.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'fn($$$(items:exp)) { body }' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    fn($$$(items:exp)) { body }
  reason: the pattern uses ellipsis kind exp in an incompatible ordered-list item position
  help: fix the pattern passed to --pattern and try again
[5]
```

An array pattern list likewise rejects an `exp` ellipsis and requires a pattern
compatible kind.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'match input { [$$$(items:exp)] => body }' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    match input { [$$$(items:exp)] => body }
  reason: the pattern uses ellipsis kind exp in an incompatible ordered-list item position
  help: fix the pattern passed to --pattern and try again
[5]
```

Names cannot mix capture forms, kinds, reserved names, or guards.

One name cannot refer to both a single-node metavariable and an ellipsis
sequence within the same rule.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'pair($items, [$$$items])' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    pair($items, [$$$items])
  reason: the pattern cannot use items as both an ellipsis metavar and a single-node metavar
  help: fix the pattern passed to --pattern and try again
[5]
```

Repeated declarations of a named ellipsis must use the same kind.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'pair([$$$(items:exp)], [$$$(items:id)])' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    pair([$$$(items:exp)], [$$$(items:id)])
  reason: the pattern declares ellipsis metavar items as multiple metavar kinds
  help: fix the pattern passed to --pattern and try again
[5]
```

`__TARGET__` is reserved for the target inserted by `then` traversal and
cannot be declared as an ellipsis name.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'inspect($$$__TARGET__)' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    inspect($$$__TARGET__)
  reason: the pattern cannot declare metavar __TARGET__ because it is reserved for then target traversal
  help: fix the pattern passed to --pattern and try again
[5]
```

`__SOURCE__` is reserved for taint source propagation and is rejected for the
same reason.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'inspect($$$__SOURCE__)' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    inspect($$$__SOURCE__)
  reason: the pattern cannot declare metavar __SOURCE__ because it is reserved for taint source targets
  help: fix the pattern passed to --pattern and try again
[5]
```

Regex guards operate on single captured nodes, not ordered node sequences, so
they cannot refer to an ellipsis metavariable.

```mooncram moonbit-community/moongrep
$ moongrep scan --pattern 'inspect($$$args)' --guard '{$args: ".+"}' ../testdata/ellipsis/sample.mbt
@STDOUT (ignore)
@STDERR
error: invalid anonymous pattern
  source: --pattern
  pattern:
    inspect($$$args)
  reason: patterns[0].guard.$args cannot reference ellipsis metavar args
  help: fix the pattern passed to --pattern and try again
[5]
```
