#!/bin/bash
# Vitro Launcher build script
# Creates an uncompressed .muxupd package for the muOS Archive Manager.

set -e

VERSION="1.0.0"
APP_NAME="Vitro Launcher"
APP_DIR="application/${APP_NAME}"
ARCHIVE_NAME="VitroLauncher"
ARCHIVE_EXT="muxupd"
ICON_DIR="opt/muos/default/MUOS/theme/active/glyph/muxapp"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# Love2D ARM64 binaries must be provided in bin/ (extract from an existing
# muOS Love2D app such as the Bluetooth configurator or ClickWheel).
if [ ! -f "bin/love" ]; then
    echo "ERROR: Love2D binaries not found in bin/"
    echo "Copy bin/ (love + libs.aarch64/) from a working muOS Love2D app, e.g.:"
    echo "  cp -r .examples/iPod-muOS/ClickWheel/bin ."
    exit 1
fi

if ! file bin/love | grep -q "aarch64"; then
    echo "ERROR: bin/love is not an ARM64 binary"
    exit 1
fi

rm -rf .build/ .dist/
mkdir -p .build/mnt/mmc/MUOS/"${APP_DIR}"
mkdir -p .build/"${ICON_DIR}"
mkdir -p .dist

# App sources
cp conf.lua main.lua defaults.cfg .build/mnt/mmc/MUOS/"${APP_DIR}"/
cp -r src assets .build/mnt/mmc/MUOS/"${APP_DIR}"/
cp mux_launch.sh vitrolauncher.gptk .build/mnt/mmc/MUOS/"${APP_DIR}"/

# Launch-at-boot and fast-boot scripts (opt-in; see README). Shipped
# inside the app folder so they are on the device, ready to copy to
# MUOS/init/ or MUOS/task/.
cp vitrolauncher_boot.sh vitrolauncher_boot_off.sh \
    vitrolauncher_fastboot_on.sh vitrolauncher_fastboot_off.sh \
    .build/mnt/mmc/MUOS/"${APP_DIR}"/
chmod +x .build/mnt/mmc/MUOS/"${APP_DIR}"/vitrolauncher_boot.sh \
    .build/mnt/mmc/MUOS/"${APP_DIR}"/vitrolauncher_boot_off.sh \
    .build/mnt/mmc/MUOS/"${APP_DIR}"/vitrolauncher_fastboot_on.sh \
    .build/mnt/mmc/MUOS/"${APP_DIR}"/vitrolauncher_fastboot_off.sh

# Ship the GAME folder structure (info.cfg files only by default; roms
# are usually copied to the device separately because of their size).
# Uncomment to bundle everything currently in GAME/:
# cp -r GAME .build/mnt/mmc/MUOS/"${APP_DIR}"/
mkdir -p .build/mnt/mmc/MUOS/"${APP_DIR}"/GAME

# Love2D runtime
cp -r bin .build/mnt/mmc/MUOS/"${APP_DIR}"/

# Icons (optional)
if [ -f "icon.png" ]; then
    cp icon.png .build/"${ICON_DIR}"/vitrolauncher.png
fi
if [ -f "icon-glyph.png" ]; then
    mkdir -p .build/mnt/mmc/MUOS/"${APP_DIR}"/glyph
    cp icon-glyph.png .build/mnt/mmc/MUOS/"${APP_DIR}"/glyph/vitrolauncher.png
fi

chmod +x .build/mnt/mmc/MUOS/"${APP_DIR}"/mux_launch.sh
chmod +x .build/mnt/mmc/MUOS/"${APP_DIR}"/bin/love

# Strip macOS metadata files
find .build \( -name ".DS_Store" -o -name "._*" \) -delete

# CRITICAL: store method only (-0), Archive Manager expects no compression
cd .build
zip -0qr "../.dist/${ARCHIVE_NAME}_${VERSION}.${ARCHIVE_EXT}" mnt opt
cd ..

rm -rf .build/

echo "✓ Built .dist/${ARCHIVE_NAME}_${VERSION}.${ARCHIVE_EXT}"
echo "Copy it to the device's ARCHIVE/ folder and install via Archive Manager."
