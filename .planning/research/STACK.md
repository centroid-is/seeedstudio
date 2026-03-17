# Stack Research

**Domain:** Kernel module .deb packaging — IgH EtherCAT 1.6 with r8169 native driver on Jetson aarch64
**Researched:** 2026-03-17
**Confidence:** MEDIUM (core toolchain HIGH; Jetson-specific kernel header paths MEDIUM; r8169 on kernel 5.15 LOW pending validation)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| debhelper-compat | 13 | Debian packaging framework | Current standard compat level for Ubuntu 22.04; avoids deprecated `debian/compat` file; available in Jammy's default repo |
| dpkg-buildpackage | system (Ubuntu 22.04) | Produces .deb artifacts from debian/ directory | The only correct tool for building Debian packages; no alternatives at this layer |
| Pre-built module strategy (NOT DKMS) | n/a | Package contains compiled .ko files tied to 5.15.148-tegra | Jetson targets a locked, vendor-specific kernel — DKMS's value (rebuildability across kernel updates) doesn't apply here; pre-built avoids requiring gcc/kernel-headers on every target device |
| IgH EtherCAT Master | stable-1.6 (branch) | EtherCAT kernel module + userspace tools | The only actively-maintained open-source Linux EtherCAT master; stable-1.6 is the current production branch |
| autoconf | >= 2.60 | Generate ./configure from configure.ac | Required by IgH's bootstrap.sh; Ubuntu 22.04 ships 2.71 — no version pinning needed |
| automake | >= 1.9 | Generate Makefiles from Makefile.am | Required by IgH's bootstrap.sh; Ubuntu 22.04 ships 1.16.5 — no version pinning needed |
| libtool | any recent | Shared library portability for EtherCAT userspace | Required by IgH build system; ships with Ubuntu 22.04 |
| Docker | 24+ (buildx capable) | Reproducible build environment | Eliminates "works on my machine" kernel header problems; the build environment IS the package |

### Supporting Libraries / Build Dependencies

| Library / Package | Version | Purpose | When to Use |
|-------------------|---------|---------|-------------|
| build-essential | Ubuntu 22.04 stock | gcc, make, dpkg-dev | Always — base compiler toolchain |
| linux-headers-5.15.148-tegra | Must match `uname -r` exactly | Kernel headers for .ko compilation | Required at build time inside Docker; NOT needed on target after .deb install |
| nvidia-l4t-kernel-headers | JetPack 6.x version | NVIDIA's packaged form of Tegra kernel headers | Install via `sudo apt install nvidia-l4t-kernel-headers` on a Jetson or from NVIDIA's apt repository; installs to `/usr/src/linux-headers-$(uname -r)/` |
| dkms | 2.x | Dynamic kernel module support framework | **Do NOT use** for this project (see "What NOT to Use") |
| devscripts | Ubuntu 22.04 stock | `debchange`, `debuild` convenience wrappers | Optional but useful for changelog maintenance |
| fakeroot | Ubuntu 22.04 stock | Build .deb as non-root | Required for `dpkg-buildpackage -rfakeroot` |
| lintian | Ubuntu 22.04 stock | Debian package linter | Run in CI to catch packaging errors before release |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Docker (build environment) | Reproducible kernel-header-matched build | Base image: `ubuntu:22.04`; must `apt install nvidia-l4t-kernel-headers` matching the target kernel version |
| GitHub Actions `ubuntu-22.04-arm` runner | Native aarch64 CI builds | Available free for **public repos** since Jan 2025; use instead of QEMU emulation |
| `dpkg-buildpackage -us -uc -b` | Build binary-only .deb without signing | `-b` = binary only (no source .dsc); `-us -uc` = skip GPG signing in CI |
| `lintian --pedantic` | Package quality gate | Run after build; treat errors as CI failures |
| `gh release upload` | Publish .deb to GitHub Releases | Triggered on `v*` tag push |

---

## Installation (Build Environment Setup)

