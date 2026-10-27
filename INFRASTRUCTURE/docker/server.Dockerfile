# syntax=docker/dockerfile:1
# STRUCTURE images. Build through `python TOOLS/cli/structure.py build`, which bakes the build manifest
# into the image, adds labels and assigns a unique immutable tag. Defaults below must match
# INFRASTRUCTURE/builds/toolchain.json (verified by `structure.py check`).
#   runtime : headless dedicated server (default target)
#   tools   : Linux Godot + Python for running the test suites against a bind-mounted repo
ARG BASE_IMAGE=debian:trixie-slim@sha256:62bd423aeee912639ca8ee681c2b762cb3e25137e0a92b20be455898a9f034ad

FROM ${BASE_IMAGE} AS godot
ARG GODOT_VERSION=4.7.2-stable
ARG GODOT_ARCHIVE=Godot_v4.7.2-stable_linux.x86_64.zip
ARG GODOT_SHA256=cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/${GODOT_ARCHIVE}" \
 && echo "${GODOT_SHA256}  /tmp/godot.zip" | sha256sum -c - \
 && unzip -q /tmp/godot.zip -d /opt/godot \
 && mv /opt/godot/Godot_v*_linux.x86_64 /opt/godot/godot \
 && chmod 0755 /opt/godot/godot \
 && rm /tmp/godot.zip

FROM godot AS project
COPY SANDBOX/godot/ /app/project/
# Pre-build import caches (global class list, imported assets) so the server starts immediately.
RUN /opt/godot/godot --headless --path /app/project --import > /tmp/import.log 2>&1 \
 && ! grep -E '^(ERROR|SCRIPT ERROR):' /tmp/import.log

FROM ${BASE_IMAGE} AS runtime
RUN useradd --system --uid 10001 --create-home --home-dir /home/structure structure \
 && mkdir -p /data \
 && chown structure:structure /data
COPY --from=godot /opt/godot/godot /opt/godot/godot
COPY --from=project --chown=structure:structure /app/project /app/project
COPY INFRASTRUCTURE/docker/entrypoint.sh INFRASTRUCTURE/docker/healthcheck.sh /app/
RUN sed -i 's/\r$//' /app/entrypoint.sh /app/healthcheck.sh \
 && chmod 0755 /app/entrypoint.sh /app/healthcheck.sh
ENV HOME=/home/structure \
    STRUCTURE_DATA_DIR=/data \
    STRUCTURE_PORT=24565 \
    STRUCTURE_BIND_IP=* \
    STRUCTURE_ENV_ID=docker \
    STRUCTURE_WORLD_ID=dev \
    STRUCTURE_WORLD_SEED=1337
EXPOSE 24565/udp
VOLUME ["/data"]
USER structure
HEALTHCHECK --interval=5s --timeout=3s --start-period=30s --retries=3 CMD ["/app/healthcheck.sh"]
ENTRYPOINT ["/app/entrypoint.sh"]

FROM godot AS tools
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 \
 && rm -rf /var/lib/apt/lists/*
ENV STRUCTURE_GODOT=/opt/godot/godot
WORKDIR /repo
