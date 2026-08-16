#!/usr/bin/env bash
set -e

echo "==> Compilando balatro-spotify-daemon (Linux/macOS)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_DIR="$SCRIPT_DIR/daemon"
BIN_DIR="$SCRIPT_DIR/bin"

mkdir -p "$BIN_DIR"

cd "$DAEMON_DIR"
cargo build --release

if [[ "$OSTYPE" == "darwin"* ]]; then
    TARGET_BIN="$BIN_DIR/daemon-x86_64-apple-darwin"
else
    TARGET_BIN="$BIN_DIR/daemon-x86_64-linux"
fi

cp "$DAEMON_DIR/target/release/balatro-spotify-daemon" "$TARGET_BIN"
chmod +x "$TARGET_BIN"

echo "==> Compilación exitosa: $TARGET_BIN"
