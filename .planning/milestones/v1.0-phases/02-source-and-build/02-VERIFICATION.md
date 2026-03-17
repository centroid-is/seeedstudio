---
phase: 02-source-and-build
verified: 2026-03-17T17:00:00Z
status: human_needed
score: 5/5 must-haves verified (2 success criteria need live build to confirm)
human_verification:
  - test: "Run dpkg-buildpackage in arm64 environment with Tegra headers and confirm output file is named igh-seeedstudio_1.6.0_arm64.deb"
    expected: "File igh-seeedstudio_1.6.0_arm64.deb is produced in the parent directory"
    why_human: "Output filename depends on debian/changelog version + Architecture field + actual dpkg-buildpackage execution; cannot be verified by static file analysis"
  - test: "Inspect the built .deb and confirm both ec_master.ko and ec_r8169.ko are installed under /lib/modules/5.15.148-tegra/extra/"
    expected: "dpkg -c igh-seeedstudio_1.6.0_arm64.deb | grep '.ko' shows both modules at ./lib/modules/5.15.148-tegra/extra/ec_master.ko and ./lib/modules/5.15.148-tegra/extra/ec_r8169.ko"
    why_human: "Module presence in the .deb requires actual compilation against Tegra kernel headers on arm64; static analysis can only confirm the build script is wired correctly to produce them"
---

# Phase 2: Source and Build Verification Report

**Phase Goal:** Running dpkg-buildpackage inside the build environment produces igh-seeedstudio_1.6.0_arm64.deb containing both ec_master.ko and ec_r8169.ko compiled against the Tegra 5.15.148 kernel headers
**Verified:** 2026-03-17T17:00:00Z
**Status:** human_needed — all 5 static must-haves verified; 2 success criteria require a live arm64 build run
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from must_haves in PLAN frontmatter)

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | debian/rules fetches IgH EtherCAT source from GitLab stable-1.6 via git clone | VERIFIED | Line 14: `git clone --depth 1 --branch stable-1.6 \` Line 15: `https://gitlab.com/etherlab.org/ethercat.git $(SRCDIR)` — command split across lines with backslash continuation |
| 2 | debian/rules configures with --enable-r8169, --prefix=/usr, --sysconfdir=/etc, --with-linux-dir, --with-module-dir=extra | VERIFIED | Lines 21-29: all five flags present in override_dh_auto_configure; KDIR=/usr/src/linux-headers-5.15.148-tegra |
| 3 | debian/rules builds userspace + kernel modules and asserts ec_r8169.ko exists | VERIFIED | Lines 33-36: `$(MAKE) -C $(SRCDIR) all modules` + `test -f $(SRCDIR)/devices/r8169/ec_r8169.ko` assertion with error message |
| 4 | debian/rules installs with correct DESTDIR and INSTALL_MOD_PATH into package staging | VERIFIED | Line 40: `$(MAKE) -C $(SRCDIR) DESTDIR=$(PKGDIR) install` Line 41: `$(MAKE) -C $(SRCDIR) INSTALL_MOD_PATH=$(PKGDIR) modules_install` |
| 5 | debian/control declares git and pkg-config in Build-Depends | VERIFIED | Lines 10-11: `pkg-config,` and `git,` present, properly aligned, in correct position (after libtool, before nvidia-l4t-kernel-headers) |

**Score:** 5/5 truths verified

### ROADMAP Success Criteria Coverage

The ROADMAP defines 4 success criteria for Phase 2:

| # | Success Criterion | Status | Evidence |
|---|-------------------|--------|---------|
| 1 | IgH EtherCAT source fetched from gitlab.com/etherlab.org/ethercat.git stable-1.6 | VERIFIED | git clone command in override_dh_update_autotools_config; both URL parts confirmed |
| 2 | configure runs with --enable-r8169, --prefix=/usr, --sysconfdir=/etc, --with-linux-dir pointing to Tegra headers | VERIFIED | All flags present; KDIR := /usr/src/linux-headers-5.15.148-tegra at top of file |
| 3 | Both ec_master.ko and ec_r8169.ko present in built .deb under /lib/modules/5.15.148-tegra/extra/ | NEEDS HUMAN | ec_r8169.ko presence is asserted by test -f at build time; --with-module-dir=extra routes both modules to extra/; actual .deb content requires live build |
| 4 | Output file named igh-seeedstudio_1.6.0_arm64.deb | NEEDS HUMAN | debian/changelog declares version 1.6.0, debian/control declares Architecture: arm64 — correct inputs present; actual filename confirmed only by running dpkg-buildpackage |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `debian/rules` | Complete build pipeline with 7 override targets | VERIFIED | 53 lines, executable, hard tabs, shebang `#!/usr/bin/make -f`; 7 override_dh_* targets confirmed by grep count |
| `debian/control` | Updated Build-Depends with git and pkg-config | VERIFIED | 8 Build-Depends entries; single Build-Depends field; no trailing comma on final entry (nvidia-l4t-kernel-headers) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| override_dh_update_autotools_config | https://gitlab.com/etherlab.org/ethercat.git | git clone --depth 1 --branch stable-1.6 | VERIFIED | Line 14-15: clone command split over two lines (backslash continuation); both stable-1.6 and gitlab.com/etherlab.org URL confirmed present |
| override_dh_auto_configure | /usr/src/linux-headers-5.15.148-tegra | --with-linux-dir=$(KDIR) | VERIFIED | KDIR defined at line 5 as exact Tegra path; --with-linux-dir=$(KDIR) at line 23 |
| override_dh_auto_build | ethercat-src/devices/r8169/ec_r8169.ko | test -f assertion | VERIFIED | Line 35: `test -f $(SRCDIR)/devices/r8169/ec_r8169.ko` with exit 1 on failure |
| override_dh_auto_install | debian/igh-seeedstudio | DESTDIR and INSTALL_MOD_PATH | VERIFIED | PKGDIR=$(CURDIR)/debian/igh-seeedstudio; line 40 DESTDIR, line 41 INSTALL_MOD_PATH both reference $(PKGDIR) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| SRC-01 | 02-01-PLAN.md | Package fetches IgH EtherCAT 1.6 source from official GitLab repo (stable-1.6) | SATISFIED | override_dh_update_autotools_config clones from https://gitlab.com/etherlab.org/ethercat.git --branch stable-1.6 |
| SRC-02 | 02-01-PLAN.md | Package installs build-essential and automake as build dependencies | SATISFIED | debian/control Build-Depends lists build-essential and automake (both present from Phase 1; confirmed no regression) |
| SRC-03 | 02-01-PLAN.md | Configure runs with --enable-r8169 --with-linux-dir pointing to Tegra 5.15.148 kernel headers | SATISFIED | --enable-r8169 and --with-linux-dir=$(KDIR) present; KDIR := /usr/src/linux-headers-5.15.148-tegra |
| SRC-04 | 02-01-PLAN.md | make and make modules produce ec_master and ec_r8169 kernel modules | SATISFIED (static) | `$(MAKE) -C $(SRCDIR) all modules` in override_dh_auto_build; ec_r8169.ko assertion added to fail loudly if silently dropped; ec_master.ko produced by default IgH build; actual .ko presence confirmed only at build time |

