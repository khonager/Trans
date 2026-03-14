#!/bin/bash

# Navigate to the project root directory
cd "$(dirname "$0")/.." || exit

echo "Building Stable AppBundle (AAB)..."
nix develop -c flutter build appbundle --release --flavor stable

echo "Build complete! AppBundle should be in build/app/outputs/bundle/stableRelease/"
# Pause so the user can read the output if they double click it in a file manager
read -p "Press Enter to close..."
