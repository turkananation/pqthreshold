#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/crypto_shared.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT

cp -R "$repo_root/packages/crypto_shared/." "$stage_dir/"
rm -rf "$stage_dir/.dart_tool" "$stage_dir/pubspec.lock"

cd "$stage_dir"
exec dart pub publish "$@"