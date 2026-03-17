# IgH EtherCAT for SeeedStudio Jetson

## What This Is

A Debian package (`igh-seeedstudio`) that builds and installs the IgH EtherCAT Master 1.6 with the r8169 native driver on NVIDIA Jetson platforms running Tegra L4T kernel 5.15.148. Includes a Dockerfile for build verification, GitHub Actions CI that builds the .deb and publishes it as a GitHub Release artifact on tag push.

## Core Value

A single `dpkg -i` installs a working EtherCAT master on a Jetson with the Realtek r8169 NIC — no manual compilation or configuration steps.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] .deb package builds IgH EtherCAT 1.6 from official source (https://gitlab.com/etherlab.org/ethercat.git, stable-1.6)
- [ ] Package configures with `--enable-r8169` against Tegra kernel headers (5.15.148-tegra)
- [ ] Package installs blacklist-eth.conf to /etc/modprobe.d/ (blacklists stock r8168 + r8169)
- [ ] Package installs ethercat.conf to /etc/ethercat.conf with MASTER0_DEVICE=<MAC> and DEVICE_MODULES="r8169"
- [ ] Post-install script runs depmod -a and restarts ethercat service
- [ ] Post-install auto-detects MAC address from enP8p1s0
- [ ] Dockerfile verifies the .deb builds cleanly and installs without errors
- [ ] GitHub Actions CI builds .deb on push, creates GitHub Release with .deb artifact on v* tag push
- [ ] CI monitors build status (watchable via `gh run watch`)

### Out of Scope

- Multi-NIC support — hardcoded to enP8p1s0
- Non-Tegra platforms — Jetson-only for now
- Runtime EtherCAT slave testing — build verification only in CI
- GUI or configuration tool — conf files are sufficient

## Context

- Target: NVIDIA Jetson (aarch64) with SeeedStudio carrier board
- Kernel: 5.15.148-tegra-ubuntu22.04_aarch64
- NIC: Realtek r8169 on enP8p1s0
- The stock r8168/r8169 drivers must be blacklisted so EtherCAT's native r8169 driver takes over
- IgH EtherCAT Master 1.6 is the stable industrial EtherCAT implementation
- Build deps: build-essential, automake, linux-headers for Tegra kernel
- ethercat.conf needs only MASTER0_DEVICE (MAC) and DEVICE_MODULES="r8169"

## Constraints

- **Platform**: NVIDIA Jetson aarch64 with Tegra L4T kernel — kernel headers must match
- **Driver**: Must use r8169 EtherCAT native driver (not generic)
- **NIC**: Hardcoded to enP8p1s0 interface
- **Source**: Official IgH EtherCAT repo, stable-1.6 branch/tag
- **CI**: GitHub Actions, release on v* tag push

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Blacklist both r8168 + r8169 | Ensure no stock Realtek driver conflicts with EtherCAT native driver | — Pending |
| Hardcode enP8p1s0 | Consistent NIC naming on Jetson + SeeedStudio carrier | — Pending |
| Docker for build verification only | Can't test kernel modules in container, but can verify build/install | — Pending |
| Tag-triggered releases | Clean versioning, only release intentional builds | — Pending |
| Package name: igh-seeedstudio | Identifies both the EtherCAT stack and target hardware | — Pending |

---
*Last updated: 2026-03-17 after initialization*
