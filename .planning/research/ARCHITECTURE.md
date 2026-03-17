# Architecture Research

**Domain:** Kernel module .deb packaging — IgH EtherCAT Master on NVIDIA Jetson (aarch64)
**Researched:** 2026-03-17
**Confidence:** HIGH (core Debian packaging patterns well-documented; Jetson-specific header paths MEDIUM)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     CI/CD Layer (GitHub Actions)                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │  build job   │  │  test job    │  │   release job        │   │
│  │ (on: push)   │  │ (docker      │  │   (on: v* tag)       │   │
│  │              │  │  install     │  │   softprops/action-  │   │
│  │              │  │  verify)     │  │   gh-release         │   │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘   │
└─────────┼─────────────────┼───────────────────────┼─────────────┘
          │                 │                       │
          ▼                 ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Build Environment (Docker)                      │
│  ubuntu:22.04-aarch64 (QEMU or native arm64 runner)             │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Build deps: build-essential, automake, autoconf,          │  │
│  │              debhelper, linux-headers-5.15.148-tegra,      │  │
│  │              devscripts, fakeroot                          │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Source Package Layout                            │
│  igh-seeedstudio-<ver>/                                          │
│  ├── debian/               ← Debian packaging metadata           │
│  │   ├── control           ← Package metadata + build-deps       │
│  │   ├── rules             ← Build instructions (debhelper)      │
│  │   ├── changelog         ← Version history (required by dpkg)  │
│  │   ├── compat            ← debhelper compat level (13)         │
│  │   ├── copyright         ← License declaration (GPL-2)         │
│  │   ├── postinst          ← depmod -a, systemctl, MAC detection  │
│  │   ├── prerm             ← systemctl stop ethercat             │
│  │   ├── postrm            ← depmod -a cleanup                   │
│  │   ├── conffiles         ← /etc/ethercat.conf (opt — see note) │
│  │   ├── install           ← Extra file install mappings         │
│  │   └── source/format     ← "3.0 (quilt)" or "3.0 (native)"    │
│  └── (upstream source embedded or fetched at build time)        │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Installed Package Layout (target Jetson)         │
│  /lib/modules/5.15.148-tegra/extra/                              │
│    ec_master.ko                                                  │
│    ec_r8169.ko                                                   │
│  /etc/ethercat.conf          ← MASTER0_DEVICE=<MAC>             │
│  /etc/modprobe.d/                                                │
│    blacklist-eth.conf        ← blacklist r8168, blacklist r8169  │
│  /usr/bin/ethercat           ← CLI tool                          │
│  /usr/lib/libethercat.so.*   ← shared library                   │
│  /lib/systemd/system/ethercat.service                            │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `debian/control` | Declares package name, version, arch, maintainer, Build-Depends, Depends, Description | Static file, `Architecture: arm64`, `Build-Depends: linux-headers-5.15.148-tegra` |
| `debian/rules` | Orchestrates full build: configure → make → make modules → debhelper install | `dh $@` with `override_dh_auto_configure` calling `./configure --enable-r8169 --with-linux-dir=...` |
| `debian/changelog` | Required by dpkg; carries package version that appears in the .deb filename | Generated or maintained manually with `dch` |
| `debian/postinst` | Runs after files are unpacked on target; calls `depmod -a`, detects MAC from `enP8p1s0`, writes `/etc/ethercat.conf`, enables+starts ethercat.service | Shell script; must be idempotent |
| `debian/prerm` | Runs before files are removed; stops and disables ethercat.service | Short shell script |
| `debian/postrm` | Runs after files are removed; calls `depmod -a` to clean up module index | Short shell script |
| `debian/conffiles` | Marks config files dpkg should not silently overwrite on upgrade | `/etc/ethercat.conf` — BUT if postinst writes it dynamically, do NOT list it here (dpkg conflict); omit or use volatile approach |
| `debian/install` | Maps extra installed files not placed by `make install` | `etc/modprobe.d/blacklist-eth.conf  etc/modprobe.d/` |
| `Dockerfile` | Reproducible build environment; installs build deps, runs `dpkg-buildpackage`, verifies `dpkg -i` | `FROM ubuntu:22.04`, `COPY . /src`, `RUN dpkg-buildpackage ...` |
| `.github/workflows/ci.yml` | Builds .deb on every push; creates GitHub Release with .deb on v* tag push | `on: push` + `on: push: tags: ['v*']`; uses `jtdor/build-deb-action` or direct `dpkg-buildpackage` |

