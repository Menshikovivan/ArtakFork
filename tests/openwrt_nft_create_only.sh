#!/bin/sh
set -eu
table="artak_recovery_test_$$"
testfile="/tmp/artak-nft-create-$$"
cleanup() { nft delete table inet "$table" >/dev/null 2>&1 || true; rm -f "$testfile"; }
trap cleanup EXIT HUP INT TERM
printf 'create table inet %s\nadd chain inet %s marker\n' "$table" "$table" > "$testfile"
nft -f "$testfile"
nft list chain inet "$table" marker >/dev/null
# Replaying create must fail atomically, leaving the original table untouched.
printf 'create table inet %s\nadd chain inet %s unexpected\n' "$table" "$table" > "$testfile"
if nft -f "$testfile" >/dev/null 2>&1; then echo 'create-only accepted existing table' >&2; exit 1; fi
nft list chain inet "$table" marker >/dev/null
if nft list chain inet "$table" unexpected >/dev/null 2>&1; then echo 'failed transaction changed table' >&2; exit 1; fi
echo 'nft atomic create-only checks passed'
