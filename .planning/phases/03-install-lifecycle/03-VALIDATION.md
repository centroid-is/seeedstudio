---
phase: 3
slug: install-lifecycle
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | File content checks (grep, test) + Docker install verification (Phase 5) |
| **Config file** | debian/postinst |
| **Quick run command** | `test -f debian/postinst && test -x debian/postinst && echo OK` |
| **Full suite command** | `grep -c 'depmod\|MASTER0_DEVICE\|blacklist\|systemctl\|DEVICE_MODULES' debian/postinst` |
| **Estimated runtime** | ~1 second |

---

## Sampling Rate

- **After every task commit:** Run quick existence/executable check
- **After every plan wave:** Run full content verification
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 1 second

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | INST-01 | content | `grep -q 'install r8169 /bin/true' debian/postinst && echo OK` | ⬜ W0 | ⬜ pending |
| 3-01-02 | 01 | 1 | INST-02 | content | `grep -q 'depmod' debian/postinst && echo OK` | ⬜ W0 | ⬜ pending |
| 3-01-03 | 01 | 1 | INST-03 | content | `grep -q 'enP8p1s0/address' debian/postinst && echo OK` | ⬜ W0 | ⬜ pending |
| 3-01-04 | 01 | 1 | INST-04 | content | `grep -q 'DEVICE_MODULES="r8169"' debian/postinst && echo OK` | ⬜ W0 | ⬜ pending |
| 3-01-05 | 01 | 1 | INST-05 | content | `grep -q 'systemctl.*ethercat' debian/postinst && echo OK` | ⬜ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- Existing file content checks provide all validation — no additional test infrastructure needed.
- Full runtime verification deferred to Phase 5 Docker (dpkg -i inside container).

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| dpkg -i installs blacklist + ethercat.conf + starts service | INST-01 thru INST-05 | Requires running kernel + systemd | Run `dpkg -i *.deb` on Jetson or in Docker, verify files and service |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 1s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
