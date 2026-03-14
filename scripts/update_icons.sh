#!/bin/bash

# This script updates all PNG icons from the SVG source files.
# Requires: rsvg-convert (librsvg)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DARK_SVG="assets/trans-dark.svg"
LIGHT_SVG="assets/trans-light.svg"

echo "Generating icons from $DARK_SVG and $LIGHT_SVG..."

# 0. Copy SVGs to web/ for direct usage there
echo "  -> web/ (copying SVGs)"
cp "$DARK_SVG" "web/trans-dark.svg"
cp "$LIGHT_SVG" "web/trans-light.svg"

# Function to generate PNG from SVG
gen_png() {
    local src=$1
    local dest=$2
    local size=$3
    echo "  -> $dest ($size x $size)"
    mkdir -p "$(dirname "$dest")"
    rsvg-convert -w "$size" -h "$size" "$src" -o "$dest"
}

# 1. Flutter Assets (lib/assets)
# logo_dark should be the one for light theme (dark icons)
# logo_light should be the one for dark theme (light icons)
gen_png "$DARK_SVG" "lib/assets/logo_dark.png" 512
gen_png "$LIGHT_SVG" "lib/assets/logo_light.png" 512

# 2. Project Icons (assets)
gen_png "$DARK_SVG" "assets/icon.png" 1024
gen_png "$DARK_SVG" "assets/logo.png" 1024

# 3. Web Icons (web/icons)
gen_png "$DARK_SVG" "web/icons/Icon-192.png" 192
gen_png "$DARK_SVG" "web/icons/Icon-512.png" 512
gen_png "$DARK_SVG" "web/icons/Icon-maskable-192.png" 192
gen_png "$DARK_SVG" "web/icons/Icon-maskable-512.png" 512

echo "Done! Icons updated."