## Recommended Project Structure

```
igh-seeedstudio/
├── debian/
│   ├── control              # Package metadata, Build-Depends, Depends
│   ├── rules                # debhelper build script
│   ├── changelog            # Package version history (required)
│   ├── compat               # debhelper compat level: 13
│   ├── copyright            # GPL-2 (IgH EtherCAT license)
│   ├── postinst             # depmod, MAC detect, ethercat.conf write, service enable
│   ├── prerm                # service stop/disable
│   ├── postrm               # depmod -a
│   ├── install              # blacklist-eth.conf → /etc/modprobe.d/
│   └── source/
│       └── format           # "3.0 (native)" for single-source approach
├── etc/
│   └── modprobe.d/
│       └── blacklist-eth.conf   # blacklist r8168\nblacklist r8169
├── Dockerfile               # Build + install verification environment
├── .github/
│   └── workflows/
│       └── ci.yml           # Build on push; release .deb on v* tag
└── README.md                # Build instructions, usage
```

### Structure Rationale

- **`debian/`:** All Debian packaging metadata lives here; `dpkg-buildpackage` reads this directory.
- **`etc/modprobe.d/`:** Ships the blacklist as a static file installed via `debian/install`. More reliable than writing it from postinst, and dpkg tracks it for removal.
- **No upstream source vendored:** IgH EtherCAT source is fetched in `debian/rules` `override_dh_auto_build` or via a `get-orig-source` target, keeping the repo small. Alternative: vendor the tarball as a native package (simpler for CI).
- **`3.0 (native)` source format:** Simplest for a single-repo approach — no upstream tarball separation required.

## Architectural Patterns

### Pattern 1: Static Kernel Module Package (non-DKMS)

**What:** Kernel modules are compiled once against the pinned kernel headers version and shipped as pre-compiled `.ko` files inside the `.deb`. No DKMS involved.

**When to use:** Target kernel is known and fixed (Tegra 5.15.148 on Jetson). Users install via `dpkg -i` and get a working binary immediately. Simpler postinst; no DKMS daemon needed.

**Trade-offs:**
- Pro: Zero runtime compilation on target. Simpler install. No DKMS dependency.
- Con: .deb is kernel-version-specific. If Tegra kernel updates, package must be rebuilt. The package name should encode the kernel version (e.g. `igh-seeedstudio-5.15.148-tegra`).

**Example debian/rules skeleton:**

```makefile
#!/usr/bin/make -f
export DH_VERBOSE = 1

KDIR := /usr/src/linux-headers-5.15.148-tegra

%:
	dh $@

override_dh_auto_configure:
	./bootstrap
	./configure \
	    --prefix=/usr \
	    --sysconfdir=/etc \
	    --with-linux-dir=$(KDIR) \
	    --enable-r8169 \
	    --disable-8139too \
	    --disable-e1000 \
	    --disable-e1000e \
	    --disable-igb \
	    --enable-generic

override_dh_auto_install:
	$(MAKE) DESTDIR=$(CURDIR)/debian/igh-seeedstudio install
	$(MAKE) DESTDIR=$(CURDIR)/debian/igh-seeedstudio modules_install \
	    INSTALL_MOD_PATH=$(CURDIR)/debian/igh-seeedstudio
```

### Pattern 2: postinst MAC Auto-Detection + Config Write

**What:** The `postinst` script reads the MAC address of the hardcoded NIC (`enP8p1s0`) using `ip link show` or `cat /sys/class/net/enP8p1s0/address`, then writes `/etc/ethercat.conf` only if it does not already exist (or always overwrites — choose a policy).

**When to use:** Every time, because MAC is hardware-specific and cannot be known at build time.

**Trade-offs:**
- Pro: Fully automated install experience. No user config required.
- Con: MAC auto-detection must be robust (NIC naming is predictable on this hardware, but still a runtime dependency). Script must handle NIC-not-found gracefully.

**Example postinst snippet:**

