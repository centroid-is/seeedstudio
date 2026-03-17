# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — IgH EtherCAT Debian Package

**Shipped:** 2026-03-17
**Phases:** 6 | **Plans:** 6 | **Sessions:** 1

### What Was Built
- Complete Debian package scaffold (debian/control, rules, changelog, copyright, compat, source/format)
- IgH EtherCAT 1.6 build pipeline with 7 debhelper override targets
- Install lifecycle (postinst): blacklist, MAC detection, ethercat.conf, depmod-safe service start
- Removal lifecycle (prerm): service stop, dependency-ordered module unload
- Dockerfile for end-to-end build verification with L4T kernel header workaround
- GitHub Actions CI with native arm64 runner and tag-triggered releases

### What Worked
- Single-session completion: all 6 phases planned + executed in one sitting
- Research-first approach caught critical issues early (debhelper ordering conflict, nvidia-l4t-core preinst /proc check)
- Plan checker caught real bugs (missing `<done>` elements, wrong file paths in VALIDATION.md)
- Infrastructure phases are fast: no test suite needed, content checks (grep, test) provide instant feedback
- Gap closure loop fixed the debian/rules shebang issue without needing a full re-plan

### What Was Inefficient
- Integration checker raised false positives about dh_installmodules and ethercat.service (misunderstood debhelper compat 13 behavior)
- VALIDATION.md files created but never marked compliant (Nyquist validation is overhead for infrastructure-only projects)
- Summary extraction via gsd-tools returned None for all phases (one-liner field not populated by executor)

### Patterns Established
- `install /bin/true` blacklist pattern (stronger than `blacklist` keyword)
- `#DEBHELPER#` token placement: custom code before, service start after
- `apt-get download + dpkg -x` pattern for installing L4T packages in Docker
- Dockerfile as CI single source of truth (no duplicated build logic in workflow YAML)

### Key Lessons
1. For infrastructure projects (shell scripts, Dockerfiles, YAML), file content checks (grep, test -f) are sufficient validation — full test frameworks add no value
2. debhelper ordering conflicts (dh_installsystemd before dh_installmodules) require explicit --no-start workaround — this is a well-known Debian packaging gotcha
3. NVIDIA L4T kernel headers can't be installed normally in Docker due to preinst device-tree checks — always use dpkg -x extraction

### Cost Observations
- Model mix: opus orchestrator, sonnet subagents (research, plan, execute, verify, integration check)
- Sessions: 1 (complete milestone in single session)
- Notable: 6 phases in ~3 hours wall clock time; execution averaged 1-2 minutes per plan

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | 1 | 6 | Initial milestone — established all patterns |

### Cumulative Quality

| Milestone | Requirements | Coverage | Verification |
|-----------|-------------|----------|-------------|
| v1.0 | 21/21 | 100% | 3 passed, 3 human_needed (arm64 hardware) |

### Top Lessons (Verified Across Milestones)

1. Research before planning catches architecture-level issues that would be expensive to fix during execution
2. Infrastructure phases execute fast — plan conservatively, execute quickly
