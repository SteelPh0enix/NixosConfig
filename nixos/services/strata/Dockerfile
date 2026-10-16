# syntax=docker/dockerfile:1
#
# Strata with the AMD (HIP) engine for gfx1100 - the RX 7900 XT in this box.
#
# Upstream's own Dockerfile is NVIDIA-only (nvidia/cuda base, nvcc build), so this is the same
# layout for the AMD path described in docs/AMD_HIP.md: the engine is compiled by setup.py and
# ROCm comes from AMD's TheRock wheels that setup installs into .venv, so no ROCm is needed in
# the base image.
#
# The wheels and the compile happen at build time rather than on the first container start, so
# the image carries a finished engine and the first start only downloads the model (~58 GB for
# the Coder plus its draft layer). docker build has no GPU, which is why the card architecture
# is stated below instead of read from KFD; the model setup runs on the first start, and it does
# have the card by then.
#
# Built by hand on this box (rootless docker is the default context):
#   cd ~/nixos-config
#   docker build -t strata-hip-gfx1100:latest \
#     -f nixos/services/strata/Dockerfile nixos/services/strata
#
# How to run it - port, model, context - is nix/settings.nix plus strata.nix next to this file.

FROM ubuntu:24.04

ARG STRATA_REPO=https://github.com/Niko1221/Strata.git
# Keep in step with settings.strataRev.
ARG STRATA_REV=v0.1.44.1
# One card family per image: AMD's ROCm wheels hold the kernels of a single family.
ARG AMD_ARCH=gfx1100

# STRATA_EXECV=1: setup.py replaces itself with the server, so the server is PID 1 and
# `docker stop`'s SIGTERM reaches it.
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    LANG=C.UTF-8 \
    STRATA_EXECV=1 \
    AMD_ARCH=${AMD_ARCH}

# build-essential and git: the engine build. cmake and ninja from apt rather than the pip wheels
# in requirements.txt, which is also what Strata's own flake does. libnuma1 is loaded by the HSA
# runtime; libgomp1 and libatomic1 are what the compiled engine links against.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates cmake curl git ninja-build python3 python3-venv \
        libatomic1 libgomp1 libnuma1 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone -q --depth 1 --branch "${STRATA_REV}" "${STRATA_REPO}" /opt/strata
WORKDIR /opt/strata

RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m venv .venv \
    && .venv/bin/pip install --upgrade pip \
    && .venv/bin/pip install -r requirements.txt

# TheRock's ROCm wheels for the card family (~10 GB) into .venv, then the engine for that
# architecture. build_engine_hip writes engine/BUILD.json, which records both the source hash and
# the ROCm library folders, so a later start reuses the engine and finds its libraries.
# Only the cmake tree goes: engine/BUILD.json fingerprints src, include, cmake and
# third_party/ggml (setup.py's ENGINE_SOURCES), so keeping third_party/ is what makes a start reuse
# this engine - delete it and every container compiles the engine again before serving.
RUN --mount=type=cache,target=/root/.cache/pip \
    .venv/bin/python -c 'import os, setup; a = os.environ["AMD_ARCH"]; setup.build_engine_hip({"arch": a, "archs": [a]}, setup.get_llama_cpp())' \
    && rm -rf build-hip

VOLUME ["/data"]
EXPOSE 8080

# /health is answered before the API-key gate. The start period covers a first run, which
# downloads the model: a shorter one would mark a still-downloading container unhealthy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=900s --retries=3 \
  CMD curl -fs "http://127.0.0.1:${PORT:-8080}/health" || exit 1

ENTRYPOINT ["./docker-entrypoint.sh"]
