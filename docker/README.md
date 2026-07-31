# Prebuilt sandbox images

The Dockerfile installs the pinned CLI tooling once, while `toolkit/` remains a
mixin for runtime policy, credentials, egress and host skills.

The image base must match the agent used to launch the sandbox. Build one image
for each agent you use:

```sh
cd ~/projects/litterbox/docker

# Shell
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg BASE_IMAGE=docker/sandbox-templates:shell-docker \
  -t docker.io/toby/litterbox:shell-v1 \
  --push -f Dockerfile .

# Claude, if needed
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg BASE_IMAGE=docker/sandbox-templates:claude-code-docker \
  -t docker.io/toby/litterbox:claude-v1 \
  --push -f Dockerfile .
```

Replace `docker.io/toby/litterbox` with a registry and repository you control.
The image contains no credentials. Use it with the toolkit mixin:

```sh
sbx run shell \
  --template docker.io/toby/litterbox:shell-v1 \
  --kit ~/projects/litterbox/toolkit .
```

For a local image, build it with a single-platform tag, save it, and load it
into sbx:

```sh
cd ~/projects/litterbox/docker
docker build \
  --build-arg BASE_IMAGE=docker/sandbox-templates:shell-docker \
  -t litterbox:shell-v1 -f Dockerfile .
docker image save litterbox:shell-v1 -o litterbox-shell.tar
sbx template load litterbox-shell.tar
sbx run shell --template litterbox:shell-v1 --kit ~/projects/litterbox/toolkit .
```

Update pinned versions in `install-tools.sh`, rebuild each image, and use a new
sandbox name or remove/recreate the existing sandbox. `sbx run` reconnects to an
existing sandbox for the workspace, so changing `--template` does not replace
it. Existing sandboxes are not changed when a template tag is rebuilt:

```sh
sbx rm shell-litterbox
sbx run shell --template litterbox:shell-v1 --kit ~/projects/litterbox/toolkit .
```

Alternatively, test with a new name:

```sh
sbx run --name shell-litterbox-v1 shell \
  --template litterbox:shell-v1 \
  --kit ~/projects/litterbox/toolkit .
```
