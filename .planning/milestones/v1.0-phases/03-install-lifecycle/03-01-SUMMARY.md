---
phase: 03-install-lifecycle
plan: 01
subsystem: infra
tags: [debian, postinst, modprobe, blacklist, ethercat, systemd, depmod, debhelper]

# Dependency graph
requires:
  - phase: 02-source-and-build
    provides: "debian/rules with override targets for source fetch, configure, build, install"
provides:
  - "debian/postinst maintainer script with full install lifecycle (blacklist, MAC detect, ethercat.conf, depmod, service start)"
  - "override_dh_installsystemd with --no-start in debian/rules"
affects: [04-systemd-integration, 05-verification]

# Tech tracking
tech-stack:
  added: [dh_installsystemd, dh_installmodules]
  patterns: [debhelper-ordering-workaround, install-bin-true-blacklist, DEBHELPER-token-placement]

key-files:
  created: [debian/postinst]
  modified: [debian/rules]

key-decisions:
  - "Service start placed AFTER #DEBHELPER# token to ensure depmod runs first (debhelper ordering conflict resolution)"
  - "Used 'install r8169 /bin/true' blacklist pattern to prevent udev bypass (stronger than 'blacklist' keyword)"
  - "systemctl restart guarded by /run/systemd/system check for Docker/chroot safety"
  - "MAC detection uses graceful fallback (empty string) when interface not present"

patterns-established:
  - "DEBHELPER token placement: custom code before, service start after"
  - "Blacklist via install /bin/true (not blacklist keyword)"
  - "Makefile override with --no-start for debhelper ordering control"

requirements-completed: [INST-01, INST-02, INST-03, INST-04, INST-05]

# Metrics
duration: 2min
completed: 2026-03-17
---

# Phase 3 Plan 1: Install Lifecycle Summary

**Debian postinst with blacklist (install /bin/true), MAC auto-detection, ethercat.conf generation, and depmod-safe service start via --no-start override**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-17T17:14:59Z
- **Completed:** 2026-03-17T17:16:59Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added override_dh_installsystemd with --no-start to debian/rules, resolving the critical debhelper ordering conflict where dh_installsystemd runs before dh_installmodules
- Created debian/postinst with full install lifecycle: stock driver blacklisting, MAC auto-detection from sysfs, ethercat.conf generation, and service start after depmod
- All 5 INST-* requirements addressed in a single POSIX-compliant maintainer script

## Task Commits

Each task was committed atomically:

1. **Task 1: Add override_dh_installsystemd to debian/rules** - `858a7eb` (feat)
2. **Task 2: Create debian/postinst maintainer script** - `d67da46` (feat)

## Files Created/Modified
- `debian/rules` - Added override_dh_installsystemd target with --no-start flag
- `debian/postinst` - Post-install maintainer script handling blacklist, MAC detection, ethercat.conf, depmod (#DEBHELPER#), and service start

## Decisions Made
- Service start placed AFTER #DEBHELPER# token to ensure depmod -a runs first (resolves debhelper ordering conflict where dh_installsystemd generates code before dh_installmodules)
- Used "install r8169 /bin/true" blacklist pattern (stronger than "blacklist r8169" -- prevents udev bypass)
- Also blacklisted r8168 the same way (locked decision from CONTEXT.md)
- systemctl restart uses || true to ensure dpkg -i completes even if service fails to start (e.g., missing hardware, chroot)
- systemctl restart guarded by /run/systemd/system check for Docker/chroot safety
- MAC detection falls back to empty string when enP8p1s0 interface not present (logs warning to stderr)
- ethercat.conf written unconditionally (v1 single-purpose Jetson package; upgrade-awareness deferred to v2)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- debian/postinst and debian/rules are complete for the install lifecycle
- Ready for Phase 4 (systemd integration) or Phase 5 (Docker verification)
- Runtime validation (actual dpkg -i on Jetson) deferred to Phase 5

## Self-Check: PASSED

- debian/postinst: FOUND
- debian/rules: FOUND
- 03-01-SUMMARY.md: FOUND
- Commit 858a7eb (Task 1): FOUND
- Commit d67da46 (Task 2): FOUND

---
*Phase: 03-install-lifecycle*
*Completed: 2026-03-17*
