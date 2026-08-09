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
The image contains no credentials. Put options before the agent name:

```sh
cd ~/projects/litterbox/docker
docker buildx build \
  --platform linux/arm64,linux/amd64 \
  --build-arg BASE_IMAGE=docker/sandbox-templates:shell-docker \
  -t YOUR_REGISTRY/litterbox:shell-v1 \
  --push -f Dockerfile .
```

Then create a fresh sandbox using the fully-qualified reference:

```sh
sbx run \
  --template YOUR_REGISTRY/litterbox:shell-v1 \
  --kit ~/projects/litterbox/toolkit \
  --name tmp \
  shell .
```

The image contains no credentials. Put options before the agent name:

```sh
sbx run \
  --template docker.io/toby/litterbox:shell-v1 \
  --kit ~/projects/litterbox/toolkit \
  shell .
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
sbx run --template litterbox:shell-v1 --kit ~/projects/litterbox/toolkit shell .
```

The reliable way to use a custom image is to push it to a registry and pass the
fully-qualified image reference to `sbx`. On sbx 0.37.x, locally loading an image
derived from a `sandbox-templates` image can retain the base shell template at
sandbox creation time even though `sbx template ls` shows the custom tag. If you
need to test locally, use the load procedure below and verify the tools inside a
new sandbox; otherwise use a registry image.

Update pinned versions in `install-tools.sh`, rebuild and publish the image, then
use a new sandbox name or remove/recreate the existing sandbox. `sbx run`
reconnects to an existing sandbox for the workspace, so changing `--template`
does not replace it. Existing sandboxes are not changed when a template tag is
rebuilt:

```sh
sbx rm shell-litterbox
sbx run --template litterbox:shell-v1 --kit ~/projects/litterbox/toolkit shell .
```

Alternatively, test with a new name:

```sh
sbx run --name shell-litterbox-v1 \
  --template litterbox:shell-v1 \
  --kit ~/projects/litterbox/toolkit \
  shell .
```
