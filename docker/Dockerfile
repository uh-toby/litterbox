# Build an image for a specific sbx agent. The base image must match the agent
# used with --template (for example, shell-docker with `sbx run shell`).
ARG BASE_IMAGE=docker/sandbox-templates:shell-docker
FROM ${BASE_IMAGE}

USER root

ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}

COPY install-tools.sh /tmp/install-tools.sh
RUN /tmp/install-tools.sh && rm /tmp/install-tools.sh

USER agent