```bash
#!/bin/sh
set -e

case "$1" in
  configure)
    MAC=$(cat /sys/class/net/enP8p1s0/address 2>/dev/null || true)
    if [ -z "$MAC" ]; then
      echo "WARNING: enP8p1s0 not found — set MASTER0_DEVICE in /etc/ethercat.conf manually"
      MAC="ff:ff:ff:ff:ff:ff"
    fi

    cat > /etc/ethercat.conf <<EOF
MASTER0_DEVICE="$MAC"
DEVICE_MODULES="r8169"
EOF

    depmod -a
    systemctl daemon-reload
    systemctl enable ethercat.service || true
    systemctl restart ethercat.service || true
    ;;
esac
```

**Key rule:** `/etc/ethercat.conf` must NOT be in `debian/conffiles` if postinst generates it. dpkg would otherwise show a conffile conflict on every upgrade. Instead, it is a "volatile" generated config managed entirely by the maintainer script.

### Pattern 3: Blacklist as Shipped conffile

**What:** `etc/modprobe.d/blacklist-eth.conf` ships as a static file tracked by dpkg. Content: `blacklist r8168` and `blacklist r8169`. Installed via `debian/install` mapping.

**When to use:** Always. This file is static — same content on every install — so shipping it as a package file (not generated by postinst) is cleaner and dpkg removes it automatically on uninstall.

**Trade-offs:**
- Pro: dpkg manages lifecycle. No postinst logic needed for blacklist. Upgrade-safe (dpkg prompts user only if they modified it).
- Con: Cannot be dynamically parameterized (not needed here).

**Note on blacklist semantics:** `blacklist r8169` alone is not sufficient to prevent autoloading via udev. Use `install r8169 /bin/false` (soft block) or ensure the EtherCAT ec_r8169 module is loaded first. The project requirement to blacklist both r8168 + r8169 is correct. Consider also `softdep ec_master pre: ec_r8169` in a separate modprobe.d file.

## Data Flow

### Build Flow (Source → .deb)

```
git clone etherlab.org/ethercat stable-1.6
         │
         ▼
   bootstrap (autoconf/automake)
         │
         ▼
   ./configure --enable-r8169
               --with-linux-dir=/usr/src/linux-headers-5.15.148-tegra
               --disable-<other drivers>
         │
         ▼
   make all              ← builds: ethercat CLI, libethercat.so, ec_master.ko, ec_r8169.ko
         │
         ▼
   make DESTDIR=... install        ← places binaries, libs, service files
   make DESTDIR=... modules_install ← places .ko files under lib/modules/...
         │
         ▼
   dh_fixperms / dh_strip / dh_shlibdeps / dh_gencontrol
         │
         ▼
   dpkg-deb --build → igh-seeedstudio_<ver>_arm64.deb
```

### Install Flow (.deb → running Jetson)

```
dpkg -i igh-seeedstudio_<ver>_arm64.deb
         │
         ├── dpkg unpacks files:
         │     /lib/modules/5.15.148-tegra/extra/ec_master.ko
         │     /lib/modules/5.15.148-tegra/extra/ec_r8169.ko
         │     /usr/bin/ethercat
         │     /usr/lib/libethercat.so.*
         │     /etc/modprobe.d/blacklist-eth.conf
         │     /lib/systemd/system/ethercat.service
         │
         └── postinst runs:
               detect MAC from enP8p1s0
               write /etc/ethercat.conf
               depmod -a
               systemctl daemon-reload
               systemctl enable ethercat.service
               systemctl restart ethercat.service
```

### CI/CD Flow (GitHub Actions)

```
git push (any branch)
         │
         ▼
   workflow: build job
     docker run ubuntu:22.04 aarch64
       apt-get install build-essential automake linux-headers-5.15.148-tegra ...
       dpkg-buildpackage -us -uc -b
       dpkg -i igh-seeedstudio*.deb          ← install verification (no module load)
         │
         ▼
   artifact upload (igh-seeedstudio*.deb)

git push tag v1.2.3
         │
         ▼
   workflow: release job (triggers on v* tags)
     (same build as above)
     softprops/action-gh-release
       files: igh-seeedstudio*.deb
       → creates GitHub Release
       → attaches .deb as release asset
```

### Key Data Flows

1. **Kernel headers at build time:** `linux-headers-5.15.148-tegra` must be installed in the Docker build environment. This is the most critical dependency — headers must match the Tegra kernel exactly. Source: NVIDIA L4T apt repository (developer.download.nvidia.com/compute/cuda/repos or Jetson apt feeds).

