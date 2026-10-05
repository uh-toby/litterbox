#!/bin/bash
# One headless Secret Service daemon shared by trusted Hub worktree containers.
set -euo pipefail

export HOME=/var/lib/lyssna-keyring
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

if [[ "${1:-}" != --session ]]; then
  install -d -o 1000 -g 1000 -m 700 "$HOME" "$XDG_RUNTIME_DIR"
  chown -R 1000:1000 "$HOME"
  # No consumer owns this runtime: only this service starts D-Bus/keyring.
  find "$XDG_RUNTIME_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  exec setpriv --reuid=1000 --regid=1000 --init-groups "$0" --session
fi

password_file="$HOME/keyring-password"
if [[ ! -f "$password_file" ]]; then
  (umask 177 && head -c32 /dev/urandom | base64 >"$password_file")
fi
chmod 600 "$password_file"
install -d -m 700 "$XDG_RUNTIME_DIR/dbus-1/services" "$XDG_RUNTIME_DIR/keyring"

dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --nofork --nopidfile &
bus_pid=$!
trap 'kill "$bus_pid" 2>/dev/null || true' EXIT
trap 'exit 0' TERM INT

for _ in {1..50}; do
  if dbus-send --session --print-reply --dest=org.freedesktop.DBus / \
    org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

# Initialise/unlock before any consumer query can activate a locked keyring.
eval "$(gnome-keyring-daemon --login --components=secrets <"$password_file")"
eval "$(gnome-keyring-daemon --start --components=secrets)"
touch "$XDG_RUNTIME_DIR/.keyring-started"

# Keep the service alive with D-Bus; Docker restarts it if the bus exits.
wait "$bus_pid"
