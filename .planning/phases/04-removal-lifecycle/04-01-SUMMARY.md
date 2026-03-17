---
phase: 04-removal-lifecycle
plan: 01
subsystem: infra
tags: [debian, prerm, systemd, rmmod, kernel-modules, ethercat, dpkg]

# Dependency graph
requires:
  - phase: 03-install-lifecycle
    provides: "debian/postinst with POSIX sh pattern, systemd guard, and #DEBHELPER# token placement"
provides:
  - "debian/prerm maintainer script that stops ethercat.service and unloads ec_r8169/ec_master before dpkg removes files"
affects: [05-verification, 06-ci-publishing]

# Tech tracking
tech-stack:
  added: []
  patterns: [prerm-service-stop, rmmod-dependency-order, prerm-debhelper-placement]

key-files:
  created: [debian/prerm]
  modified: []

key-decisions:
  - "Module unload order: ec_r8169 before ec_master (ec_r8169 depends on ec_master)"
  - "systemctl stop guarded by /run/systemd/system check (same Docker/chroot safety pattern as postinst)"
  - "All operations use || true / 2>/dev/null || true to prevent dpkg removal failure on edge cases"
  - "postrm purge explicitly deferred to v2 (REM-03 out of scope)"

patterns-established:
  - "prerm mirrors postinst POSIX sh structure: shebang, set -e, case dispatch, #DEBHELPER#, exit 0"
  - "Kernel module unload in reverse dependency order with 2>/dev/null || true"

requirements-completed: [REM-01, REM-02]

# Metrics
duration: 1min
completed: 2026-03-17
---

# Phase 4 Plan 1: Removal Lifecycle Summary

**debian/prerm with systemd-guarded service stop and dependency-ordered kernel module unload (ec_r8169 before ec_master) for clean dpkg -r**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-17T17:28:18Z
- **Completed:** 2026-03-17T17:29:15Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Created debian/prerm maintainer script following the exact POSIX sh pattern from debian/postinst
- Service stop guarded by /run/systemd/system check for Docker/chroot safety
- Kernel modules unloaded in correct dependency order (ec_r8169 before ec_master) with robust error handling

## Task Commits

Each task was committed atomically:

1. **Task 1: Create debian/prerm maintainer script** - `1b8b57b` (feat)

## Files Created/Modified
- `debian/prerm` - Pre-removal maintainer script: stops ethercat.service, unloads ec_r8169 and ec_master kernel modules before dpkg removes package files

## Decisions Made
- Module unload order: ec_r8169 before ec_master (ec_r8169 depends on ec_master, must be unloaded first)
- systemctl stop guarded by /run/systemd/system check (identical pattern to postinst for Docker/chroot safety)
- All operations use || true / 2>/dev/null || true to ensure dpkg removal succeeds even when service is not running or modules are not loaded
- postrm purge logic explicitly deferred to v2 (requirement REM-03 is out of scope for this plan)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- debian/prerm completes the removal lifecycle (Phase 4)
- Package now supports clean install (postinst), removal (prerm), and reinstall cycles
- Ready for Phase 5 (Docker verification) to validate full dpkg -i / dpkg -r lifecycle
- postrm purge (REM-03) deferred to v2 -- only affects config file cleanup on `dpkg --purge`

## Self-Check: PASSED

- debian/prerm: FOUND
- 04-01-SUMMARY.md: FOUND
- Commit 1b8b57b (Task 1): FOUND

---
*Phase: 04-removal-lifecycle*
*Completed: 2026-03-17*
