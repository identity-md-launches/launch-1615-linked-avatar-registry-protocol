#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
sha256sum --check DEPENDENCIES.sha256
forge fmt --check

# Verify only deliverable sources in a fresh directory, without local build output or pinned inputs.
larp_check_dir=$(mktemp -d)
trap 'rm -rf -- "$larp_check_dir"' EXIT
cp -R -- src test lib foundry.toml remappings.txt "$larp_check_dir/"
rm -rf -- "$larp_check_dir/test/scratch"
(
    cd -- "$larp_check_dir"
    forge build --offline
    forge test --offline
    forge fmt --check
    slither . --exclude-informational --exclude-optimization --exclude-low --exclude-medium
)

slither . --exclude-informational --exclude-optimization --exclude-low
forge test --offline --fuzz-seed 0x4c415250 --fuzz-runs 2048
forge build --offline --sizes