2. **MAC address at install time:** `enP8p1s0` MAC is read from sysfs by postinst on the target Jetson. This is a runtime dependency — the .deb contains no MAC information.

3. **Module loading at runtime:** After install, `ethercat.service` loads `ec_master` and `ec_r8169` via modprobe. The blacklist ensures stock r8168/r8169 do not conflict.

## Scaling Considerations

This is a single-hardware-target packaging project. "Scaling" means supporting additional Jetson variants or kernel versions.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Single Jetson + single kernel (current scope) | Static .ko in .deb, hardcoded kernel version in Build-Depends |
| Multiple kernel versions | One .deb per kernel version, matrix build in CI, package name encodes kernel version |
| Multiple Jetson variants | Parameterize NIC name in postinst; detect interface by driver rather than name |
| Multi-NIC support | Drop hardcoded `enP8p1s0`; iterate over interfaces with r8169 driver |

## Anti-Patterns

### Anti-Pattern 1: Listing Generated Conffiles in `debian/conffiles`

**What people do:** Add `/etc/ethercat.conf` to `debian/conffiles` because it is a config file in `/etc`.

**Why it's wrong:** `debian/conffiles` is for files dpkg ships verbatim from the package archive. If postinst generates the file dynamically (with the MAC address), dpkg does not know the "original" value and will prompt users with conffile conflict dialogs on every upgrade, even when nothing changed in the package.

**Do this instead:** Omit `/etc/ethercat.conf` from `debian/conffiles`. Let postinst own it entirely. On upgrade, postinst regenerates the file only if needed (check `$1 = configure` vs `$1 = upgrade`).

### Anti-Pattern 2: Relying on DKMS for a Fixed-Target Package

**What people do:** Use DKMS to compile modules at install time so the package is "kernel-agnostic."

**Why it's wrong:** The Tegra kernel headers are not available on the target Jetson at install time in the same way they are in a standard Ubuntu environment. DKMS adds a hard runtime build dependency. On an embedded Jetson, this adds build tools to a deployment target — heavyweight and fragile. Also adds complexity to postinst and introduces build-time failures at customer sites.

**Do this instead:** Build the static `.ko` in CI against the pinned Tegra headers. Ship pre-compiled `.ko` files. The package is kernel-version-specific, which is acceptable and explicit.

### Anti-Pattern 3: Using `blacklist` Without `install ... /bin/false` for Critical Conflicts

**What people do:** Add `blacklist r8169` to modprobe.d and assume the stock driver will not load.

**Why it's wrong:** `blacklist` prevents automatic loading by udev aliases but does NOT prevent explicit `modprobe r8169` or loading by other means. If the stock r8169 is already loaded when the package is installed, the blacklist has no effect until reboot.

**Do this instead:** Use `install r8169 /bin/false` in modprobe.d to hard-block the module. The postinst should also attempt `modprobe -r r8169 r8168` before starting the ethercat service. Accept that a reboot may be required after first install.

### Anti-Pattern 4: Fetching IgH Source Inside `debian/rules` with `git clone`

**What people do:** Clone the EtherCAT git repository inside the `debian/rules` build step to get the latest source.

**Why it's wrong:** Breaks reproducible builds. Network access in `dpkg-buildpackage` is unreliable in CI environments. Build output depends on upstream branch state, not the tagged package version.

**Do this instead:** Vendor the IgH EtherCAT source tarball in the repository, or use the Debian `3.0 (quilt)` source format with `debian/watch` and `uscan` to download and verify it at source-package creation time, not at binary build time. For a simple project like this, vendoring the stable-1.6 tarball alongside the `debian/` directory is the most straightforward approach.

### Anti-Pattern 5: Building on x86_64 Without Emulation

**What people do:** Run `dpkg-buildpackage` on a standard x86_64 GitHub Actions runner and assume the .ko files will work on aarch64 Jetson.

**Why it's wrong:** Kernel modules must be compiled for the target architecture. An x86_64-compiled `.ko` will not load on aarch64. Cross-compilation is possible but complex (requires cross-compiler toolchain and cross-compiled kernel headers).

