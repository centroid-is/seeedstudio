# Project Research Summary

**Project:** igh-seeedstudio — IgH EtherCAT .deb Package for Jetson aarch64
**Domain:** Kernel module Debian packaging for industrial automation (embedded/fixed-target)
**Researched:** 2026-03-17
**Confidence:** MEDIUM-HIGH (core Debian toolchain HIGH; Jetson-specific kernel header paths MEDIUM; r8169 on kernel 5.15 LOW pending build validation)

## Executive Summary

This project is a Debian binary package (.deb) that delivers pre-compiled IgH EtherCAT Master kernel modules (`ec_master.ko`, `ec_r8169.ko`) and supporting userspace tools for a specific, vendor-locked target: NVIDIA Jetson running L4T kernel `5.15.148-tegra` on a SeeedStudio carrier board. Because the Tegra kernel is managed by NVIDIA and does not update through standard Ubuntu channels, the correct approach is a static pre-compiled package — not DKMS. The entire build environment must be containerized (Docker, `ubuntu:22.04`, aarch64) to guarantee the right kernel headers are used, and CI must run on native arm64 (GitHub Actions `ubuntu-22.04-arm` runner, free for public repos since January 2025) rather than QEMU emulation.

The recommended architecture is a minimal, single-package approach: a `debian/` directory containing the build instructions, lifecycle scripts (`postinst`, `prerm`, `postrm`), and a static modprobe.d blacklist file. The `postinst` script performs MAC auto-detection from the known interface `enP8p1s0` and writes `/etc/ethercat.conf` at install time; it must not declare this file as a `debian/conffile` since it is dynamically generated. The GitHub Actions pipeline builds the `.deb` on every push and attaches it as a release asset on `v*` tag pushes.

The highest-risk implementation areas are: (1) the IgH EtherCAT configure prefix — `--prefix=/usr` is mandatory so that `ethercatctl` finds `ethercat.conf` at `/etc/ethercat.conf` rather than `/usr/local/etc/`; (2) the modprobe.d blacklist must use `install r8169 /bin/true` rather than the weaker `blacklist r8169` keyword, and the postinst must call `update-initramfs -u` for the blacklist to survive reboot; and (3) the `depmod -a` call in postinst must precede any `modprobe` or `systemctl restart ethercat` invocation. All three pitfalls cause silent install success followed by runtime EtherCAT failure, which makes them especially dangerous.

## Key Findings

### Recommended Stack

The build toolchain is `dpkg-buildpackage` with `debhelper-compat = 13` inside an `ubuntu:22.04` Docker container. The IgH EtherCAT source is from the `stable-1.6` branch on GitLab (the only actively-maintained upstream). Build dependencies are `build-essential`, `autoconf`, `automake`, `libtool`, and `nvidia-l4t-kernel-headers` pinned to match `5.15.148-tegra` exactly. The resulting package is a binary-only arm64 `.deb` containing pre-compiled `.ko` files — DKMS is explicitly rejected because Tegra kernel headers are not available on target devices and the kernel is vendor-locked.

CI runs on GitHub Actions using `ubuntu-22.04-arm` (native arm64, free for public repos), eliminating QEMU overhead. QEMU is documented as unsuitable: 5-10x slower, with known build failure bugs on kernel 6.8+ hosts.

**Core technologies:**
- `debhelper-compat (= 13)`: Debian packaging framework — current standard for Ubuntu 22.04; avoids legacy `debian/compat` file
- `dpkg-buildpackage -us -uc -b`: Binary .deb production — the only correct tool for this layer
- Pre-built `.ko` (non-DKMS): Kernel modules compiled once against pinned headers — DKMS value proposition doesn't apply to a vendor-locked kernel
- IgH EtherCAT `stable-1.6`: The production branch of the only open-source Linux EtherCAT master
- `ubuntu-22.04-arm` GHA runner: Native aarch64 CI — free for public repos since Jan 2025; eliminates QEMU
- Docker `ubuntu:22.04`: Reproducible build environment — the build environment IS the package guarantee

### Expected Features

The MVP goal is: `dpkg -i` on a Jetson results in a working EtherCAT master with zero manual steps.

