set -euox pipefail

# setup moongrep
moon build --release
cp _build/wasm/release/build/moongrep.wasm e2etests


for mdfile in e2etests/*.md; do
  NO_COLOR=1 moon-cram "$@" "$mdfile"
done