No orphaned requirements: REQUIREMENTS.md traceability table maps SRC-01 through SRC-04 exclusively to Phase 2, and all four are covered by 02-01-PLAN.md.

### Commit Verification

Both commits claimed in SUMMARY.md exist and are valid:

| Commit | Hash | Files Changed | Description |
|--------|------|---------------|-------------|
| Task 1 | 7981141 | debian/control (+2 lines) | Add git and pkg-config to Build-Depends |
| Task 2 | aa0730a | debian/rules (+48 lines) | Implement complete IgH EtherCAT build pipeline |

### Anti-Patterns Found

No anti-patterns detected.

| File | Pattern | Result |
|------|---------|--------|
| debian/rules | TODO/FIXME/PLACEHOLDER | None found |
| debian/rules | Empty implementations (return null, stub handlers) | None found |
| debian/control | TODO/FIXME/PLACEHOLDER | None found |
| debian/rules | Space-indented recipe lines (Makefile violation) | None found — all recipes use hard tabs |

### Additional Quality Checks

- `debian/rules` executable bit: confirmed (`file` reports "executable")
- Shebang line: `#!/usr/bin/make -f` (correct)
- Hard tabs on all recipe lines: confirmed (Python byte-level check)
- No trailing comma on final Build-Depends entry (nvidia-l4t-kernel-headers): confirmed
- Phase 1 regression check: Architecture: arm64 still present; `dh $@` sequencer still present
- override_dh_autoreconf with `@true`: present — prevents dh_autoreconf running in wrong directory
- override_dh_shlibdeps with `-X.ko`: present — prevents dpkg-shlibdeps errors on kernel module ELF files
- --enable-generic included: present — provides ec_generic.ko fallback driver alongside ec_r8169.ko
- Unneeded drivers disabled (--disable-8139too, --disable-e1000, --disable-e1000e): all three confirmed

### Human Verification Required

#### 1. Output .deb Filename

**Test:** Run `dpkg-buildpackage -us -uc -b` inside an arm64 environment and list the parent directory
**Expected:** File `igh-seeedstudio_1.6.0_arm64.deb` is produced
**Why human:** The output filename is derived from debian/changelog version (1.6.0) and Architecture (arm64) — both are correctly set in the files — but confirmation requires dpkg-buildpackage to actually execute. The arm64 + Tegra headers environment is deferred to Phase 5 (Docker verification).

#### 2. Module Content in Built .deb

**Test:** After a successful build, run `dpkg -c igh-seeedstudio_1.6.0_arm64.deb | grep '\.ko'`
**Expected:** Output includes both `./lib/modules/5.15.148-tegra/extra/ec_master.ko` and `./lib/modules/5.15.148-tegra/extra/ec_r8169.ko`
**Why human:** The build pipeline is correctly wired (--with-module-dir=extra, INSTALL_MOD_PATH, ec_r8169.ko assertion), but physical .ko creation requires compilation against actual Tegra 5.15.148 kernel headers on arm64. The assertion at `test -f $(SRCDIR)/devices/r8169/ec_r8169.ko` will surface any compile-time failure immediately.

### Summary

Phase 2's deliverable is a build pipeline, not a built artifact. All five static must-haves are fully implemented and wired:

- debian/rules has 7 complete override targets (fetch, configure, build, install, clean, autoreconf skip, shlibdeps exclusion)
- debian/control has all 8 required Build-Depends with no regressions
- Every key link is verified: source URL, KDIR path, ec_r8169.ko assertion path, DESTDIR/INSTALL_MOD_PATH staging paths
- All 4 requirements (SRC-01 through SRC-04) are satisfied by the static implementation

The two items requiring human verification are inherent to the phase design: the phase ROADMAP goal states "running dpkg-buildpackage produces..." which cannot be confirmed without an arm64 + Tegra headers build environment. The SUMMARY itself notes "Full dpkg-buildpackage validation requires arm64 environment with Tegra kernel headers (deferred to Phase 5 Docker build)" — this is correct and expected. Phase 3 (install scripts) can proceed immediately.

---

_Verified: 2026-03-17T17:00:00Z_
_Verifier: Claude (gsd-verifier)_
