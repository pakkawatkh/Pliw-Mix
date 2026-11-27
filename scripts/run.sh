#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

pkill -9 -x "pliw-mix" || true
sleep 0.3

if [ -d "/Applications/Pliw Mix.app" ]; then
    open "/Applications/Pliw Mix.app"
    echo "🚀 Launched /Applications/Pliw Mix.app"
else
    open "${PROJECT_DIR}/Pliw Mix.app"
    echo "🚀 Launched ${PROJECT_DIR}/Pliw Mix.app"
fi
