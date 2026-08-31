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

secret_service_registered() {
  dbus-send --session \
    --dest=org.freedesktop.DBus --print-reply \
    /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null \
    | grep -q '"org.freedesktop.secrets"'
}

secret_service_ready() {
  dbus-send --session \
    --dest=org.freedesktop.secrets --print-reply \
    /org/freedesktop/secrets/aliases/default \
    org.freedesktop.DBus.Properties.Get \
    string:org.freedesktop.Secret.Collection string:Locked 2>/dev/null \
    | awk '/boolean/ { print $NF; exit }' \
    | grep -qx false
}

secret_service_pid() {
  dbus-send --session \
    --dest=org.freedesktop.DBus --print-reply \
    /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID \
    string:org.freedesktop.secrets 2>/dev/null \
    | awk '/uint32/ { print $NF; exit }'
}

sudo install -d -o "$(id -u)" -g "$(id -g)" -m 700 "$runtime_dir"
sudo chown "$(id -u):$(id -g)" "$runtime_dir"
sudo chmod 700 "$runtime_dir"
install -d -m 700 "$keyring_dir"

# postStart can be entered more than once by an IDE or CLI reconnect. The lock
# ensures those invocations share the one container-local session.
exec 9>"$lock_file"
flock 9

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

  # The Nix D-Bus package keeps session.conf in its immutable store path rather
  # than /etc. Prefer the system configuration when it exists so this remains
  # compatible with an apt-provided D-Bus daemon.
  if [[ -f /etc/dbus-1/session.conf ]]; then
    dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --fork --nopidfile
  else
    dbus_daemon="$(readlink -f "$(command -v dbus-daemon)")"
    dbus_session_config="$(dirname "$(dirname "$dbus_daemon")")/share/dbus-1/session.conf"
    [[ -f "$dbus_session_config" ]] || {
      echo "Error: could not find a D-Bus session configuration for $dbus_daemon." >&2
      exit 1
    }
    dbus-daemon --config-file="$dbus_session_config" --address="$DBUS_SESSION_BUS_ADDRESS" --fork --nopidfile
  fi
fi

# Do not query org.freedesktop.secrets before --login. D-Bus activation would
# start gnome-keyring without the password and leave its default collection
# locked. A pre-existing locked daemon can only be one from that old race, so
# stop it and initialise it with this container's persistent password instead.
if secret_service_registered; then
  if secret_service_ready; then
    exit 0
  fi

  keyring_pid="$(secret_service_pid)"
  if [[ -n "$keyring_pid" ]]; then
    kill "$keyring_pid"
    for _ in {1..20}; do
      secret_service_registered || break
      sleep 0.1
    done
  fi
  rm -rf "$runtime_dir/keyring" "$runtime_dir"/keyring-*
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
