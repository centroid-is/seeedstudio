---
phase: 5
slug: docker-verification
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-17
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | File content checks (grep, test) + Docker build (manual/CI) |
| **Config file** | Dockerfile |
| **Quick run command** | `test -f Dockerfile && grep -q 'dpkg-buildpackage' Dockerfile && echo OK` |
| **Full suite command** | `grep -c 'dpkg-buildpackage\|dpkg -i\|ec_r8169' Dockerfile` |
| **Estimated runtime** | ~1 second (content checks); ~10-30 min (actual docker build on arm64) |

---

## Sampling Rate

- **After every task commit:** Run quick content checks on Dockerfile
- **After every plan wave:** Run full content verification
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 1 second (content checks)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 5-01-01 | 01 | 1 | DOC-01 | content | `grep -q 'ubuntu:22.04' Dockerfile && grep -q 'dpkg-buildpackage' Dockerfile && echo OK` | ⬜ W0 | ⬜ pending |
| 5-01-02 | 01 | 1 | DOC-02 | content | `grep -q 'dpkg -i' Dockerfile && echo OK` | ⬜ W0 | ⬜ pending |
| 5-01-03 | 01 | 1 | DOC-03 | content | `grep -q 'ec_r8169' Dockerfile && echo OK` | ⬜ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- Existing file content checks provide all validation — no additional test infrastructure needed.
- Full docker build verification is a manual step requiring an arm64 machine.

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| docker build completes on aarch64 | DOC-01 | Requires arm64 Docker host | Run `docker build -t igh-seeedstudio .` on arm64 |
| dpkg -i exits 0 in container | DOC-02 | Part of docker build pipeline | Check docker build output for dpkg -i exit code |
| ec_r8169.ko present after make | DOC-03 | Part of docker build pipeline | Check docker build output for assertion |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 1s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
