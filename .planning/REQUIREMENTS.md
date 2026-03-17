# Requirements: igh-seeedstudio

**Defined:** 2026-03-17
**Core Value:** A single `dpkg -i` installs a working EtherCAT master on a Jetson with the Realtek r8169 NIC

## v1 Requirements

### Source & Build

- [x] **SRC-01**: Package fetches IgH EtherCAT 1.6 source from official GitLab repo (https://gitlab.com/etherlab.org/ethercat.git, stable-1.6)
- [x] **SRC-02**: Package installs build-essential and automake as build dependencies
- [x] **SRC-03**: Configure runs with `--enable-r8169 --with-linux-dir` pointing to Tegra 5.15.148 kernel headers
- [x] **SRC-04**: `make` and `make modules` produce ec_master and ec_r8169 kernel modules

### Debian Packaging

- [x] **DEB-01**: debian/ directory with control, rules, changelog, copyright, and maintainer scripts
- [x] **DEB-02**: Package builds as `igh-seeedstudio_1.6.0_arm64.deb`
- [x] **DEB-03**: Package declares Architecture: arm64

### Install (postinst)

- [ ] **INST-01**: postinst copies blacklist-eth.conf to /etc/modprobe.d/ (blacklists r8168 + r8169 stock drivers)
- [ ] **INST-02**: postinst runs `depmod -a` after module files are installed
- [ ] **INST-03**: postinst auto-detects MAC address from /sys/class/net/enP8p1s0/address
- [ ] **INST-04**: postinst generates /etc/ethercat.conf with MASTER0_DEVICE=<detected MAC> and DEVICE_MODULES="r8169"
- [ ] **INST-05**: postinst restarts ethercat systemd service

### Removal (prerm/postrm)

- [ ] **REM-01**: prerm stops ethercat service before package removal
- [ ] **REM-02**: prerm unloads EtherCAT kernel modules

### Docker Verification

- [ ] **DOC-01**: Dockerfile builds the .deb from scratch in an aarch64 ubuntu:22.04 environment
- [ ] **DOC-02**: Dockerfile verifies the .deb installs without errors (dpkg -i succeeds)
- [ ] **DOC-03**: Docker build runs before r8168 driver is unloaded (tests build in safe environment)

### CI/CD

- [ ] **CI-01**: GitHub Actions workflow builds .deb on every push to main
- [ ] **CI-02**: GitHub Actions creates GitHub Release with .deb artifact on v* tag push
- [ ] **CI-03**: CI uses native arm64 runner (ubuntu-22.04-arm or equivalent)
- [ ] **CI-04**: CI status is watchable via `gh run watch`

## v2 Requirements

### Install Hardening

- **INST-06**: postinst uses `install r8169 /bin/true` pattern instead of just `blacklist` keyword
- **INST-07**: postinst runs `update-initramfs -u` after blacklist install
- **REM-03**: postrm purge removes blacklist and conf files

### Packaging Polish

- **DEB-04**: Kernel version in `Provides:` virtual package for conflict detection
- **DEB-05**: Split igh-seeedstudio-dev package with EtherCAT headers

## Out of Scope

| Feature | Reason |
|---------|--------|
| DKMS support | Tegra kernel headers not in standard apt repo; DKMS rebuild would silently fail |
| Multi-NIC auto-discovery | Always enP8p1s0 on SeeedStudio Jetson carrier |
| GUI/TUI configurator | Conf files are industry standard; GUI adds deps |
| Interactive debconf prompts | Breaks unattended/automated install |
| Runtime EtherCAT slave testing in CI | Requires physical hardware |
| Non-Tegra platform support | Jetson-only for now |
| QEMU-based CI builds | Too slow (45-90 min); native arm64 runners available |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SRC-01 | Phase 2 | Complete |
| SRC-02 | Phase 2 | Complete |
| SRC-03 | Phase 2 | Complete |
| SRC-04 | Phase 2 | Complete |
| DEB-01 | Phase 1 | Complete |
| DEB-02 | Phase 1 | Complete |
| DEB-03 | Phase 1 | Complete |
| INST-01 | Phase 3 | Pending |
| INST-02 | Phase 3 | Pending |
| INST-03 | Phase 3 | Pending |
| INST-04 | Phase 3 | Pending |
| INST-05 | Phase 3 | Pending |
| REM-01 | Phase 4 | Pending |
| REM-02 | Phase 4 | Pending |
| DOC-01 | Phase 5 | Pending |
| DOC-02 | Phase 5 | Pending |
| DOC-03 | Phase 5 | Pending |
| CI-01 | Phase 6 | Pending |
| CI-02 | Phase 6 | Pending |
| CI-03 | Phase 6 | Pending |
| CI-04 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 21 total
- Mapped to phases: 21
- Unmapped: 0

---
*Requirements defined: 2026-03-17*
*Last updated: 2026-03-17 after roadmap creation*
