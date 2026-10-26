# The Windows half of the local file system's platform check: the Windows Dart
# VM, run under Wine. Wine is Wine's implementation of Windows, not Windows —
# what it shows is that the Windows code paths run and call what they mean to.
FROM --platform=linux/amd64 debian:bookworm-slim
ARG DART_VERSION
RUN dpkg --add-architecture i386 && apt-get update \
    && apt-get install -y --no-install-recommends wine wine64 curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN curl -sSfL -o /tmp/dart.zip \
      "https://storage.googleapis.com/dart-archive/channels/stable/release/$DART_VERSION/sdk/dartsdk-windows-x64-release.zip" \
    && unzip -q /tmp/dart.zip -d /opt && rm /tmp/dart.zip
ENV WINEDEBUG=-all WINEPREFIX=/tmp/wine
