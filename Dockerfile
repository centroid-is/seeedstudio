# Build verification for igh-seeedstudio .deb package
# Validates: .deb builds from scratch, dpkg -i succeeds, ec_r8169.ko present
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# --- Stage 2: ca-certificates (needed for HTTPS repos) ---
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates

# --- Stage 3: NVIDIA L4T apt repository ---
ADD https://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
    /etc/apt/trusted.gpg.d/jetson-ota-public.asc
RUN chmod 644 /etc/apt/trusted.gpg.d/jetson-ota-public.asc && \
    echo "deb https://repo.download.nvidia.com/jetson/common r36.4 main" \
      > /etc/apt/sources.list.d/nvidia-l4t-apt-source.list && \
    echo "deb https://repo.download.nvidia.com/jetson/t234 r36.4 main" \
      >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list

# --- Stage 4: Build dependencies (mirrors debian/control Build-Depends) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    dpkg-dev \
    debhelper \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    git \
    fakeroot \
    && rm -rf /var/lib/apt/lists/*

# --- Stage 5: Kernel headers extraction (bypass nvidia-l4t-core preinst) ---
# nvidia-l4t-kernel-headers depends on nvidia-l4t-kernel which pre-depends
# on nvidia-l4t-core. The nvidia-l4t-core preinst checks
# /proc/device-tree/compatible which does not exist in Docker containers.
# Use apt-get download + dpkg -x to extract headers without triggering
# the dependency chain's preinst scripts.
RUN apt-get update && \
    cd /tmp && \
    apt-get download nvidia-l4t-kernel-headers && \
    mkdir -p /tmp/headers && \
    dpkg -x nvidia-l4t-kernel-headers_*.deb /tmp/headers && \
    ls /tmp/headers/usr/src/ && \
    cp -a /tmp/headers/usr/src/* /usr/src/ && \
    rm -rf /tmp/headers /tmp/nvidia-l4t-kernel-headers_*.deb && \
    rm -rf /var/lib/apt/lists/*

# Create symlink if headers directory has a different name than expected
RUN ls /usr/src/ && \
    if [ ! -d /usr/src/linux-headers-5.15.148-tegra ]; then \
      ACTUAL=$(ls -d /usr/src/linux-headers-5.15.148* 2>/dev/null | head -1) && \
      ln -s "$ACTUAL" /usr/src/linux-headers-5.15.148-tegra; \
    fi && \
    test -d /usr/src/linux-headers-5.15.148-tegra

# --- Stage 6: Copy source and build ---
COPY . /build/igh-seeedstudio
WORKDIR /build/igh-seeedstudio

# Build the .deb package
# -us: no source signature
# -uc: no changes signature
# -b:  binary-only build
# Note: ec_r8169.ko assertion is already in debian/rules override_dh_auto_build
# Note: dpkg-buildpackage outputs .deb to parent directory /build/
RUN dpkg-buildpackage -us -uc -b

# --- Stage 7: Install verification ---
# postinst is Docker-safe: systemctl guarded by /run/systemd/system check,
# MAC detection has graceful fallback. Do NOT use "|| true" here -- we want
# dpkg -i to fail loudly if install breaks.
RUN dpkg -i /build/igh-seeedstudio_1.6.0_arm64.deb

# --- Stage 8: Final assertions ---
RUN test -f /lib/modules/5.15.148-tegra/extra/ec_r8169.ko && echo "PASS: ec_r8169.ko is present"
RUN test -f /lib/modules/5.15.148-tegra/extra/ec_master.ko && echo "PASS: ec_master.ko is present"
RUN test -x /usr/bin/ethercat && echo "PASS: ethercat CLI is present"
