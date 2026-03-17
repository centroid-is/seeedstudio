# Phase 6: CI/CD Pipeline - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Create a GitHub Actions workflow that builds the .deb on every push to main (using native arm64 runner), and creates a GitHub Release with the .deb as a downloadable artifact on v* tag push.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Dockerfile — already handles the full build pipeline (L4T repo, headers, dpkg-buildpackage)
- .dockerignore — build context already optimized

### Established Patterns
- Build happens inside Docker container (proven in Phase 5)
- L4T repo + dpkg -x for kernel headers extraction
- dpkg-buildpackage -us -uc -b produces the .deb

### Integration Points
- .github/workflows/ directory for GitHub Actions
- Runner: ubuntu-22.04-arm (native arm64, not QEMU)
- Trigger: push to main (build) + v* tag push (release)
- Artifact: igh-seeedstudio_1.6.0_arm64.deb
- gh run watch for monitoring

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase

</specifics>

<deferred>
## Deferred Ideas

None

</deferred>