**Must have (table stakes):**
- `postinst` runs `depmod -a` before any module load — without this, modprobe cannot find the module even though it is on disk
- `postinst` installs modprobe.d blacklist (`install r8169 /bin/true`, `install r8168 /bin/true`) and runs `update-initramfs -u` — stock driver must be fully blocked including from initramfs
- `postinst` writes `/etc/ethercat.conf` with MAC auto-detected from `enP8p1s0` (fallback to `ff:ff:ff:ff:ff:ff`) — not declared as a `debian/conffile` since it is generated
- `postinst` enables and starts `ethercat.service` after depmod
- `prerm` stops service and unloads modules before `.ko` files are removed
- `postrm purge` removes blacklist and conf files; calls `update-initramfs -u`
- `debian/control` declares `Architecture: arm64`; `Build-Depends` pins `nvidia-l4t-kernel-headers` to exact Tegra version
- Kernel module `.ko` files installed to `/lib/modules/5.15.148-tegra/extra/`

**Should have (differentiators vs. "build it yourself"):**
- MAC auto-detection from `enP8p1s0` via sysfs — eliminates the most common manual step at each new Jetson setup
- `Dockerfile` for build + `dpkg -i` install verification — proves package builds from a clean environment
- GitHub Actions CI on push + GitHub Release artifact on `v*` tag — reproducible, trusted artifact delivery
- `postrm purge` removes modprobe.d blacklist and conf (clean uninstall)
- Build assertion in CI: `test -f devices/ec_r8169.ko` — fails loudly if r8169 driver was silently dropped by configure

**Defer (v2+):**
- Split `igh-seeedstudio-dev` package with headers — only if applications are built on-device
- DKMS variant — only if Tegra kernel becomes a standard apt-managed kernel
- Multi-NIC support beyond `enP8p1s0` — only if deployed on other carrier boards

### Architecture Approach

The project is a single-package repository: a `debian/` directory alongside the IgH EtherCAT upstream source (vendored as a tarball or via `get-orig-source`). The `debian/rules` file calls `./bootstrap`, then `./configure --prefix=/usr --sysconfdir=/etc --with-linux-dir=/usr/src/linux-headers-5.15.148-tegra --enable-r8169 --disable-8139too --enable-generic`, then `make` and `make modules_install`. The source format is `3.0 (native)` — simplest for a single-repo approach. A companion `Dockerfile` and `.github/workflows/ci.yml` complete the project structure.

**Major components:**
1. `debian/control` — Package metadata, architecture declaration (`arm64`), pinned `Build-Depends` on Tegra headers
2. `debian/rules` — Orchestrates configure/make/modules_install via debhelper overrides; critical: `--prefix=/usr` and `--with-linux-dir` flags
3. `debian/postinst` — depmod, blacklist install, update-initramfs, MAC detection, ethercat.conf write, service enable/start; strict ordering required
4. `debian/prerm` + `debian/postrm` — Service stop, module unload, and purge-time cleanup of blacklist/conf
5. `etc/modprobe.d/blacklist-eth.conf` — Static file installed by dpkg; content: `install r8169 /bin/true` and `install r8168 /bin/true`
6. `Dockerfile` — Reproducible `ubuntu:22.04` aarch64 build + install verification environment
7. `.github/workflows/ci.yml` — Build on push; GitHub Release with `.deb` artifact on `v*` tag

### Critical Pitfalls

1. **ethercat.conf written to wrong path** — Use `--prefix=/usr` in configure. With the default `/usr/local` prefix, `ethercatctl` reads `/usr/local/etc/ethercat.conf` but postinst writes `/etc/ethercat.conf`; service fails with "MAC address may not be empty" after otherwise-clean install. Verify: `strings $(which ethercatctl) | grep etc`.

2. **`blacklist r8169` does not block udev autoloading** — Use `install r8169 /bin/true` (not just `blacklist r8169`) AND call `update-initramfs -u` in postinst. A plain blacklist blocks on-demand `modprobe` but not hotplug/udev loading or modules embedded in initramfs.

3. **depmod must precede modprobe/service restart in postinst** — Postinst ordering: (1) dpkg unpacks `.ko` files, (2) `depmod -a`, (3) `systemctl restart ethercat`. Reversing 2 and 3 causes `Module ec_master not found` on first install even though the file exists on disk.

