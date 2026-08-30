set -eu

wasm=$1
root=testdata/skip-dirs

cleanup() {
  rm -rf "$root/.git" "$root/.mooncakes" "$root/.xx" "$root/_build" \
    "$root/node_modules" "$root/target"
}

cleanup
mkdir -p "$root/.git" "$root/.mooncakes" "$root/.xx" "$root/_build" \
  "$root/node_modules" "$root/target"
for dir in .git .mooncakes .xx _build node_modules target; do
  printf 'fn sample { target() }\n' > "$root/$dir/ignored.mbt"
done

trap cleanup EXIT
moonrun "$wasm" -- scan --verbose --rules e2etests/rules/structural "$root"
