# The Linux half of the local file system's platform check: the Linux Dart VM
# of the same version that compiled the kernel file, and the freedesktop.org
# trash tools the file system prefers to its own fallback.
FROM debian:bookworm-slim
ARG DART_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip libglib2.0-bin \
    && rm -rf /var/lib/apt/lists/*
RUN arch="$(dpkg --print-architecture | sed 's/amd64/x64/')" \
    && curl -sSfL -o /tmp/dart.zip \
      "https://storage.googleapis.com/dart-archive/channels/stable/release/$DART_VERSION/sdk/dartsdk-linux-$arch-release.zip" \
    && unzip -q /tmp/dart.zip -d /opt && rm /tmp/dart.zip
ENV PATH=/opt/dart-sdk/bin:$PATH
WORKDIR /work
