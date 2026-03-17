---
phase: 2
slug: source-and-build
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | File content checks (grep, test) + Docker build verification (Phase 5) |
| **Config file** | debian/rules (override targets) |
| **Quick run command** | `grep -q 'override_dh_auto_configure' debian/rules && echo OK` |
| **Full suite command** | `grep -c 'override_dh_' debian/rules` |
| **Estimated runtime** | ~1 second |

---

## Sampling Rate

- **After every task commit:** Run quick content checks on debian/rules
- **After every plan wave:** Run full content verification suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 1 second

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | SRC-01 | content | `grep -q 'etherlab.org/ethercat.git' debian/rules && echo OK` | ⬜ W0 | ⬜ pending |
| 2-01-02 | 01 | 1 | SRC-03 | content | `grep -q '\-\-enable-r8169' debian/rules && echo OK` | ⬜ W0 | ⬜ pending |
| 2-01-03 | 01 | 1 | SRC-03 | content | `grep -q '\-\-prefix=/usr' debian/rules && echo OK` | ⬜ W0 | ⬜ pending |
| 2-01-04 | 01 | 1 | SRC-04 | content | `grep -q 'ec_r8169' debian/rules && echo OK` | ⬜ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- Existing file content checks provide all validation — no additional test infrastructure needed.
- Full build verification deferred to Phase 5 Docker.

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| dpkg-buildpackage produces .deb | SRC-04 | Requires arm64 build environment with Tegra headers | Run `dpkg-buildpackage` in Docker or on Jetson |
| ec_master.ko and ec_r8169.ko in .deb | SRC-04 | Requires actual compilation | Check `dpkg -c *.deb | grep '\.ko$'` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 1s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
