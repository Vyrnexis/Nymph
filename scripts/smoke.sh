#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

BIN="./bin/nymph"

echo "Building nymph..."
nim c -d:release -d:danger --opt:size --nimcache:./.nimcache -o:./bin/nymph src/nymph.nim >/dev/null

echo "Smoke: run with builtin defaults"
"$BIN" >/dev/null

echo "Smoke: run with --no-color"
"$BIN" --no-color >/dev/null

echo "Smoke: run with override logo name (fallback expected)"
"$BIN" --logo fake-does-not-exist >/dev/null

echo "Smoke: run with override logo name (existing)"
"$BIN" --logo archlinux >/dev/null

echo "Smoke: run with theme/icon/layout/modules"
"$BIN" --theme nord --icon-pack ascii --layout compact --modules os,kernel,packages,memory >/dev/null

echo "Smoke: run doctor output"
"$BIN" --doctor | rg -q "Nymph doctor"

echo "Smoke: run json output"
"$BIN" --json | rg -q "\"packages\""

echo "Smoke: list themes and icon packs"
"$BIN" --list-themes | rg -q "catppuccin"
"$BIN" --list-icon-packs | rg -q "nerd"

echo "OK"
