set -eu

wasm=$1
root=testdata/skip-dirs

cleanup() {
  rm -rf "$root/.git" "$root/_build" "$root/.mooncakes" "$root/target"
}

cleanup
mkdir -p "$root/.git" "$root/_build" "$root/.mooncakes" "$root/target"
for dir in .git _build .mooncakes target; do
  printf 'fn sample { target() }\n' > "$root/$dir/ignored.mbt"
done

trap cleanup EXIT
moonrun "$wasm" -- scan --verbose --rules e2etests/rules/structural "$root"
