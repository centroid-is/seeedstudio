# IgH EtherCAT for SeeedStudio Jetson

## What This Is

A Debian package (`igh-seeedstudio`) that builds and installs the IgH EtherCAT Master 1.6 with the r8169 native driver on NVIDIA Jetson platforms running Tegra L4T kernel 5.15.148. Includes a Dockerfile for build verification, GitHub Actions CI that builds the .deb and publishes it as a GitHub Release artifact on tag push.

## Core Value

A single `dpkg -i` installs a working EtherCAT master on a Jetson with the Realtek r8169 NIC — no manual compilation or configuration steps.

## Requirements

### Validated

- ✓ .deb package builds IgH EtherCAT 1.6 from official source (stable-1.6) — v1.0
- ✓ Package configures with --enable-r8169 against Tegra kernel headers (5.15.148-tegra) — v1.0
- ✓ Package installs blacklist-eth.conf to /etc/modprobe.d/ (blacklists stock r8168 + r8169) — v1.0
- ✓ Package installs ethercat.conf with MASTER0_DEVICE=<MAC> and DEVICE_MODULES="r8169" — v1.0
- ✓ Post-install runs depmod -a and restarts ethercat service — v1.0
- ✓ Post-install auto-detects MAC address from enP8p1s0 — v1.0
- ✓ Dockerfile verifies the .deb builds cleanly and installs without errors — v1.0
- ✓ GitHub Actions CI builds .deb on push, creates GitHub Release on v* tag — v1.0
- ✓ CI monitors build status (watchable via gh run watch) — v1.0

### Active

(None — define with /gsd:new-milestone)

### Out of Scope

- Multi-NIC support — hardcoded to enP8p1s0
- Non-Tegra platforms — Jetson-only for now
- Runtime EtherCAT slave testing — build verification only in CI
- GUI or configuration tool — conf files are sufficient
- DKMS support — Tegra kernel headers not in standard apt repo
- QEMU-based CI builds — too slow; native arm64 runners available

## Context

Shipped v1.0 with 324 LOC across 11 files (Makefile, shell scripts, Dockerfile, YAML).
Tech stack: dpkg/debhelper, POSIX sh, Docker, GitHub Actions.
Package name: igh-seeedstudio_1.6.0_arm64.deb
All 21 v1 requirements validated via static analysis; live hardware testing pending first CI run.

## Constraints

- **Platform**: NVIDIA Jetson aarch64 with Tegra L4T kernel — kernel headers must match
- **Driver**: Must use r8169 EtherCAT native driver (not generic)
- **NIC**: Hardcoded to enP8p1s0 interface
- **Source**: Official IgH EtherCAT repo, stable-1.6 branch/tag
- **CI**: GitHub Actions, release on v* tag push

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Blacklist both r8168 + r8169 via install /bin/true | Stronger than blacklist keyword; prevents udev bypass | ✓ Good |
| Hardcode enP8p1s0 | Consistent NIC naming on Jetson + SeeedStudio carrier | ✓ Good |
| Docker for build verification only | Can't load kernel modules in container, but verifies build/install | ✓ Good |
| Tag-triggered releases | Clean versioning, only release intentional builds | ✓ Good |
| Package name: igh-seeedstudio | Identifies both the EtherCAT stack and target hardware | ✓ Good |
| --prefix=/usr | ethercatctl reads /etc/ethercat.conf, not /usr/local/etc/ | ✓ Good |
| apt-get download + dpkg -x for L4T headers | Bypasses nvidia-l4t-core preinst /proc/device-tree check in Docker | ✓ Good |
| Reuse Dockerfile in CI | Single source of truth for build pipeline; no duplicated logic in YAML | ✓ Good |
| Native arm64 runner (ubuntu-22.04-arm) | No QEMU overhead; correct architecture for kernel module compilation | ✓ Good |
| Service start after #DEBHELPER# token | Ensures depmod runs before systemctl restart (debhelper ordering fix) | ✓ Good |

---
*Last updated: 2026-03-17 after v1.0 milestone*
