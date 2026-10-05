#!/bin/bash
set -euo pipefail

# Personal stores survive worktree/container cleanup.
for volume in lyssna-nix lyssna-keyring-data lyssna-keyring-runtime; do
  docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create "$volume" >/dev/null
done

container_name=lyssna-keyring
service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Rebuild automatically when the entrypoint changes; never replace a live
# shared daemon behind existing clients. A changed image applies on recreation.
script_digest="$(shasum -a 256 "$service_dir/keyring.local.sh" | awk '{ print $1 }')"
image_name="lyssna-keyring:litterbox-${script_digest:0:12}"

if ! docker container inspect "$container_name" >/dev/null 2>&1; then
  if ! docker image inspect "$image_name" >/dev/null 2>&1; then
    docker build --tag "$image_name" --file - "$service_dir" <<'DOCKERFILE'
FROM debian:bookworm-slim
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends --yes \
    bash coreutils dbus-bin dbus-daemon gnome-keyring passwd util-linux \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --gid 1000 lyssna \
  && useradd --uid 1000 --gid 1000 --create-home lyssna
ENV HOME=/var/lib/lyssna-keyring \
    XDG_RUNTIME_DIR=/run/user/1000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
COPY keyring.local.sh /usr/local/bin/lyssna-keyring
RUN chmod 755 /usr/local/bin/lyssna-keyring
ENTRYPOINT ["/usr/local/bin/lyssna-keyring"]
DOCKERFILE
  fi
  # Simultaneous worktree starts may race; only one can claim the name.
  docker run --detach --name "$container_name" --restart unless-stopped \
    --label com.lyssna.keyring=litterbox \
    --volume lyssna-keyring-data:/var/lib/lyssna-keyring \
    --volume lyssna-keyring-runtime:/run/user/1000 \
    "$image_name" >/dev/null 2>&1 || true
fi

owner_label="$(docker container inspect --format '{{ index .Config.Labels "com.lyssna.keyring" }}' "$container_name")"
if [[ "$owner_label" != litterbox ]]; then
  echo "Error: $container_name already exists and is not Litterbox's keyring service." >&2
  exit 1
fi
if [[ "$(docker container inspect --format '{{ .State.Running }}' "$container_name")" != true ]]; then
  docker start "$container_name" >/dev/null 2>&1 || true
fi

# A responding bus alone is insufficient: Pup needs an unlocked collection.
for _ in {1..30}; do
  if docker exec --user 1000:1000 "$container_name" test -f /run/user/1000/.keyring-started \
    && docker exec --user 1000:1000 "$container_name" dbus-send --session \
    --print-reply --dest=org.freedesktop.secrets /org/freedesktop/secrets/aliases/default \
    org.freedesktop.DBus.Properties.Get \
    string:org.freedesktop.Secret.Collection string:Locked 2>/dev/null \
    | grep -q 'boolean false'; then
    exit 0
  fi
  sleep 1
done

echo "Error: shared Secret Service is not ready; inspect docker logs $container_name." >&2
exit 1
