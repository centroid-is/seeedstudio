# Phase 2: Source and Build - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire up the IgH EtherCAT 1.6 source fetch and compilation pipeline within debian/rules so that dpkg-buildpackage produces igh-seeedstudio_1.6.0_arm64.deb containing ec_master.ko and ec_r8169.ko compiled against Tegra 5.15.148 kernel headers.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- debian/control — already declares build-essential, autoconf, automake, libtool, nvidia-l4t-kernel-headers
- debian/rules — minimal dh $@ scaffold ready for override targets
- debian/changelog — igh-seeedstudio 1.6.0 version already set

### Established Patterns
- Debian packaging with debhelper compat 13
- 3.0 (native) source format

### Integration Points
- debian/rules needs override_dh_auto_configure and override_dh_auto_build targets
- IgH source from https://gitlab.com/etherlab.org/ethercat.git stable-1.6
- Configure flags: --enable-r8169 --prefix=/usr --sysconfdir=/etc --with-linux-dir=<tegra-headers>
- Output modules under /lib/modules/5.15.148-tegra/extra/

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase

</specifics>

<deferred>
## Deferred Ideas

None

</deferred>
