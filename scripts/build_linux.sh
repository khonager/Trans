#!/bin/bash

# Navigate to the project root directory
cd "$(dirname "$0")/.." || exit

echo "Building Linux Version..."
nix develop -c flutter build linux --release

echo "Build complete! Linux build should be in build/linux/x64/release/bundle/"
# Pause so the user can read the output if they double click it in a file manager
read -p "Press Enter to close..."
