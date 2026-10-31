#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root. GOOSDOC names goosdoc's main.goose.
exec "${GOOSE:-goose}" run "${GOOSDOC:-../goosdoc/main.goose}" -- \
  --title "goosimd API" --symbols api.txt --require-docs \
  --output "${DOC_OUTPUT:-API.md}" "$@" goosimd.goose