**Do this instead:** Use QEMU aarch64 emulation (`uraimo/run-on-arch-action` or `docker buildx` with `--platform linux/arm64`) or a native ARM64 GitHub Actions runner. QEMU is slower but simpler and free on GitHub-hosted runners. Native ARM64 runners (e.g., via Blacksmith) are faster but cost money.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| NVIDIA L4T apt feed | apt source in Dockerfile: `deb https://repo.download.nvidia.com/jetson/t234 r35.5 main` (example) | Provides `linux-headers-5.15.148-tegra`; exact repo URL varies by Jetson generation and L4T version |
| IgH EtherCAT GitLab | `git clone --branch stable-1.6 https://gitlab.com/etherlab.org/ethercat.git` | Used to vendor or fetch source; stable-1.6 is the target branch per PROJECT.md |
| GitHub Actions `jtdor/build-deb-action` | Wraps `dpkg-buildpackage` in a Docker container; `host-arch: arm64` for cross or `docker-image: arm64v8/ubuntu:22.04` for native | Simplest CI integration for .deb building |
| `softprops/action-gh-release` | Upload .deb to GitHub Release; triggered on `v*` tags | Requires `permissions: contents: write` |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `debian/rules` ↔ IgH source tree | `./configure` + `make` invocations via debhelper overrides | rules must know the path to kernel headers; pass via env var or hardcode for this pinned target |
| `postinst` ↔ systemd | `systemctl` calls | postinst must use `|| true` on restart to avoid failing install on systems without network/NIC; check systemd availability first |
| `postinst` ↔ sysfs | `cat /sys/class/net/enP8p1s0/address` | Fragile if run in Docker (NIC not present); postinst must gracefully degrade with a warning, not a hard exit |
| Dockerfile ↔ .deb | `dpkg -i` inside container | Cannot test module loading in Docker; verifies install-side postinst runs without error (NIC absent = degraded mode) |
| CI build job ↔ release job | `actions/upload-artifact` / `actions/download-artifact` | Pass .deb between jobs in same workflow run |

## Build Order (Phase Dependencies)

```
1. Kernel headers available in build env
         ↓
2. IgH EtherCAT source vendored/fetched (stable-1.6)
         ↓
3. autoconf bootstrap (./bootstrap or autoreconf)
         ↓
4. ./configure --enable-r8169 --with-linux-dir=<headers>
         ↓
5. make (userspace: libethercat, ethercat CLI)
         ↓
6. make modules (kernel: ec_master.ko, ec_r8169.ko)
         ↓
7. make DESTDIR=... install && make DESTDIR=... modules_install
         ↓
8. dh_fixperms, dh_strip, dh_shlibdeps, dh_gencontrol
         ↓
9. dpkg-deb --build → igh-seeedstudio_<ver>_arm64.deb
         ↓
10. (on tag) GitHub Release with .deb artifact
```

Steps 3-6 depend on correct kernel headers path. If headers are wrong version, step 6 (modules) will fail with symbol errors. Validate headers match exactly: `uname -r` on target vs. package name in Build-Depends.

## Sources

- Debian Maintainers' Guide — Chapter 5: https://www.debian.org/doc/manuals/maint-guide/dother.en.html
- Debian DkmsPackaging wiki: https://wiki.debian.org/DkmsPackaging
- Debian Policy — Conffiles handling: https://www.debian.org/doc/debian-policy/ap-pkg-conffiles.html
- DpkgConffileHandling: https://wiki.debian.org/DpkgConffileHandling
- IgH EtherCAT Master (ec-debianize, zultron): https://github.com/zultron/ec-debianize
- IgH EtherCAT Master (ec-debianize, sittner): https://github.com/sittner/ec-debianize
- IgH EtherCAT DKMS packaging: https://github.com/ICube-Robotics/ethercat_igh_dkms
- etherlabmaster build environment: https://github.com/icshwi/etherlabmaster
- `jtdor/build-deb-action` GitHub Action: https://github.com/jtdor/build-deb-action
- `uraimo/run-on-arch-action` GitHub Action: https://github.com/uraimo/run-on-arch-action
- Debian Kernel Handbook — Modules chapter: https://kernel-team.pages.debian.net/kernel-handbook/ch-modules.html
- xkyle.com — Building Linux packages for kernel drivers: https://xkyle.com/building-linux-packages-for-kernel-drivers/
- pi3g.com — Configuration files in /etc: https://pi3g.com/creating-configuration-files-in-etc-in-debian-packages/

---
*Architecture research for: IgH EtherCAT .deb packaging on NVIDIA Jetson (aarch64)*
*Researched: 2026-03-17*