```bash
# Inside the Docker build container (ubuntu:22.04, aarch64)

# Core packaging tools
apt-get install -y \
  build-essential \
  debhelper \
  devscripts \
  fakeroot \
  lintian \
  autoconf \
  automake \
  libtool \
  pkg-config

# Jetson kernel headers — must match target kernel exactly
# Add NVIDIA's apt repo first (nvidia-l4t-apt-source configures it on real Jetson)
# For CI, pin the version:
apt-get install -y nvidia-l4t-kernel-headers=<version-matching-5.15.148-tegra>

# Verify headers are at expected path
ls /usr/src/linux-headers-5.15.148-tegra/
```

```yaml
# GitHub Actions — native aarch64 (public repo)
runs-on: ubuntu-22.04-arm
```

---

## The debian/ Directory Structure

This is a pre-built binary package (not DKMS). Required files:

```
debian/
  changelog          # Package version history (required)
  control            # Package metadata, build-deps, dependencies
  rules              # Build instructions (calls ./configure then make)
  compat             # NOT used — use debhelper-compat in control instead
  install            # Files to install and their destinations
  postinst           # Post-install script: depmod -a, service restart, MAC detection
  postrm             # Post-remove: cleanup
  modprobe.d/        # blacklist-eth.conf source
```

Key `debian/control` fields:
```
Build-Depends: debhelper-compat (= 13), build-essential, autoconf, automake, libtool,
               nvidia-l4t-kernel-headers (= ${kernel:Version})
Depends: kmod
Package: igh-seeedstudio
Architecture: arm64
```

Key `debian/rules` pattern:
```makefile
%:
	dh $@

override_dh_auto_configure:
	./bootstrap.sh
	./configure \
	  --with-linux-dir=/usr/src/linux-headers-5.15.148-tegra \
	  --enable-r8169 \
	  --disable-8139too \
	  --prefix=/opt/etherlab \
	  --sysconfdir=/etc

override_dh_auto_install:
	$(MAKE) DESTDIR=$(CURDIR)/debian/igh-seeedstudio install
	$(MAKE) DESTDIR=$(CURDIR)/debian/igh-seeedstudio modules_install
```

---

## IgH EtherCAT Build Flags Reference