4. **ec_r8169.ko silently not built if configure feature detection fails** — `--enable-r8169` does not guarantee `ec_r8169.ko` is produced if kernel headers lack expected r8169 symbols. Add explicit assertion: `test -f devices/ec_r8169.ko || exit 1` in the Dockerfile/CI build step.

5. **Kernel update via `apt upgrade` silently breaks modules** — Pin `nvidia-l4t-kernel` and `nvidia-l4t-kernel-headers` with `apt-mark hold`. Add a `Depends:` on the exact kernel version so dpkg warns on mismatch. Document clearly in README.

## Implications for Roadmap

Based on research, 3 phases cover the full project scope:

### Phase 1: Build Foundation
**Rationale:** Everything else depends on a working build. The Dockerfile and debian/rules must be correct before any lifecycle scripts are testable. The kernel header path and `--prefix` flag are the two highest-risk items — they must be validated first.
**Delivers:** A `.deb` that can be produced from a clean environment and installs without errors (even if service doesn't start yet).
**Addresses:** Core packaging structure (`debian/control`, `rules`, `changelog`, `compat`, `copyright`); IgH configure flags (`--prefix=/usr`, `--enable-r8169`, `--with-linux-dir`); `Dockerfile` build verification; ec_r8169.ko build assertion.
**Avoids:** Wrong prefix path (Pitfall 1); ec_r8169.ko silently not built (Pitfall 6); module built against wrong kernel version (Pitfall 2).

### Phase 2: Install Lifecycle and Device Configuration
**Rationale:** Once the build is solid, the install lifecycle scripts are authored. These have strict ordering requirements and multiple runtime failure modes — they are best developed and tested as a unit after the package builds correctly.
**Delivers:** `dpkg -i` on a Jetson results in a working, running EtherCAT master with no manual steps.
**Addresses:** `postinst` (depmod ordering, blacklist, update-initramfs, MAC auto-detection, ethercat.conf write, service enable/start); `prerm` (service stop, module unload); `postrm` (purge cleanup, update-initramfs); modprobe.d blacklist with `install /bin/true` semantics.
**Avoids:** depmod ordering failure (Pitfall 4); blacklist not blocking udev (Pitfall 3); blacklist not in initramfs (Pitfall 9); MAC detection failure (Pitfall 5); kernel update breaking modules (Pitfall 8).

### Phase 3: CI/CD Pipeline
**Rationale:** The CI workflow builds on a working package. Once local build and install are validated, the GitHub Actions pipeline and release workflow are straightforward to implement using well-documented actions.
**Delivers:** GitHub Actions workflow that builds `.deb` on every push and publishes a GitHub Release artifact on `v*` tag; native arm64 runner configured.
**Addresses:** `ubuntu-22.04-arm` runner configuration; `dpkg-buildpackage -us -uc -b` in CI; `softprops/action-gh-release` for release artifact; NVIDIA L4T apt repo setup in CI for kernel headers.
**Avoids:** QEMU build slowness/failures (Pitfall 7); incorrect kernel headers in CI (Pitfall 2).

### Phase Ordering Rationale

- Phase 1 must come first: the `debian/rules` configure flags (especially `--prefix=/usr` and `--with-linux-dir`) are foundational. Every downstream script and test depends on the package building correctly with the right flags.
- Phase 2 depends on Phase 1: lifecycle scripts can only be tested against a working .deb; the postinst ordering constraint (depmod before service start) makes this a unit of work that must be developed together.
- Phase 3 depends on Phase 2: CI should validate a complete, installable package. Building CI before the lifecycle scripts are correct produces a pipeline that passes on `.deb` creation but would fail at runtime — a false confidence trap.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1 (Build Foundation):** The exact NVIDIA L4T apt repository URL and package name for `linux-headers-5.15.148-tegra` needs validation. Multiple forum sources confirm the package name but the exact apt repo endpoint for Jetson Orin / JetPack 6.x differs from older Nano references. Recommend validating on actual Jetson hardware or NVIDIA developer portal before writing the Dockerfile.
- **Phase 2 (Lifecycle Scripts):** The `update-initramfs` behavior on Tegra-based Jetson (L4T) may differ from standard Ubuntu — Jetson uses a custom boot flow and the initrd may not be updated the same way. Needs empirical validation on hardware.

Phases with standard patterns (skip research-phase):
- **Phase 3 (CI/CD):** GitHub Actions `ubuntu-22.04-arm` runner usage, `jtdor/build-deb-action`, and `softprops/action-gh-release` are all well-documented with official examples. No deeper research needed.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | debhelper 13 + dpkg-buildpackage toolchain is stable, well-documented. Pre-built vs DKMS decision is clear. Native arm64 GHA runner confirmed via official GitHub announcement Jan 2025. |
| Features | HIGH | Feature set is well-understood from prior art (ec-debianize, ethercat_igh_dkms) and IgH upstream documentation. Conffile vs. generated-config distinction is documented in Debian policy. |
| Architecture | HIGH | Debian packaging structure (debian/ directory, build/install flow, CI/CD) is a mature, well-documented domain. Jetson-specific header paths are MEDIUM — need build validation. |
| Pitfalls | HIGH | Most pitfalls are verified by multiple community reports and official documentation (depmod ordering, blacklist semantics, prefix path). r8169 on kernel 5.15 compatibility is LOW — needs empirical build test. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **NVIDIA L4T apt repo URL for kernel headers in CI:** The exact `apt-get install nvidia-l4t-kernel-headers=<version>` command and apt source configuration for JetPack 6.x / kernel 5.15.148-tegra needs validation. Multiple sources reference the package but none provide a tested Dockerfile snippet. Address in Phase 1 by testing the Dockerfile against the actual NVIDIA apt repository.

- **r8169 compatibility with kernel 5.15:** IgH EtherCAT's r8169 native driver patches were originally written for 3.x/4.x kernel APIs. Community reports suggest they apply to 5.15 but this is unverified for the Tegra-specific kernel. The build assertion (`test -f devices/ec_r8169.ko`) in Phase 1 will immediately surface any incompatibility.

- **update-initramfs behavior on Jetson:** Standard Ubuntu `update-initramfs -u` behavior is well-documented, but Jetson L4T uses a modified boot configuration. Validate in Phase 2 that running `update-initramfs -u` in postinst actually updates the initrd used at boot on the target hardware.

- **Exact ethercat.conf path with `--prefix=/usr`:** Using `--prefix=/usr` should resolve the conf path to `/etc/ethercat.conf` (since `--sysconfdir=/etc`), but this should be verified by inspecting the installed `ethercatctl` script (`strings $(which ethercatctl) | grep etc`) on first build.

## Sources

### Primary (HIGH confidence)
- GitHub Blog: Linux arm64 hosted runners — confirmed `ubuntu-22.04-arm` label, free for public repos, Jan 2025 launch
- GitHub Actions Hosted Runners Reference — specs for arm64 public repo runners
- Debian Wiki: DkmsPackaging — confirmed why DKMS is the wrong choice here
- Debian Maintainers' Guide Chapter 5 — debian/ directory structure and debhelper patterns
- Debian Policy: Conffiles handling — `debian/conffiles` semantics, generated vs. shipped configs
- Debian Wiki: KernelModuleBlacklisting — `blacklist` vs. `install /bin/true` distinction

### Secondary (MEDIUM confidence)
- NVIDIA Developer Forums: EtherCAT on Jetson Nano — confirmed configure flags and kernel header path format
- NVIDIA Developer Forums: linux-headers missing on Jetson Orin Nano — confirms `nvidia-l4t-kernel-headers` package name
- Vincent Bernat: Packaging a driver for Debian with DKMS (2018) — patterns still valid
- GitLab Forum: EtherCAT empty MAC error — confirms Pitfall 1 (wrong prefix path)
- LinuxCNC Forum: EtherCAT build from source — confirms depmod ordering and udev rules
- IgH EtherCAT GitLab Issue #21 — systemd integration and ethercat.conf path confusion

### Tertiary (LOW confidence)
- sittner/ec-debianize — Reference debian/ structure (targets older Debian/Stretch, DKMS-based; patterns useful but not directly applicable)
- QEMU aarch64 performance issues — Known QEMU build problem (open issue, not officially closed)
- r8169 on kernel 5.15 compatibility — Community reports only; needs empirical validation

---
*Research completed: 2026-03-17*
*Ready for roadmap: yes*
