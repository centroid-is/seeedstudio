---
phase: 05-docker-verification
plan: 01
subsystem: infra
tags: [docker, dockerfile, dpkg-buildpackage, nvidia-l4t, ubuntu-22.04, aarch64]

# Dependency graph
requires:
  - phase: 01-debian-scaffold
    provides: debian/control Build-Depends, debian/rules KDIR
  - phase: 02-source-and-build
    provides: debian/rules build targets with ec_r8169.ko assertion
  - phase: 03-install-lifecycle
    provides: debian/postinst with Docker-safe systemd/MAC guards
  - phase: 04-removal-lifecycle
    provides: debian/prerm with Docker-safe systemd/rmmod guards
provides:
  - Dockerfile for end-to-end .deb build and install verification
  - .dockerignore excluding .git, .planning, *.deb from build context
  - Reproducible smoke test validating Phases 1-4 in isolated container
affects: []

# Tech tracking
tech-stack:
  added: [docker, ubuntu:22.04, nvidia-l4t-r36.4-repo]
  patterns: [apt-get-download-dpkg-x-extraction, l4t-trusted-gpg-d-key-pattern]

key-files:
  created: [Dockerfile, .dockerignore]
  modified: []

key-decisions:
  - "Used apt-get download + dpkg -x for nvidia-l4t-kernel-headers (bypass nvidia-l4t-core preinst /proc/device-tree check)"
  - "No || true on dpkg -i step (fail loudly on install error)"
  - "Used r36.4 release designation for L4T apt repo (matches 5.15.148-tegra kernel)"

patterns-established:
  - "L4T repo in Docker: ADD GPG key to trusted.gpg.d + echo repos to sources.list.d"
  - "Kernel header extraction: apt-get download + dpkg -x (bypasses preinst scripts)"

requirements-completed: [DOC-01, DOC-02, DOC-03]

# Metrics
duration: 1min
completed: 2026-03-17
---

# Phase 5 Plan 1: Docker Verification Summary

**Dockerfile with ubuntu:22.04 base, L4T r36.4 repo setup, dpkg-buildpackage, dpkg -i install, and ec_r8169.ko/ec_master.ko/ethercat assertions**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-17T17:50:10Z
- **Completed:** 2026-03-17T17:51:36Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created .dockerignore excluding .git, .planning, and *.deb from Docker build context
- Created Dockerfile that builds the .deb from scratch in ubuntu:22.04 with NVIDIA L4T r36.4 repos
- Dockerfile extracts nvidia-l4t-kernel-headers via apt-get download + dpkg -x (bypasses nvidia-l4t-core preinst)
- Dockerfile runs dpkg -i without || true (fails loudly on install error)
- Final assertions verify ec_r8169.ko, ec_master.ko, and /usr/bin/ethercat are present

## Task Commits

Each task was committed atomically:

1. **Task 1: Create .dockerignore** - `fed482b` (chore)
2. **Task 2: Create Dockerfile for end-to-end build and install verification** - `a8cd04d` (feat)

## Files Created/Modified
- `.dockerignore` - Excludes .git, .planning, *.deb from Docker build context
- `Dockerfile` - End-to-end build and install verification (8 stages: base, ca-certs, L4T repo, build-deps, kernel headers, build, install, assertions)

## Decisions Made
- Used `apt-get download` + `dpkg -x` for nvidia-l4t-kernel-headers instead of `apt-get install` (bypasses nvidia-l4t-core preinst that checks /proc/device-tree/compatible, which does not exist in Docker containers)
- No `|| true` on `dpkg -i` step so install errors fail the Docker build loudly
- Used `r36.4` as the L4T release designation (kernel 5.15.148-tegra = L4T R36.4.x / JetPack 6.2.x)
- Added both `common` and `t234` (Orin platform) repos for complete L4T package coverage

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Docker verification Dockerfile is complete and ready for runtime testing on a native aarch64 host (Jetson device or arm64 CI runner)
- Runtime verification (actually running `docker build`) deferred to Phase 6 CI or manual Jetson test
- All Phase 1-4 artifacts are validated by the Dockerfile structure (Build-Depends, KDIR, postinst guards, prerm guards)

## Self-Check: PASSED

- FOUND: .dockerignore
- FOUND: Dockerfile
- FOUND: 05-01-SUMMARY.md
- FOUND: fed482b (Task 1 commit)
- FOUND: a8cd04d (Task 2 commit)

---
*Phase: 05-docker-verification*
*Completed: 2026-03-17*
