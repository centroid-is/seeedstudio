# Phase 3: Install Lifecycle - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Create the postinst maintainer script that handles everything after dpkg installs the package files — blacklist stock r8168/r8169 drivers, run depmod, auto-detect MAC from enP8p1s0, write ethercat.conf, and start the EtherCAT service. Zero manual steps after dpkg -i.

</domain>

<decisions>
## Implementation Decisions

### Blacklist Strategy
- Use "install r8169 /bin/true" pattern (not "blacklist r8169") to prevent udev bypass
- Also blacklist r8168 the same way
- Write to /etc/modprobe.d/blacklist-eth.conf

### Service Ordering
- depmod -a MUST run before any systemctl invocation (locked decision from STATE.md)
- Service enable + start/restart as the final postinst step

### MAC Detection
- Auto-detect from /sys/class/net/enP8p1s0/address (hardcoded interface per PROJECT.md)

### Claude's Discretion
- Script error handling approach (set -e vs individual checks)
- Whether to use configure/upgrade/abort-upgrade case handling in postinst

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- debian/control — package name igh-seeedstudio already declared
- debian/rules — override_dh_auto_install stages files into debian/igh-seeedstudio/

### Established Patterns
- Hard tabs in debian/rules (Makefile format)
- Shell scripts use #!/bin/sh for POSIX compliance in Debian

### Integration Points
- postinst goes in debian/ directory
- Must be executable (like debian/rules)
- ethercat.conf needs MASTER0_DEVICE=<MAC> and DEVICE_MODULES="r8169"
- Blacklist file installed to /etc/modprobe.d/blacklist-eth.conf
- Static blacklist file can be shipped in debian/ and installed via rules, or written by postinst

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase

</specifics>

<deferred>
## Deferred Ideas

- update-initramfs -u after blacklist install (v2 requirement INST-07)
- postrm purge removes blacklist and conf files (v2 requirement REM-03)

</deferred>
