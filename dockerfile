FROM fedora:30

ARG FLUTTER_VERSION=3.47.7

ENV FLUTTER_ROOT=/flutter
ENV PATH=/flutter/bin:$PATH
ENV PUB_CACHE=/root/.pub-cache

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

# Clone Flutter SDK, configure git safe directory, disable analytics, precache Linux artifacts, and set permissions
RUN git clone https://github.com/flutter/flutter.git -b ${FLUTTER_VERSION} --depth=1 /flutter && \
    git config --system --add safe.directory '*' && \
    /flutter/bin/flutter config --no-analytics && \
    /flutter/bin/dart --disable-analytics && \
    /flutter/bin/flutter doctor -v && \
    /flutter/bin/flutter precache --linux && \
    chmod -R a+rwX /flutter

WORKDIR /workspace

CMD ["flutter", "--version"]
