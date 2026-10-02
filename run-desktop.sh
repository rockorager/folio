#!/usr/bin/env bash
set -euo pipefail
directory="$(dirname "$(realpath "$0")")"
toolkit="${OUROKIT_DIR:-$directory/../ourokit}"
exec "$toolkit/zig-out/bin/ouroctl" run "$directory/ouro.json" --software "$@"
