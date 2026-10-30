#!/bin/sh
# Compile to a temporary bytecode file, never execute any application code.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM
count=0
for file in "$ROOT"/forkop/files/usr/lib/subscription/amnezia_*.uc \
    "$ROOT/forkop/files/usr/lib/subscription/cache.uc" \
    "$ROOT/forkop/files/usr/lib/singbox/generator.uc" \
    "$ROOT/forkop/files/usr/lib/singbox/subscription.uc" \
    "$ROOT/forkop/files/usr/lib/service/lifecycle.uc" \
    "$ROOT/forkop/files/usr/lib/nft/apply.uc"; do
    [ -f "$file" ] || { echo "Missing source: $file" >&2; exit 1; }
    echo "Compiling ${file#"$ROOT"/}"
    ucode -c -o "$WORK/module.ucb" "$file"
    count=$((count + 1))
done
[ "$count" -gt 5 ] || { echo 'AWG modules were not found' >&2; exit 1; }
echo "Compiled $count ucode files without executing them"
