# Build verification for igh-seeedstudio .deb package
# Validates: .deb builds from scratch, dpkg -i succeeds, ec_r8169.ko present
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# --- Build dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    dpkg-dev \
    debhelper \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    git \
    fakeroot \
    wget \
    bc flex bison libssl-dev \
    kmod \
    && rm -rf /var/lib/apt/lists/*

# --- Kernel source: L4T BSP for out-of-tree module builds ---
# The nvidia-l4t-kernel-headers apt package only provides unconfigured source
# (just 3rdparty/ directory). Download the official L4T R36.4 kernel source,
# configure with defconfig + LOCALVERSION=-tegra, and run modules_prepare to
# generate the build infrastructure (.config, include/generated/autoconf.h,
# scripts/, Module.symvers) needed by IgH EtherCAT's configure and make.
RUN cd /tmp && \
    wget -q https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v4.0/sources/public_sources.tbz2 && \
    tar xf public_sources.tbz2 --wildcards "*/kernel_src.tbz2" && \
    rm public_sources.tbz2 && \
    KSRC_TAR=$(find /tmp -name kernel_src.tbz2 -type f | head -1) && \
    tar xf "$KSRC_TAR" -C /usr/src && \
    rm -rf /tmp/Linux_for_Tegra "$KSRC_TAR"

# Configure the kernel source tree for out-of-tree module builds
RUN cd /usr/src/kernel/kernel-jammy-src && \
    make ARCH=arm64 defconfig && \
    scripts/config --file .config --set-str LOCALVERSION "-tegra" && \
    make ARCH=arm64 -j$(nproc) modules_prepare && \
    ln -sf /usr/src/kernel/kernel-jammy-src /usr/src/linux-headers-5.15.148-tegra && \
    echo "Kernel: $(make -s kernelrelease)"

# --- Copy source and build ---
COPY . /build/igh-seeedstudio
WORKDIR /build/igh-seeedstudio

# dpkg-buildpackage flags:
# -us/-uc: skip signatures  -b: binary-only  -d: skip build-deps check
# (-d needed because nvidia-l4t-kernel-headers not dpkg-installed)
RUN dpkg-buildpackage -us -uc -b -d

# --- Install verification ---
# postinst is Docker-safe (systemctl guarded, MAC detection has fallback)
RUN dpkg -i /build/igh-seeedstudio_1.6.8_arm64.deb

# --- Final assertions ---
RUN test -f /lib/modules/5.15.148-tegra/extra/devices/r8169/ec_r8169.ko && echo "PASS: ec_r8169.ko is present"
RUN test -f /lib/modules/5.15.148-tegra/extra/master/ec_master.ko && echo "PASS: ec_master.ko is present"
RUN test -x /usr/bin/ethercat && echo "PASS: ethercat CLI is present"
