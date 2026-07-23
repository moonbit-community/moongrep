# Ellipsis metavariables

The matching snapshots below print only the matched source to keep positive and
near-miss cases readable.

## Empty, single, and multiple items

An argument ellipsis accepts any number of complete arguments, including zero,
and preserves the entire matched call as the result.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'inspect($$$args)' testdata/ellipsis/sample.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
inspect()
inspect(1)
inspect(1, content=\"1\")
```

Fixed items on both sides of an ellipsis remain exact anchors. The middle
capture may be empty or contain several arguments, while calls with a different
prefix or suffix do not match.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'anchored(prefix, $$$middle, suffix)' testdata/ellipsis/sample.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
anchored(prefix, suffix)
anchored(prefix, first, second, suffix)
```

## Backtracking and binding equality

Later fixed items can force an ellipsis matcher to reconsider an earlier split.
Only the call that can consume both markers and the full argument list is
accepted.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'split($$$left, marker, $$$right, marker)' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
split(a, marker, b, marker)
```

Repeated named ellipses must capture structurally equal sequences. Equality
holds for both empty and multi-item arrays; unequal sequences are omitted.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'repeated([$$$items], [$$$items])' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
repeated([], [])
repeated([a, b], [a, b])
```

Argument labels are part of a captured sequence. Reusing the capture across
two calls succeeds only when positional values, labels, and values all agree.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'arguments_equal(left($$$args), right($$$args))' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
arguments_equal(left(1, label=2), right(1, label=2))
```

The anonymous ellipsis `$$$_` does not bind a reusable value. Its two
occurrences can therefore consume different sequences.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'anonymous([$$$_], [$$$_])' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
anonymous([a], [b, c])
```

Anonymous ellipses can still constrain item kinds independently. Here the
first array must contain constants and the second must contain identifiers.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'typed_anonymous([$$$(_:const)], [$$$(_:id)])' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
typed_anonymous([1, 2], [a, b])
```

A kind declared on the first occurrence of a named ellipsis also applies when
the same name is reused in shorthand form. Only equal constant sequences
match.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'propagated([$$$(items:const)], [$$$items])' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
propagated([1, 2], [1, 2])
```

Backtracking over an ellipsis must preserve ordinary metavariable bindings.
The final expression therefore has to equal the earlier captured `value`.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'restore($$$gap, $(value:exp), marker, $(value:exp))' testdata/ellipsis/bindings.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
restore(first, selected, marker, selected)
```

## Typed call arguments

Bare and `arg` ellipses accept every complete argument kind. The `exp`, `id`,
and `const` forms accept only compatible positional argument values.

The explicit `arg` kind accepts positional, labelled, punned, and optional
arguments, as well as an empty argument list.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'any_args($$$(args:arg))' testdata/ellipsis/arguments.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
any_args()
any_args(value, other)
any_args(value, label=other)
any_args(label~)
any_args(label?=other)
any_args(label?)
```

An `exp` argument ellipsis accepts only positional expression values. Labelled
and punned arguments in the fixture are not reported.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'exp_args($$$(args:exp))' testdata/ellipsis/arguments.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
exp_args()
exp_args(value, other + 1)
```

An `id` argument ellipsis narrows positional values further to identifiers,
excluding constants and labelled arguments.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'id_args($$$(args:id))' testdata/ellipsis/arguments.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
id_args()
id_args(value, other)
```

A `const` argument ellipsis accepts literal positional values, excluding
identifier values and labelled constants.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'const_args($$$(args:const))' testdata/ellipsis/arguments.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
const_args()
const_args(1, \"two\")
```

## Ordered AST list positions

The array fixture also contains a spread element; both the bare and `exp`
patterns below intentionally match only the regular-element array.

Ellipses work in tuple element lists. A fixed trailing element anchors the
capture and prevents a tuple with a different tail from matching.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'tuple_expr(($$$(items:exp), tail))' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
tuple_expr((first, second, tail))
```

Block statements are ordered list items as well. The ellipsis consumes the
leading statements, while the final `tail` expression remains fixed.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'if condition { $$$items; tail }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
if condition {\n    before()\n    middle()\n    tail\n  }
```

An `exp` ellipsis captures regular array elements. It does not consume the
spread element in the second array from the fixture.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'array_expr([$$$(items:exp)])' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
array_expr([first, second])
```

The bare array ellipsis has the same complete-item requirement, so it also
matches only the array made entirely of regular elements.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'array_expr([$$$items])' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
array_expr([first, second])
```

A `pat` ellipsis captures the leading tuple patterns before the fixed `tail`
pattern.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match tuple_input { ($$$(items:pat), tail) => tuple_pattern }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match tuple_input { (first, second, tail) => tuple_pattern }
```

Constructor pattern arguments form another ordered pattern list and can be
captured together by a `pat` ellipsis.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match constructor_input { Some($$$(items:pat)) => constructor_pattern }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match constructor_input { Some(first, second) => constructor_pattern }
```

Array pattern lists accept all pattern forms under the `pat` kind, including
identifiers, wildcards, and constants.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match array_input { [$$$(items:pat)] => array_pattern }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match array_input { [first, _, 1] => array_pattern }
```

An `id` ellipsis in an array pattern accepts only identifier patterns. The
fixture containing a constant is excluded.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match id_input { [$$$(items:id)] => id_patterns }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match id_input { [first, second] => id_patterns }
```

A `const` ellipsis in the same position accepts only constant patterns. The
fixture containing an identifier is excluded.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'match const_input { [$$$(items:const)] => const_patterns }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
match const_input { [1, \"two\"] => const_patterns }
```

Type tuple elements can be captured with a `type` ellipsis while a fixed final
type anchors the end of the tuple.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'let value : ($$$(Types:type), Bool) = input' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
let value : (Int, String, Bool) = input
```

Function parameter lists support ellipses across positional, labelled,
defaulted, and optional parameters. The same pattern also accepts an empty
parameter list.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --output-json --pattern 'fn($$$(params:id)) { body }' testdata/ellipsis/ordered_lists.mbt | sed -n 's/.*"matched_source":"\(.*\)","source_context".*/\1/p'
fn(\n    positional,\n    labelled~ : Int,\n    optional~ : Int = 1,\n    question? : String,\n  ) { body }
fn() { body }
```

## Rule contexts and prefiltering

An ellipsis captured by `inside-expr` can be reused by the target pattern. The
target matches when its arguments repeat the wrapper prefix, including the
empty prefix, and rejects a differing final argument.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/ellipsis/inside/rules testdata/ellipsis/inside/src
testdata/ellipsis/inside/src/sample.mbt:2:3-2:20
rule: ellipsis-inside
description:
  Reuse the surrounding argument prefix inside the target.
source:
1 | fn inside {
2 >   wrapper(target())
3 |   wrapper(a, b, target(a, b))
4 |   wrapper(a, b, target(a, other))

testdata/ellipsis/inside/src/sample.mbt:3:3-3:30
rule: ellipsis-inside
description:
  Reuse the surrounding argument prefix inside the target.
source:
1 | fn inside {
2 |   wrapper(target())
3 >   wrapper(a, b, target(a, b))
4 |   wrapper(a, b, target(a, other))
5 | }
```

Taint rules can place ellipses around source and sink arguments. Both direct
dirty values reach the variadic sink, while a variadic sanitizer removes the
third candidate.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/ellipsis/taint/rules testdata/ellipsis/taint/src
testdata/ellipsis/taint/src/sample.mbt:3:24-3:29
rule: ellipsis-taint
description:
  Variadic sink arguments preserve taint and variadic cleaners sanitize it.
source:
1 | fn taint {
2 |   let dirty = get_user_input()
3 >   sink(prefix, marker, dirty)
4 |   sink(prefix, one, two, marker, dirty, trailing)
5 |   sink(prefix, marker, clean(prefix, around, dirty, trailing), trailing)

testdata/ellipsis/taint/src/sample.mbt:4:34-4:39
rule: ellipsis-taint
description:
  Variadic sink arguments preserve taint and variadic cleaners sanitize it.
source:
2 |   let dirty = get_user_input()
3 |   sink(prefix, marker, dirty)
4 >   sink(prefix, one, two, marker, dirty, trailing)
5 |   sink(prefix, marker, clean(prefix, around, dirty, trailing), trailing)
6 | }
```

Literal items adjacent to an ellipsis remain useful prefilter anchors. They
select the call with the required prefix and suffix without admitting calls
whose callee or prefix differs.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rules testdata/ellipsis/prefilter/rules testdata/ellipsis/prefilter/src
testdata/ellipsis/prefilter/src/sample.mbt:2:3-2:34
rule: ellipsis-prefilter
description:
  Keep literals adjacent to an ellipsis as prefilter anchors.
source:
1 | fn prefilter {
2 >   anchored(prefix, value, suffix)
3 |   anchored(other, value, suffix)
4 |   other(prefix, value, suffix)
```

## Validation errors

Ellipses must occupy a complete unnamed ordered-list item.

A standalone ellipsis is an expression position rather than an item inside an
ordered AST list, so it is rejected during rule validation.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern '$$$items' testdata/ellipsis/sample.mbt
$$$items: patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered AST list item
[1]
```

Embedding an ellipsis inside a larger arithmetic expression also makes it only
part of a list item and is invalid.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'wrap($$$items + 1)' testdata/ellipsis/sample.mbt
wrap($$$items + 1): patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered AST list item
[1]
```

A labelled argument value is not an unnamed argument item. An ellipsis cannot
be used as only the value of that labelled argument.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'sink(label=$$$items)' testdata/ellipsis/sample.mbt
sink(label=$$$items): patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered AST list item
[1]
```

The final expression of a block is not a replaceable statement sequence. A
bare ellipsis in that position must therefore be rejected.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'if condition { $$$items }' testdata/ellipsis/sample.mbt
if condition { $$$items }: patterns[0].shape uses ellipsis metavar $$$items outside a complete ordered AST list item
[1]
```

Malformed spellings and unsupported kinds are rejected.

An ellipsis needs either a name or the explicit anonymous spelling `$$$_`.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$)' testdata/ellipsis/sample.mbt
inspect($$$): patterns[0].shape has invalid metavar syntax $$; use explicit typed syntax like $(value:exp)
[1]
```

Parenthesized ellipsis syntax must include a kind after the name; an untyped
`$$$(items)` form is not accepted.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$(items))' testdata/ellipsis/sample.mbt
inspect($$$(items)): patterns[0].shape has invalid metavar syntax $$$(items); use explicit typed syntax like $(value:exp)
[1]
```

Typed ellipses validate their kind names and report an unsupported kind before
the scan starts.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$(items:unknown))' testdata/ellipsis/sample.mbt
inspect($$$(items:unknown)): patterns[0].shape contains unsupported ellipsis metavar kind unknown
[1]
```

Typed ellipses must be compatible with their list slot.

A call argument list cannot contain a `type` ellipsis because its items are
arguments, not types.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'sink($$$(items:type))' testdata/ellipsis/sample.mbt
sink($$$(items:type)): patterns[0].shape uses ellipsis kind type in an incompatible ordered-list item position
[1]
```

A function parameter list cannot contain an `exp` ellipsis because parameters
are not expression items.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'fn($$$(items:exp)) { body }' testdata/ellipsis/sample.mbt
fn($$$(items:exp)) { body }: patterns[0].shape uses ellipsis kind exp in an incompatible ordered-list item position
[1]
```

An array pattern list likewise rejects an `exp` ellipsis and requires a pattern
compatible kind.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'match input { [$$$(items:exp)] => body }' testdata/ellipsis/sample.mbt
match input { [$$$(items:exp)] => body }: patterns[0].shape uses ellipsis kind exp in an incompatible ordered-list item position
[1]
```

Names cannot mix capture forms, kinds, reserved names, or guards.

One name cannot refer to both a single-node metavariable and an ellipsis
sequence within the same rule.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'pair($items, [$$$items])' testdata/ellipsis/sample.mbt
pair($items, [$$$items]): patterns[0].shape cannot use items as both an ellipsis metavar and a single-node metavar
[1]
```

Repeated declarations of a named ellipsis must use the same kind.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'pair([$$$(items:exp)], [$$$(items:id)])' testdata/ellipsis/sample.mbt
pair([$$$(items:exp)], [$$$(items:id)]): patterns[0].shape declares ellipsis metavar items as multiple metavar kinds
[1]
```

`__TARGET__` is reserved for the target inserted by `inside-expr` traversal and
cannot be declared as an ellipsis name.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$__TARGET__)' testdata/ellipsis/sample.mbt
inspect($$$__TARGET__): patterns[0] cannot declare metavar __TARGET__ because it is reserved for inside-expr target traversal
[1]
```

`__SOURCE__` is reserved for taint source propagation and is rejected for the
same reason.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$__SOURCE__)' testdata/ellipsis/sample.mbt
inspect($$$__SOURCE__): patterns[0] cannot declare metavar __SOURCE__ because it is reserved for taint source targets
[1]
```

Regex guards operate on single captured nodes, not ordered node sequences, so
they cannot refer to an ellipsis metavariable.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --pattern 'inspect($$$args)' --guard '{$args: ".+"}' testdata/ellipsis/sample.mbt
inspect($$$args): patterns[0].guard.$args cannot reference ellipsis metavar args
[1]
```

Inherited inside-context captures must remain ellipses with the same kind.

Reusing an inherited ellipsis with a different typed kind would change its
capture contract and is rejected while loading the rule.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rule testdata/ellipsis/invalid/inside-kind.yaml testdata/ellipsis/sample.mbt
testdata/ellipsis/invalid/inside-kind.yaml: patterns[0] cannot use inherited inside-expr ellipsis metavar items with a different kind
[1]
```

An inherited ellipsis also cannot be narrowed to a single-node metavariable in
the target pattern.

```mooncram
$ cd "$TESTDIR"/.. && moonrun "$TESTDIR"/moongrep.wasm -- scan --rule testdata/ellipsis/invalid/inside-single.yaml testdata/ellipsis/sample.mbt
testdata/ellipsis/invalid/inside-single.yaml: patterns[0] cannot use inherited inside-expr ellipsis metavar items as exp
[1]
```
