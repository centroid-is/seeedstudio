# Phase 4: Removal Lifecycle - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Create the prerm maintainer script that handles clean package removal — stop the ethercat service and unload EtherCAT kernel modules before dpkg removes files. Must not leave state that prevents reinstall.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- debian/postinst — existing maintainer script pattern to follow (POSIX sh, set -e, case $1 in configure)
- debian/rules — override_dh_installsystemd --no-start already set

### Established Patterns
- POSIX sh with #!/bin/sh
- set -e for error handling
- case "$1" in pattern for dpkg action routing
- #DEBHELPER# token for debhelper expansion
- || true for non-critical operations

### Integration Points
- prerm goes in debian/ directory
- Must be executable (chmod +x)
- Service name: ethercat.service
- Kernel modules: ec_master, ec_r8169

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase

</specifics>

<deferred>
## Deferred Ideas

- postrm purge removes blacklist and conf files (v2 requirement REM-03)

</deferred>
