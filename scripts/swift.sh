#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${PROMPT_PIN_COMPAT:-0}" == "1" ]]; then
  export SWIFT_EXEC="$(python3 scripts/prepare-compat.py)"
fi
if [[ "${1:-}" == "compile" ]]; then
  shift
  "${SWIFT_EXEC:-$(xcrun --find swiftc)}" -sdk "$(xcrun --show-sdk-path)" "$@"
else
  swift "$@"
fi
