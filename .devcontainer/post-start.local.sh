#!/bin/bash
# Consumers only connect to the shared service; never start a local keyring.
set -euo pipefail

for _ in {1..20}; do
  if dbus-send --session --print-reply --dest=org.freedesktop.secrets \
    /org/freedesktop/secrets/aliases/default org.freedesktop.DBus.Properties.Get \
    string:org.freedesktop.Secret.Collection string:Locked 2>/dev/null \
    | grep -q 'boolean false'; then
    exit 0
  fi
  sleep 0.5
done

echo "Error: shared Secret Service is unavailable or locked. Run the host initialize.local.sh and inspect lyssna-keyring." >&2
exit 1
