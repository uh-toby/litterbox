#!/bin/bash
# Start one headless Secret Service session for this container. Pup and Buildkite
# then use their upstream binaries directly through the fixed D-Bus socket set
# in compose.local.yaml.

set -euo pipefail

runtime_dir="/run/user/$(id -u)"
bus_path="$runtime_dir/bus"
keyring_dir="$HOME/.local/share/keyring-session"
password_file="$keyring_dir/password"
lock_file="$keyring_dir/lock"

secret_service_ready() {
  dbus-send --session \
    --dest=org.freedesktop.secrets --print-reply \
    /org/freedesktop/secrets/aliases/default \
    org.freedesktop.DBus.Properties.Get \
    string:org.freedesktop.Secret.Collection string:Locked 2>/dev/null \
    | awk '/boolean/ { print $NF; exit }' \
    | grep -qx false
}

sudo install -d -o "$(id -u)" -g "$(id -g)" -m 700 "$runtime_dir"
sudo chown "$(id -u):$(id -g)" "$runtime_dir"
sudo chmod 700 "$runtime_dir"
install -d -m 700 "$keyring_dir"

# postStart can be entered more than once by an IDE or CLI reconnect. The lock
# ensures those invocations share the one container-local session.
exec 9>"$lock_file"
flock 9

if secret_service_ready; then
  exit 0
fi

if [[ ! -f "$password_file" ]]; then
  (umask 177 && head -c32 /dev/urandom | base64 >"$password_file")
fi
chmod 600 "$password_file"

# A stopped container leaves no processes behind, but an unclean shutdown can
# leave runtime directories with restrictive 0600 permissions. Remove them
# before D-Bus and gnome-keyring recreate their private 0700 directories.
if ! dbus-send --session \
  --dest=org.freedesktop.DBus --print-reply \
  /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
  rm -rf "$bus_path" "$runtime_dir/dbus-1" "$runtime_dir/keyring" "$runtime_dir"/keyring-*
  # dbus-daemon and gnome-keyring expect these private directories to be
  # searchable by their owner. Creating them here avoids a Debian trixie bug
  # where they can otherwise be created as mode 0600.
  install -d -m 700 "$runtime_dir/dbus-1/services" "$runtime_dir/keyring"
  dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --fork --nopidfile
fi

# --login unlocks the persistent collection. Starting the Secret Service
# component registers it on the fixed D-Bus session for every container process.
eval "$(gnome-keyring-daemon --login --components=secrets,pkcs11 <"$password_file")"
eval "$(gnome-keyring-daemon --start --components=secrets,pkcs11)"

# Do not let the daemon inherit the lock descriptor: a later postStart must be
# able to confirm the session without waiting for the container to stop.
flock -u 9
exec 9>&-

# Secret Service registers asynchronously after gnome-keyring starts.
for _ in {1..20}; do
  if secret_service_ready; then
    exit 0
  fi
  sleep 0.1
done

echo "Error: Secret Service did not start with an unlocked default collection." >&2
exit 1