| Flag | Value | Effect |
|------|-------|--------|
| `--with-linux-dir` | `/usr/src/linux-headers-5.15.148-tegra` | Points configure to the Tegra kernel headers |
| `--enable-r8169` | (presence = yes) | Builds the EtherCAT-native r8169 driver module (`ec_r8169.ko`) |
| `--disable-8139too` | (presence = yes) | Excludes the 8139too driver module from build (not needed, keeps package lean) |
| `--prefix` | `/opt/etherlab` | Userspace tool install path (convention from upstream) |
| `--sysconfdir` | `/etc` | Places `ethercat.conf` in `/etc/ethercat.conf` |
| `--enable-cycles` | optional | Uses CPU cycle counter for timestamps — safe to enable on aarch64 |

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Pre-built .deb (binary only) | DKMS package | When kernel version is not locked — e.g., desktop Ubuntu that receives kernel updates. Not appropriate for Jetson: adding gcc/headers to production Jetson bloats image and risks version drift. |
| Native `ubuntu-22.04-arm` GHA runner | QEMU emulation with `docker/setup-qemu-action` | When the project must be in a private GitHub repo (arm64 hosted runners are free only for public repos). QEMU is 5-10x slower for kernel module compilation. |
| Native `ubuntu-22.04-arm` GHA runner | Cross-compilation (x86_64 → aarch64) | Cross-compiling kernel modules is fragile: requires matching kernel config, cross-toolchain, and sysroot. For a Tegra kernel with vendor patches, it's not worth the complexity — native compilation is simpler and faster. |
| `ubuntu:22.04` Docker base | `nvcr.io/nvidia/l4t-base` or JetPack SDK | L4T containers are large, change frequently, and not needed just to compile a kernel module. A vanilla Ubuntu 22.04 container with `nvidia-l4t-kernel-headers` installed is sufficient and reproducible. |
| IgH EtherCAT stable-1.6 (official GitLab) | Downstream forks (tormach, ICube-Robotics, etc.) | Forks exist for specific use-cases (RTAI, custom hardware). Use upstream for standard r8169 on Tegra — fork code may contain incompatible patches or be out of date. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| DKMS packaging (`dh --with dkms`) | Forces gcc + kernel headers onto every Jetson target device; DKMS recompiles on kernel update but Jetson kernel is vendor-locked anyway; adds complexity with no benefit | Pre-built .deb with `.ko` compiled at package build time |
| `debhelper-compat` < 12 | Deprecated behavior; `debian/compat` file approach is legacy; Ubuntu 22.04's debhelper ships version 13 | `Build-Depends: debhelper-compat (= 13)` in `debian/control` |
| QEMU-based aarch64 CI on x86 runners | 5-10x slower; QEMU user-mode has known bugs with kernel 6.8+ hosts (docker/buildx issue #3170); kernel module builds occasionally fail silently under QEMU | `runs-on: ubuntu-22.04-arm` (native, free for public repos) |
| Cross-compilation for kernel modules | Requires matching kernel config, cross-toolchain, and Tegra sysroot; fails on subtle ABI mismatches in vendor-patched kernels; brittle to maintain | Native compilation on aarch64 runner |
| Hardcoding kernel header path in `Makefile` | Breaks when path changes between JetPack versions | Use `--with-linux-dir` configure flag; document exact kernel version in package changelog |
| `dpkg-buildpackage -sa` (source package upload) | Unnecessary for a binary-only CI artifact workflow | `dpkg-buildpackage -us -uc -b` (binary-only, unsigned) |
| `make install` then manual `dpkg --build` | Bypasses Debian packaging conventions; produces non-standard packages; hard to maintain | Proper `debian/` directory with `dpkg-buildpackage` |

---

## Stack Patterns by Variant

**If the project must be in a private GitHub repo:**
- Use `ubuntu-22.04` (x86_64) runner with `docker/setup-qemu-action@v3` + `runs-on: ubuntu-22.04` + `--platform linux/arm64` Docker build
- Accept the ~5x build time penalty from QEMU emulation
- Alternatively, use a self-hosted Jetson as a GitHub Actions runner (register with `./config.sh` + `./svc.sh install`)

**If Jetson kernel is updated (e.g., 5.15.148 → 5.15.160):**
- The compiled `.ko` files will not load on the new kernel
- Cut a new version of the package, rebuild against updated `nvidia-l4t-kernel-headers`
- This is expected behavior for pre-built kernel module packages; document in README
- This is NOT a reason to switch to DKMS unless you're supporting multiple kernel versions simultaneously

**If targeting multiple Jetson JetPack versions:**
- Build matrix: `matrix: [jetpack-6.0, jetpack-6.1]` with different `nvidia-l4t-kernel-headers` versions
- Produce separate .deb for each (e.g., `igh-seeedstudio_1.0.0_arm64_5.15.122-tegra.deb`)
- Out of scope for current requirements but documented for future reference

---

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| IgH EtherCAT stable-1.6 | Linux kernel 4.x – 5.15.x | Kernel 5.15 is within supported range; r8169 driver patches apply to stock 5.15 sources. Kernel 6.x support is NOT in stable-1.6 — requires master branch or forks. |
| nvidia-l4t-kernel-headers | Must exactly match `uname -r` on target Jetson | `5.15.148-tegra` headers are installed by JetPack 6.1; version mismatch causes `Exec format error` or unknown symbols at `insmod` time |
| debhelper-compat = 13 | Ubuntu 22.04 (Jammy) ships debhelper 13.6ubuntu1 | Compatible; no pinning needed |
| `ubuntu-22.04-arm` GHA runner | Public repos only (as of Jan 2025 public preview) | Free for public repos; private repos need alternative (self-hosted or QEMU) |
| autoconf 2.71 | IgH configure.ac (requires >= 2.60) | Ubuntu 22.04's version exceeds minimum — no issue |

---

## Sources

- [sittner/ec-debianize](https://github.com/sittner/ec-debianize) — Reference debian/ directory structure for IgH EtherCAT packaging (LOW confidence: targets older Debian/Stretch, DKMS-based approach)
- [ICube-Robotics/ethercat_igh_dkms](https://github.com/ICube-Robotics/ethercat_igh_dkms) — DKMS-based IgH EtherCAT packaging (reviewed and rejected for this use case)
- [NVIDIA Developer Forums: EtherCAT on Jetson Nano](https://forums.developer.nvidia.com/t/jetson-nano-install-preempt-rt-successfull-and-build-ethercat-igh-module-problem/232271) — Confirmed configure flags and kernel header path format (`--with-linux-dir=/usr/src/linux-headers-<ver>-tegra-ubuntu22.04_aarch64/`) (MEDIUM confidence)
- [GitHub Blog: Linux arm64 hosted runners public preview](https://github.blog/changelog/2025-01-16-linux-arm64-hosted-runners-now-available-for-free-in-public-repositories-public-preview/) — Confirmed `ubuntu-22.04-arm` label; free for public repos; Jan 2025 launch (HIGH confidence)
- [GitHub Actions Hosted Runners Reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) — Specs: 4-core, 16 GB RAM, 14 GB disk for public repo arm64 runners (HIGH confidence)
- [Debian Wiki: DkmsPackaging](https://wiki.debian.org/DkmsPackaging) — DKMS packaging structure and dh_dkms usage (HIGH confidence — used to confirm why DKMS is the wrong choice here)
- [Vincent Bernat: Packaging a driver for Debian with DKMS](https://vincent.bernat.ch/en/blog/2018-packaging-driver-debian-dkms) — Canonical reference for out-of-tree module Debian packaging patterns (MEDIUM confidence — 2018 article, patterns still valid)
- [docker/buildx issue #3170: QEMU segfault on Linux 6.8+](https://github.com/docker/buildx/issues/3170) — Confirmed QEMU emulation reliability issues (MEDIUM confidence — open issue)
- [InfoQ: GitHub Actions ARM64 runners](https://www.infoq.com/news/2025/02/github-actions-linux-arm64/) — Corroborating source for native arm64 runner availability (HIGH confidence)
- [NVIDIA L4T Kernel Headers Forum](https://forums.developer.nvidia.com/t/linux-header-missing-in-jetson-orin-nano/314205) — Confirms `nvidia-l4t-kernel-headers` package name and apt availability (MEDIUM confidence)

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| debhelper packaging toolchain | HIGH | Well-documented, stable tooling; debhelper 13 in Ubuntu 22.04 confirmed |
| Pre-built vs DKMS decision | HIGH | Clear tradeoff: Jetson kernel is vendor-locked; DKMS value proposition doesn't apply |
| IgH EtherCAT configure flags | MEDIUM | `--enable-r8169 --disable-8139too --with-linux-dir` confirmed from multiple forum posts; but r8169 on kernel 5.15 (vs older 4.9) needs build validation |
| Kernel header package name/path | MEDIUM | `nvidia-l4t-kernel-headers` confirmed as package name; exact path format (`/usr/src/linux-headers-5.15.148-tegra/`) needs verification on actual Jetson hardware or in CI |
| GitHub Actions arm64 runners | HIGH | Officially announced Jan 2025; labels confirmed from GitHub docs |
| QEMU unreliability for kernel modules | MEDIUM | Known issue with kernel 6.8+ hosts; confirmed open bug in docker/buildx |
| r8169 driver compatibility with kernel 5.15 | LOW | EtherCAT r8169 patches were originally written for 3.x/4.x kernels; community reports suggest patches apply to 5.15 but this needs empirical validation on the Tegra kernel specifically |

---

*Stack research for: IgH EtherCAT .deb packaging on Jetson aarch64*
*Researched: 2026-03-17*
