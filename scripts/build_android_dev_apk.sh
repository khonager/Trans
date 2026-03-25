#!/bin/bash

# Navigate to the project root directory
cd "$(dirname "$0")/.." || exit

echo "Building Dev APK..."
nix develop -c flutter build apk --release --flavor dev

echo "Build complete! APK should be in build/app/outputs/flutter-apk/"
# Pause so the user can read the output if they double click it in a file manager
read -p "Press Enter to close..."
