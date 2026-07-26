#!/bin/bash
# Run the launcher locally on macOS for testing.
# Requires LÖVE (brew install love).

cd "$(dirname "$0")"

if command -v love >/dev/null 2>&1; then
    exec love .
elif [ -x "/Applications/love.app/Contents/MacOS/love" ]; then
    exec /Applications/love.app/Contents/MacOS/love .
else
    echo "LÖVE not found. Install with: brew install --cask love"
    exit 1
fi
