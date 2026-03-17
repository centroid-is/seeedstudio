---
phase: 02-source-and-build
plan: 01
subsystem: infra
tags: [debian, dpkg, makefile, igh-ethercat, r8169, kernel-module, autotools]

# Dependency graph
requires:
  - phase: 01-debian-scaffold
    provides: "debian/control Build-Depends and minimal debian/rules with dh $@"
provides:
  - "Complete debian/rules with 7 override targets for IgH EtherCAT source fetch, configure, build, install, clean"
  - "debian/control with git and pkg-config in Build-Depends"
  - "ec_r8169.ko build assertion that fails loudly if driver silently dropped"
affects: [03-install-scripts, 05-docker-build, 06-ci-publish]

# Tech tracking
tech-stack:
  added: [igh-ethercat-stable-1.6, git-clone-depth-1]
  patterns: [dh-override-targets, source-fetch-via-dh_update_autotools_config, build-assertion-pattern, DESTDIR-vs-INSTALL_MOD_PATH]

key-files:
  modified:
    - debian/rules
    - debian/control

key-decisions:
  - "Used override_dh_update_autotools_config for source fetch (runs before autoreconf/configure in dh sequence)"
  - "Used --prefix=/usr (locked decision from STATE.md; ethercatctl reads /etc/ethercat.conf)"
  - "Used --with-module-dir=extra (modules install to /lib/modules/ver/extra/ per roadmap criterion)"
  - "Added override_dh_autoreconf with @true to prevent dh_autoreconf running in wrong directory"
  - "Added override_dh_shlibdeps -X.ko as safety measure against dpkg-shlibdeps errors on kernel modules"

patterns-established:
  - "Build assertion: test -f for critical .ko files after make (prevents silent driver omission)"
  - "Dual install targets: DESTDIR for make install (userspace), INSTALL_MOD_PATH for make modules_install (kernel)"
  - "Makefile line continuation with backslash for long commands (git clone, configure flags)"

requirements-completed: [SRC-01, SRC-02, SRC-03, SRC-04]

# Metrics
duration: 2min
completed: 2026-03-17
---

# Phase 2 Plan 1: Source and Build Summary

**IgH EtherCAT 1.6 build pipeline in debian/rules: git clone from GitLab stable-1.6, autotools bootstrap, configure with r8169/Tegra flags, build with ec_r8169.ko assertion, dual DESTDIR/INSTALL_MOD_PATH install**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-17T16:45:24Z
- **Completed:** 2026-03-17T16:47:39Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added git and pkg-config to debian/control Build-Depends (8 total entries, properly aligned)
- Implemented 7 override_dh_* targets in debian/rules covering the complete IgH EtherCAT build lifecycle
- ec_r8169.ko build assertion checks devices/r8169/ subdirectory path (kernel 5.15 layout)
- All configure flags match research recommendations including locked --prefix=/usr decision

## Task Commits

Each task was committed atomically:

1. **Task 1: Add git and pkg-config to debian/control Build-Depends** - `7981141` (feat)
2. **Task 2: Implement complete debian/rules build pipeline** - `aa0730a` (feat)

## Files Created/Modified
- `debian/control` - Added pkg-config and git to Build-Depends (8 entries total)
- `debian/rules` - Complete build pipeline with 7 override targets: source fetch, configure, build, install, clean, autoreconf skip, shlibdeps exclusion

## Decisions Made
- Used `override_dh_update_autotools_config` hook for git clone (runs early in dh sequence, before autoreconf and configure)
- Split git clone across two lines with backslash continuation for readability (standard Makefile pattern)
- Included `--enable-generic` alongside `--enable-r8169` for fallback ec_generic.ko driver
- Disabled unneeded drivers explicitly (--disable-8139too, --disable-e1000, --disable-e1000e)
- Used `@true` in override_dh_autoreconf to safely skip autoreconf without error

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- debian/rules and debian/control are complete for Phase 2 scope
- Full dpkg-buildpackage validation requires arm64 environment with Tegra kernel headers (deferred to Phase 5 Docker build)
- Phase 3 (install scripts) can proceed: postinst will need depmod + systemctl, prerm will need module unload
- The ec_r8169.ko assertion will surface any kernel header compatibility issues during first real build

## Self-Check: PASSED

All 2 modified files exist. SUMMARY.md created. Commits 7981141 and aa0730a verified in git log.

---
*Phase: 02-source-and-build*
*Completed: 2026-03-17*
