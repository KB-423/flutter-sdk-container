FROM fedora:30

ARG FLUTTER_VERSION

ENV FLUTTER_HOME=/flutter
ENV PATH=/flutter/bin:$PATH
ENV PUB_CACHE=/${FLUTTER_HOME}/.pub-cache

# Install required build tools, libraries, and utilities for Flutter Linux desktop development
RUN dnf install -y \
curl \
git \
unzip \
xz \
zip \
mesa-libGLU \
clang \
cmake \
ninja-build \
pkg-config \
gtk3-devel \
findutils \
which \
egl-utils && \
dnf clean all && \
rm -rf /var/cache/dnf

WORKDIR /workspace
ENV PUB_CACHE=/var/pub-cache

# Clone Flutter SDK (FLUTTER_VERSION must be provided via build-arg), configure git safe directory, disable analytics, precache Linux artifacts, and set permissions
RUN if [ -z "$FLUTTER_VERSION" ]; then echo "Error: FLUTTER_VERSION build argument is required" >&2; exit 1; fi && \
git clone https://github.com/flutter/flutter.git -b ${FLUTTER_VERSION} --depth=1 /flutter && \
git config --system --add safe.directory '*' && \
/flutter/bin/flutter config --no-analytics && \
/flutter/bin/dart --disable-analytics && \
/flutter/bin/flutter doctor -v && \
/flutter/bin/flutter precache --linux && \
chmod -R a+rwX /flutter /var/pub-cache /workspace

CMD ["flutter", "--version"]
