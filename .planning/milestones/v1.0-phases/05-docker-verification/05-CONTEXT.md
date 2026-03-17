# Phase 5: Docker Verification - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Create a Dockerfile that builds the .deb package from scratch in an aarch64 ubuntu:22.04 environment, verifies dpkg -i succeeds, and confirms ec_r8169.ko was built. This is the end-to-end verification that validates Phases 1-4.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- debian/ directory — complete packaging scaffold (control, rules, changelog, copyright, postinst, prerm)
- debian/rules — full build pipeline with 7 override targets
- debian/control — Build-Depends list for apt-get install

### Established Patterns
- IgH source fetched via git clone in debian/rules (not pre-downloaded)
- Build requires Tegra kernel headers (nvidia-l4t-kernel-headers)
- ec_r8169.ko assertion already in debian/rules override_dh_auto_build

### Integration Points
- Dockerfile at project root
- Base image: ubuntu:22.04 (aarch64)
- Must install dpkg-dev, debhelper, and all Build-Depends from debian/control
- NVIDIA L4T apt repo needed for nvidia-l4t-kernel-headers
- dpkg-buildpackage produces the .deb
- dpkg -i verifies install succeeds
- Need to assert ec_r8169.ko exists after build

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase

</specifics>

<deferred>
## Deferred Ideas

None

</deferred>
