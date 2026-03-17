---
phase: 04-removal-lifecycle
verified: 2026-03-17T18:00:00Z
status: passed
score: 3/3 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Run dpkg -r igh-seeedstudio on a Jetson with the package installed and service running, then dpkg -i again"
    expected: "Service stops cleanly, modules unload without errors, reinstall produces no module-in-use or service-already-running errors"
    why_human: "Requires live Jetson hardware with ethercat.service running and ec_master/ec_r8169 loaded; cannot simulate module state in a static grep check"
---

# Phase 4: Removal Lifecycle Verification Report

**Phase Goal:** dpkg -r or dpkg -P removes the package cleanly — service stopped, modules unloaded, no leftover state that prevents reinstall
**Verified:** 2026-03-17T18:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | prerm stops ethercat.service before any .ko files are removed | VERIFIED | Line 9: `systemctl stop ethercat.service \|\| true` guarded by `/run/systemd/system` check on line 8 |
| 2 | prerm unloads ec_master and ec_r8169 kernel modules before removal completes | VERIFIED | Line 14: `rmmod ec_r8169 2>/dev/null \|\| true`; Line 15: `rmmod ec_master 2>/dev/null \|\| true`; dependency order correct (ec_r8169 first) |
| 3 | Reinstalling the package after removal produces no module-in-use or service-already-running errors | VERIFIED (static) | `\|\| true` on all operations; `2>/dev/null \|\| true` on rmmod; service stop only if systemd present — all three are idempotent. Full reinstall path needs human/hardware verification (see below) |

**Score:** 3/3 truths verified (static analysis; reinstall cycle needs human confirmation)

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `debian/prerm` | Pre-removal maintainer script that stops service and unloads modules | VERIFIED | File exists (30 lines), is executable (`-rwxr-xr-x`), committed at `1b8b57b` |

#### Artifact Level Checks

**Level 1 — Exists:** `debian/prerm` present in repository root.

**Level 2 — Substantive (not a stub):**
- Line 1: `#!/bin/sh` (correct shebang)
- Line 3: `set -e` (error propagation)
- Line 5: `case "$1" in` dispatch present
- Line 6: `remove|upgrade)` case handles both dpkg actions
- Line 8–10: systemd-guarded service stop block
- Lines 14–15: Both rmmod invocations with correct flags
- Lines 17, 21: `#DEBHELPER#` token in both cases
- Line 30: `exit 0` at end
- 30 lines total — substantive, not a placeholder

**Level 3 — Wired:**
`debian/prerm` is a dpkg maintainer script; it is wired by convention — dpkg executes it automatically before file removal when installed. There is no import/usage chain to verify beyond the file existing and being executable. The script is correctly placed in `debian/` where `dh_installdeb` will include it in the package.

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `debian/prerm` | `ethercat.service` | `systemctl stop` | WIRED | Line 9: `systemctl stop ethercat.service \|\| true`; guarded by `/run/systemd/system` check on line 8 |
| `debian/prerm` | `ec_master, ec_r8169 kernel modules` | `rmmod` | WIRED | Line 14: `rmmod ec_r8169 2>/dev/null \|\| true`; Line 15: `rmmod ec_master 2>/dev/null \|\| true`; ec_r8169 before ec_master satisfies dependency order |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| REM-01 | 04-01-PLAN.md | prerm stops ethercat service before package removal | SATISFIED | `systemctl stop ethercat.service \|\| true` present, guarded by systemd check; comment `# --- REM-01: Stop ethercat service before removal ---` on line 7 |
| REM-02 | 04-01-PLAN.md | prerm unloads EtherCAT kernel modules | SATISFIED | `rmmod ec_r8169` and `rmmod ec_master` present with `2>/dev/null \|\| true`; comment `# --- REM-02: Unload kernel modules in dependency order ---` on line 12 |

**Orphaned requirements check:** REQUIREMENTS.md maps REM-01 and REM-02 to Phase 4 (both marked complete). No other requirements are mapped to Phase 4. No orphaned requirements found.

**Out-of-scope confirmation:** REM-03 (postrm purge removes blacklist and conf files) is a v2 requirement explicitly deferred. Confirmed absent from `debian/prerm` — no `postrm` or `purge` logic found.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | None | — | No TODO/FIXME/placeholder/stub patterns found |

No `return null`, empty handlers, console.log stubs, or placeholder comments detected.

---

### Structural Correctness

All items from the PLAN `<done>` checklist verified against actual file:

| Check | Expected | Actual | Pass |
|-------|----------|--------|------|
| Shebang | `#!/bin/sh` on line 1 | Line 1: `#!/bin/sh` | YES |
| Error handling | `set -e` on line 3 | Line 3: `set -e` | YES |
| Case dispatch | `case "$1" in` present | Line 5: `case "$1" in` | YES |
| Service stop guarded | systemd guard + `systemctl stop ethercat.service` | Lines 8–10 | YES |
| Module order | `rmmod ec_r8169` BEFORE `rmmod ec_master` | Lines 14, 15 | YES |
| Error-safe unload | Both rmmod use `2>/dev/null \|\| true` | Lines 14, 15 | YES |
| DEBHELPER token | `#DEBHELPER#` present | Lines 17, 21 | YES |
| Clean exit | `exit 0` at end | Line 30 | YES |
| No purge logic | Does NOT contain postrm/purge | Confirmed absent | YES |
| Executable bit | `chmod +x debian/prerm` | `test -x` returns true | YES |

---

### Human Verification Required

#### 1. Full Reinstall Cycle on Jetson Hardware

**Test:** On a Jetson with `igh-seeedstudio` installed and `ethercat.service` running with `ec_master` and `ec_r8169` loaded, run `sudo dpkg -r igh-seeedstudio`, then `sudo dpkg -i igh-seeedstudio_1.6.0_arm64.deb`.

**Expected:**
- `dpkg -r` exits 0, no errors; service stops before .ko removal
- After removal, `lsmod | grep ec_` returns nothing
- `dpkg -i` reinstall exits 0, no module-in-use or service-already-running errors

**Why human:** Requires live Jetson hardware with the service actually running and modules loaded. Static analysis confirms the script logic is correct, but the end-to-end removal-and-reinstall cycle can only be validated on hardware.

---

### Gaps Summary

No gaps found. All three observable truths are verified by static analysis. The sole human verification item (live reinstall cycle on hardware) is a real-world validation of logic that is demonstrably correct in the script.

**Commit:** `1b8b57b` — feat(04-01): add debian/prerm maintainer script for clean package removal (verified present in git log)

---

_Verified: 2026-03-17T18:00:00Z_
_Verifier: Claude (gsd-verifier)_
