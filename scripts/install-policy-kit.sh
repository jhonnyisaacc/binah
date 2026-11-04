#!/usr/bin/env bash
# Caller for the install command. binah-install does the work.
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/binah-install" "$@"
