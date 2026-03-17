---
phase: 1
slug: debian-scaffold
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dpkg-dev CLI tools (dpkg-parsechangelog, dpkg-buildpackage) |
| **Config file** | none — debian/ files ARE the config |
| **Quick run command** | `dpkg-parsechangelog -l debian/changelog` |
| **Full suite command** | `dpkg-buildpackage --no-check-builddeps -d -tc 2>&1 | head -20` |
| **Estimated runtime** | ~2 seconds |

---

## Sampling Rate

- **After every task commit:** Run `dpkg-parsechangelog -l debian/changelog`
- **After every plan wave:** Run `dpkg-buildpackage --no-check-builddeps -d -tc 2>&1 | head -20`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 2 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 1-01-01 | 01 | 1 | DEB-01 | file check | `test -f debian/control && echo OK` | ⬜ W0 | ⬜ pending |
| 1-01-02 | 01 | 1 | DEB-01 | file check | `test -f debian/rules && test -x debian/rules && echo OK` | ⬜ W0 | ⬜ pending |
| 1-01-03 | 01 | 1 | DEB-01 | file check | `test -f debian/changelog && echo OK` | ⬜ W0 | ⬜ pending |
| 1-01-04 | 01 | 1 | DEB-01 | file check | `test -f debian/copyright && echo OK` | ⬜ W0 | ⬜ pending |
| 1-01-05 | 01 | 1 | DEB-03 | content | `grep -q 'Architecture: arm64' debian/control && echo OK` | ⬜ W0 | ⬜ pending |
| 1-01-06 | 01 | 1 | DEB-02 | parse | `dpkg-parsechangelog -l debian/changelog 2>&1 | grep -q 'Version:' && echo OK` | ⬜ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- Existing dpkg-dev tools provide all validation — no additional test infrastructure needed.

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| dpkg-buildpackage full parse | DEB-02 | Requires dpkg-dev installed on build host | Run `dpkg-buildpackage --no-check-builddeps -d -tc` and verify exit 0 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 2s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
