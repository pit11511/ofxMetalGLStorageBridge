#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INPUT_METAL="${1:-$ROOT_DIR/example-basic/bin/data/metal/ofxMetalGLStorageKernels.metal}"
OUTPUT_METALLIB="${2:-${INPUT_METAL%.metal}.metallib}"
OUTPUT_AIR="${OUTPUT_METALLIB%.metallib}.air"

if [[ ! -f "$INPUT_METAL" ]]; then
  echo "input .metal file not found: $INPUT_METAL" >&2
  exit 1
fi

if ! xcrun -sdk macosx metal -std=metal3.1 -c "$INPUT_METAL" -o "$OUTPUT_AIR"; then
  echo "If Metal Toolchain is missing, run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

xcrun -sdk macosx metallib "$OUTPUT_AIR" -o "$OUTPUT_METALLIB"
rm -f "$OUTPUT_AIR"

echo "built: $OUTPUT_METALLIB"
