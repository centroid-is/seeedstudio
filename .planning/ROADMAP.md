# Roadmap: igh-seeedstudio

## Overview

Build a Debian package that delivers IgH EtherCAT Master 1.6 with the r8169 native driver on NVIDIA Jetson aarch64. The project proceeds in six phases: scaffold the Debian packaging structure, wire up the IgH source fetch and compile pipeline, author the install lifecycle scripts (the highest-risk work), add clean removal, verify everything with Docker, then automate build and release with GitHub Actions CI. Every phase delivers something independently verifiable before the next begins.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Debian Scaffold** - debian/ directory with control, rules, changelog, copyright, and compat declared (completed 2026-03-17)
- [ ] **Phase 2: Source and Build** - IgH EtherCAT 1.6 fetched, configured with --enable-r8169 and --prefix=/usr, compiled to produce ec_master.ko and ec_r8169.ko
- [ ] **Phase 3: Install Lifecycle** - postinst installs blacklist, runs depmod, auto-detects MAC, writes ethercat.conf, starts service in correct order
- [ ] **Phase 4: Removal Lifecycle** - prerm stops service and unloads modules cleanly before file removal
- [ ] **Phase 5: Docker Verification** - Dockerfile builds .deb from scratch and verifies dpkg -i succeeds
- [ ] **Phase 6: CI/CD Pipeline** - GitHub Actions builds .deb on push, publishes GitHub Release artifact on v* tag

## Phase Details

### Phase 1: Debian Scaffold
**Goal**: The debian/ directory exists with all required metadata files, the package declares arm64 architecture and correct build dependencies, and dpkg-buildpackage can parse the control file without errors
**Depends on**: Nothing (first phase)
**Requirements**: DEB-01, DEB-02, DEB-03
**Success Criteria** (what must be TRUE):
  1. debian/control, rules, changelog, copyright, and compat files all exist and are syntactically valid
  2. Package declares Architecture: arm64 in debian/control
  3. Build-Depends in debian/control includes build-essential, autoconf, automake, and the pinned nvidia-l4t-kernel-headers package
  4. dpkg-buildpackage --no-check-builddeps parses without errors
**Plans:** 1/1 plans complete

Plans:
- [x] 01-01-PLAN.md — Create and validate all debian/ packaging metadata files

### Phase 2: Source and Build
**Goal**: Running dpkg-buildpackage inside the build environment produces igh-seeedstudio_1.6.0_arm64.deb containing both ec_master.ko and ec_r8169.ko compiled against the Tegra 5.15.148 kernel headers
**Depends on**: Phase 1
**Requirements**: SRC-01, SRC-02, SRC-03, SRC-04
**Success Criteria** (what must be TRUE):
  1. IgH EtherCAT source is fetched from https://gitlab.com/etherlab.org/ethercat.git stable-1.6 branch during build
  2. configure runs with --enable-r8169, --prefix=/usr, --sysconfdir=/etc, and --with-linux-dir pointing to Tegra headers
  3. Both ec_master.ko and ec_r8169.ko are present in the built .deb package under /lib/modules/5.15.148-tegra/extra/
  4. The output file is named igh-seeedstudio_1.6.0_arm64.deb
**Plans:** 1 plan

Plans:
- [ ] 02-01-PLAN.md — Wire up debian/rules build pipeline and update debian/control Build-Depends

### Phase 3: Install Lifecycle
**Goal**: Running dpkg -i on a Jetson results in a running EtherCAT master with no manual steps — blacklist in place, conf written with correct MAC, depmod run, service started
**Depends on**: Phase 2
**Requirements**: INST-01, INST-02, INST-03, INST-04, INST-05
**Success Criteria** (what must be TRUE):
  1. /etc/modprobe.d/blacklist-eth.conf exists after install and contains "install r8169 /bin/true" and "install r8168 /bin/true"
  2. depmod -a runs in postinst before any systemctl invocation
  3. /etc/ethercat.conf is written with MASTER0_DEVICE set to the MAC address read from /sys/class/net/enP8p1s0/address
  4. /etc/ethercat.conf contains DEVICE_MODULES="r8169"
  5. ethercat.service is enabled and started (or restarted) as the final postinst step
**Plans**: TBD

### Phase 4: Removal Lifecycle
**Goal**: dpkg -r or dpkg -P removes the package cleanly — service stopped, modules unloaded, no leftover state that prevents reinstall
**Depends on**: Phase 3
**Requirements**: REM-01, REM-02
**Success Criteria** (what must be TRUE):
  1. prerm stops ethercat.service before any .ko files are removed
  2. prerm unloads ec_master and ec_r8169 kernel modules before removal completes
  3. Reinstalling the package after removal does not produce module-in-use or service-already-running errors
**Plans**: TBD

### Phase 5: Docker Verification
**Goal**: docker build succeeds end-to-end — IgH source fetched, .deb built, dpkg -i succeeds — with no errors and with ec_r8169.ko confirmed present
**Depends on**: Phase 4
**Requirements**: DOC-01, DOC-02, DOC-03
**Success Criteria** (what must be TRUE):
  1. docker build completes without errors on aarch64 using ubuntu:22.04 base
  2. dpkg -i inside the container exits 0 with no error or warning output
  3. The Dockerfile asserts that devices/ec_r8169.ko exists after make (build fails loudly if r8169 module was not produced)
**Plans**: TBD

### Phase 6: CI/CD Pipeline
**Goal**: Every push to main triggers a .deb build on a native arm64 runner, and every v* tag push creates a GitHub Release with the .deb as a downloadable artifact
**Depends on**: Phase 5
**Requirements**: CI-01, CI-02, CI-03, CI-04
**Success Criteria** (what must be TRUE):
  1. Pushing to main triggers a GitHub Actions workflow that builds the .deb on ubuntu-22.04-arm (native arm64, not QEMU)
  2. Pushing a v* tag creates a GitHub Release with the .deb file attached as a release asset
  3. gh run watch shows build progress in real time for any triggered run
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Debian Scaffold | 1/1 | Complete    | 2026-03-17 |
| 2. Source and Build | 0/1 | Not started | - |
| 3. Install Lifecycle | 0/TBD | Not started | - |
| 4. Removal Lifecycle | 0/TBD | Not started | - |
| 5. Docker Verification | 0/TBD | Not started | - |
| 6. CI/CD Pipeline | 0/TBD | Not started | - |
