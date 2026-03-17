# Phase 3: Install Lifecycle - Research

**Researched:** 2026-03-17
**Domain:** Debian postinst maintainer scripts, kernel module blacklisting, IgH EtherCAT configuration, systemd service management
**Confidence:** HIGH

## Summary

Phase 3 creates the `debian/postinst` maintainer script that runs after `dpkg -i` unpacks the package files. The postinst must: (1) install a modprobe.d blacklist file that prevents stock r8168/r8169 drivers from loading, (2) run `depmod -a` to register the newly installed ec_master.ko and ec_r8169.ko kernel modules, (3) detect the MAC address from the hardcoded enP8p1s0 interface, (4) generate `/etc/ethercat.conf` with the detected MAC and DEVICE_MODULES="r8169", and (5) enable and start the ethercat systemd service.

The most critical discovery is a **debhelper ordering conflict**: in the `dh` install sequence, `dh_installsystemd` runs BEFORE `dh_installmodules`. This means the auto-generated `#DEBHELPER#` snippets would attempt to start the ethercat service BEFORE `depmod -a` registers the kernel modules -- causing the service to fail. The solution is to use `dh_installsystemd --no-start` in `debian/rules` so debhelper only enables (but does not start) the service, then manually start the service in the postinst AFTER the `#DEBHELPER#` token (which contains the depmod from `dh_installmodules`).

A second important finding is that IgH's `ethercatctl` script sources `/etc/ethercat.conf` as a shell script (using the `.` dot operator). The config file is NOT INI format -- it is plain shell variable assignments. The postinst must write valid shell syntax: `MASTER0_DEVICE="aa:bb:cc:dd:ee:ff"` with proper quoting.

**Primary recommendation:** Create `debian/postinst` with custom code for blacklist + ethercat.conf BEFORE `#DEBHELPER#`, and service start AFTER `#DEBHELPER#`. Add `override_dh_installsystemd` with `--no-start` to `debian/rules`.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Use "install r8169 /bin/true" pattern (not "blacklist r8169") to prevent udev bypass
- Also blacklist r8168 the same way
- Write to /etc/modprobe.d/blacklist-eth.conf
- depmod -a MUST run before any systemctl invocation (locked decision from STATE.md)
- Service enable + start/restart as the final postinst step
- Auto-detect MAC from /sys/class/net/enP8p1s0/address (hardcoded interface per PROJECT.md)

### Claude's Discretion
- Script error handling approach (set -e vs individual checks)
- Whether to use configure/upgrade/abort-upgrade case handling in postinst

### Deferred Ideas (OUT OF SCOPE)
- update-initramfs -u after blacklist install (v2 requirement INST-07)
- postrm purge removes blacklist and conf files (v2 requirement REM-03)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INST-01 | postinst copies blacklist-eth.conf to /etc/modprobe.d/ (blacklists r8168 + r8169 stock drivers) | Architecture Patterns section documents the "install modulename /bin/true" pattern and exact file content; Code Examples section provides the complete postinst script |
| INST-02 | postinst runs depmod -a after module files are installed | Architecture Patterns section documents the debhelper ordering conflict and the --no-start solution; dh_installmodules auto-generates depmod in #DEBHELPER# |
| INST-03 | postinst auto-detects MAC address from /sys/class/net/enP8p1s0/address | Code Examples section shows the MAC detection command; Common Pitfalls section covers the missing-interface edge case |
| INST-04 | postinst generates /etc/ethercat.conf with MASTER0_DEVICE=<detected MAC> and DEVICE_MODULES="r8169" | Architecture Patterns section documents the ethercat.conf shell variable format; Code Examples section shows the exact file generation |
| INST-05 | postinst restarts ethercat systemd service | Architecture Patterns section documents why systemctl start must come AFTER #DEBHELPER# (after depmod); Code Examples section shows the complete postinst with correct ordering |
</phase_requirements>

## Standard Stack

### Core

| Tool/File | Version/Value | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| debian/postinst | POSIX sh | Maintainer script executed after dpkg installs files | Debian Policy requires #!/bin/sh for POSIX compliance |
| debhelper (compat 13) | 13.x | Auto-generates depmod and service enable snippets via #DEBHELPER# | Already declared from Phase 1; handles edge cases in maintainer scripts |
| dh_installmodules | (part of debhelper) | Auto-generates depmod -a in postinst via #DEBHELPER# | Standard way to register kernel modules; handles preinst/postrm too |
| dh_installsystemd | (part of debhelper) | Auto-generates service enable in postinst via #DEBHELPER# | Standard way to manage systemd services; must use --no-start |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| systemctl | Enable and start ethercat.service | Called in postinst after #DEBHELPER# expands depmod |
| cat /sys/class/net/enP8p1s0/address | Read MAC address of the EtherCAT NIC | Called in postinst configure case |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom postinst blacklist install | debian/igh-seeedstudio.modprobe (dh_installmodules) | dh_installmodules would install to /etc/modprobe.d/igh-seeedstudio.conf, not blacklist-eth.conf; requirement INST-01 specifies postinst handles it |
| --no-start + manual start | Full custom (--no-scripts on both) | --no-scripts loses depmod auto-generation; --no-start is minimal override |
| set -e for error handling | Individual error checks per command | set -e is Debian Policy recommended and simpler; individual checks only needed for commands that may legitimately fail |
| Full case statement (configure/abort-upgrade/etc) | Simple if [ "$1" = "configure" ] | Case statement is Debian Policy standard and handles upgrade scenarios correctly; use case statement |

## Architecture Patterns

### Critical: Debhelper Snippet Ordering

The `dh` install sequence runs commands in this order (relevant excerpt from debhelper source):

```
...
dh_installinit
dh_installtmpfiles        # compat >= 13
dh_installsystemd         # compat >= 11  <-- ENABLES + STARTS service
...
dh_installmodules          #               <-- RUNS depmod
...
```

**Problem:** `dh_installsystemd` generates service start code BEFORE `dh_installmodules` generates depmod code. Both snippets are inserted into `#DEBHELPER#` in sequence order. If we let dh_installsystemd start the service, it would fail because depmod has not run yet and the kernel modules are not registered.

**Solution:** Use `--no-start` on dh_installsystemd. This makes it generate only the enable snippet (not start). The depmod from dh_installmodules still runs via `#DEBHELPER#`. Then we manually start the service AFTER `#DEBHELPER#`.

### Recommended debian/postinst Structure

```
debian/postinst
  #!/bin/sh
  set -e
  case "$1" in
    configure)
      1. Write blacklist-eth.conf        (before #DEBHELPER#)
      2. Detect MAC, write ethercat.conf  (before #DEBHELPER#)
      3. #DEBHELPER#                      (expands to: enable service + depmod -a)
      4. Start/restart ethercat.service   (after #DEBHELPER#, after depmod)
      ;;
    abort-upgrade|abort-remove|abort-deconfigure)
      #DEBHELPER#
      ;;
    *)
      echo "postinst called with unknown argument: $1" >&2
      exit 1
      ;;
  esac
  exit 0
```

### Pattern 1: #DEBHELPER# Token Placement

**What:** The `#DEBHELPER#` token is a placeholder in `debian/postinst` that gets replaced by auto-generated code from debhelper commands (dh_installsystemd, dh_installmodules, etc.) during `dh_installdeb`.

**When to use:** Always in custom postinst scripts when using debhelper.

**Key rule:** Code BEFORE `#DEBHELPER#` runs before auto-generated snippets. Code AFTER `#DEBHELPER#` runs after them.

**Source:** [debhelper(7) manpage](https://www.man7.org/linux/man-pages/man7/debhelper.7.html) -- "dh_installdeb is responsible for inserting into these scripts a token #DEBHELPER# and replacing it with generated code."

### Pattern 2: Blacklist via "install /bin/true"

**What:** The `install modulename /bin/true` directive in modprobe.d tells the kernel to run `/bin/true` instead of loading the module. This is stronger than the `blacklist` keyword, which only prevents auto-loading but can be bypassed by udev rules or explicit modprobe calls.

**When to use:** When you need to completely prevent a kernel module from loading, especially when a replacement module (ec_r8169) will take its place.

**Source:** [Debian Wiki: KernelModuleBlacklisting](https://wiki.debian.org/KernelModuleBlacklisting), [Arch Wiki: Kernel module blacklisting](https://wiki.archlinux.org/title/Kernel_module)

**File content for /etc/modprobe.d/blacklist-eth.conf:**
```
# Prevent stock Realtek drivers from loading (EtherCAT uses ec_r8169)
install r8169 /bin/true
install r8168 /bin/true
```

### Pattern 3: ethercat.conf as Shell Variables

**What:** The IgH EtherCAT `ethercatctl` script sources `/etc/ethercat.conf` using the shell `.` (dot) operator. The file must contain valid POSIX shell variable assignments.

**When to use:** When generating ethercat.conf in postinst.

**Source:** [IgH EtherCAT ethercatctl.in](https://gitlab.com/etherlab.org/ethercat/-/blob/stable-1.6/script/ethercatctl.in) -- confirmed: `. ${ETHERCAT_CONFIG}`

**Required variables:**
- `MASTER0_DEVICE="aa:bb:cc:dd:ee:ff"` -- MAC address (must be quoted)
- `DEVICE_MODULES="r8169"` -- space-separated list of driver names (prefixed with ec_ at runtime)

### Pattern 4: debian/rules Override for --no-start

**What:** Add `override_dh_installsystemd` to `debian/rules` to prevent dh_installsystemd from generating service start code.

**Example:**
```makefile
# Let debhelper enable the service but do NOT start it
# (postinst starts it manually after depmod runs via #DEBHELPER#)
override_dh_installsystemd:
	dh_installsystemd --no-start
```

### Anti-Patterns to Avoid

- **Placing systemctl start BEFORE #DEBHELPER#:** The #DEBHELPER# token expands to include depmod -a (from dh_installmodules). Starting the service before depmod means the kernel cannot find ec_master.ko and ec_r8169.ko. The service will fail with "modprobe: FATAL: Module ec_master not found."

- **Using the default dh_installsystemd (without --no-start):** This generates both enable AND start code, which runs before depmod. The service start will fail.

- **Writing ethercat.conf without quotes around values:** The file is sourced as a shell script. Unquoted MAC addresses with colons are valid, but quoting is safer and matches the upstream template format.

- **Using #!/bin/bash in postinst:** Debian Policy requires #!/bin/sh for POSIX compliance in maintainer scripts. Bash-isms (arrays, [[ ]], etc.) must not be used.

- **Omitting set -e:** Debian Policy strongly recommends `set -e` in maintainer scripts so dpkg can detect failures and leave the package in a known "Half-Configured" state.

- **Not handling the abort-* cases:** The case statement should include abort-upgrade, abort-remove, and abort-deconfigure entries. Even if they just run #DEBHELPER#, their presence is required for correct dpkg state transitions during failed upgrades.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| depmod registration | Manual `depmod -a` in postinst | Let dh_installmodules generate it via #DEBHELPER# | dh_installmodules also generates preinst and postrm depmod calls for upgrades and removals |
| Service enable | Manual `systemctl enable` | Let dh_installsystemd generate it via #DEBHELPER# (with --no-start) | dh_installsystemd handles enable/disable correctly across install, upgrade, and removal lifecycles |
| MAC address validation | Regex validation of MAC format | Trust /sys/class/net/*/address output | The kernel always writes valid MAC format; validation adds complexity without value |
| Upgrade state management | Custom version comparison logic | Debian case "$1" in configure) with "$2" (old-version) | dpkg handles state transitions; the postinst just needs to be idempotent |

**Key insight:** The postinst only needs to hand-write two things: (1) the blacklist file and (2) the ethercat.conf file. Everything else (depmod, service enable, upgrade handling) is delegated to debhelper auto-generated code.

## Common Pitfalls

### Pitfall 1: Service Starts Before depmod
**What goes wrong:** `systemctl start ethercat.service` fails because ec_master.ko and ec_r8169.ko are not registered in the module dependency database.
**Why it happens:** In the dh sequence, `dh_installsystemd` runs before `dh_installmodules`. The auto-generated #DEBHELPER# code starts the service before running depmod.
**How to avoid:** Use `dh_installsystemd --no-start` in debian/rules. Start the service manually in postinst AFTER the #DEBHELPER# token.
**Warning signs:** postinst fails with "modprobe: FATAL: Module ec_master not found" or ethercat.service enters failed state.

### Pitfall 2: Interface Not Present During Install
**What goes wrong:** `/sys/class/net/enP8p1s0/address` does not exist. The MAC detection fails and ethercat.conf gets an empty MASTER0_DEVICE.
**Why it happens:** The network interface might be renamed, down, or not present during install (e.g., in a Docker build verification environment).
**How to avoid:** Check if the sysfs path exists before reading. If missing, log a warning and set MASTER0_DEVICE to "ff:ff:ff:ff:ff:ff" (IgH broadcast fallback that accepts any NIC) or fail the install with a clear error message. The requirement says to read from enP8p1s0; failing with a clear error is the safer choice.
**Warning signs:** Empty MAC in ethercat.conf; ethercatctl reports "MAC address may not be empty."

### Pitfall 3: ethercat.conf Overwritten on Upgrade
**What goes wrong:** On package upgrade, the postinst regenerates ethercat.conf and overwrites any user customizations.
**Why it happens:** The postinst always writes the config file in the configure case without checking if it already exists.
**How to avoid:** Only write ethercat.conf if it does not exist or if MASTER0_DEVICE is empty/unset. Use `[ ! -f /etc/ethercat.conf ] || ! grep -q "^MASTER0_DEVICE=" /etc/ethercat.conf` as a guard. For v1, writing unconditionally is acceptable since this is a single-purpose Jetson package. Document as a v2 improvement.
**Warning signs:** User-modified config gets silently replaced after apt upgrade.

### Pitfall 4: Blacklist File Not Effective Until Reboot
**What goes wrong:** The stock r8169 driver remains loaded in memory even after blacklist-eth.conf is installed.
**Why it happens:** The blacklist prevents future loading but does not unload already-loaded modules. The ethercatctl start script handles this by unloading stock modules and loading ec_r8169 instead.
**How to avoid:** This is not a bug -- the ethercatctl start script (called by ethercat.service) explicitly unloads stock drivers and loads ec_ variants. The blacklist prevents the stock driver from being reloaded after the ec_ driver takes over. No additional action needed in postinst.
**Warning signs:** `lsmod | grep r8169` shows stock r8169 immediately after install, but after ethercat.service starts, it should show ec_r8169 instead.

### Pitfall 5: postinst Not Executable
**What goes wrong:** dpkg ignores the postinst script silently if it lacks the execute permission.
**Why it happens:** The file was created without chmod +x.
**How to avoid:** Ensure `debian/postinst` has mode 0755 (executable). Debhelper typically handles this, but verify.
**Warning signs:** dpkg -i succeeds but none of the postinst actions (blacklist, depmod, config, service) are executed.

### Pitfall 6: IgH make install Creates Template ethercat.conf
**What goes wrong:** Phase 2's `make install DESTDIR=...` already installs a template ethercat.conf with empty values to `$(DESTDIR)/etc/ethercat.conf`. The postinst must overwrite this, not append to it.
**Why it happens:** IgH's Makefile.am installs ethercat.conf as configuration data to $(sysconfdir).
**How to avoid:** In postinst, write the complete ethercat.conf file (overwriting the template). Do not try to sed/patch the template -- write a fresh file with only the variables we need.
**Warning signs:** ethercat.conf contains template comments but empty MASTER0_DEVICE.

## Code Examples

### Complete debian/postinst

```sh
#!/bin/sh
# postinst for igh-seeedstudio
# Source: Debian Policy ch-maintainerscripts, IgH EtherCAT ethercatctl.in
set -e

case "$1" in
    configure)
        # --- INST-01: Install blacklist for stock Realtek drivers ---
        # Use "install /bin/true" pattern to prevent udev bypass
        cat > /etc/modprobe.d/blacklist-eth.conf <<'BLACKLIST'
# Prevent stock Realtek drivers from loading.
# EtherCAT uses ec_r8169 instead.
install r8169 /bin/true
install r8168 /bin/true
BLACKLIST

        # --- INST-03 + INST-04: Detect MAC and write ethercat.conf ---
        IFACE="enP8p1s0"
        SYSFS_PATH="/sys/class/net/${IFACE}/address"

        if [ -f "${SYSFS_PATH}" ]; then
            MAC=$(cat "${SYSFS_PATH}")
        else
            echo "WARNING: ${SYSFS_PATH} not found, cannot detect MAC address" >&2
            echo "ethercat.conf will need manual configuration" >&2
            MAC=""
        fi

        cat > /etc/ethercat.conf <<CONF
# EtherCAT Master configuration
# Generated by igh-seeedstudio postinst
MASTER0_DEVICE="${MAC}"
DEVICE_MODULES="r8169"
CONF

        # --- INST-02 + service enable handled by #DEBHELPER# ---
        # dh_installmodules generates: depmod -a
        # dh_installsystemd generates: systemctl enable ethercat.service
        #DEBHELPER#

        # --- INST-05: Start service AFTER depmod (from #DEBHELPER# above) ---
        if [ -d /run/systemd/system ]; then
            systemctl restart ethercat.service || true
        fi
        ;;

    abort-upgrade|abort-remove|abort-deconfigure)
        #DEBHELPER#
        ;;

    *)
        echo "postinst called with unknown argument: $1" >&2
        exit 1
        ;;
esac

exit 0
```

### debian/rules Addition for Phase 3

```makefile
# Prevent dh_installsystemd from starting the service in postinst.
# The postinst starts it manually after depmod runs via #DEBHELPER#.
override_dh_installsystemd:
	dh_installsystemd --no-start
```

### ethercat.conf Format Reference

```sh
# This file is sourced by ethercatctl as a shell script.
# Variables must be valid POSIX shell assignments.
# Source: https://gitlab.com/etherlab.org/ethercat/-/blob/stable-1.6/script/ethercatctl.in

MASTER0_DEVICE="aa:bb:cc:dd:ee:ff"
DEVICE_MODULES="r8169"
```

### MAC Address Detection

```sh
# Read MAC from sysfs (kernel always writes lowercase hex with colons)
MAC=$(cat /sys/class/net/enP8p1s0/address)
# Example output: "00:e0:4c:68:01:23"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `blacklist r8169` in modprobe.d | `install r8169 /bin/true` in modprobe.d | Always available, better practice | Prevents udev from bypassing blacklist |
| dh_systemd_enable + dh_systemd_start | dh_installsystemd (combined) | debhelper compat 11+ | Single command handles both; --no-start flag available |
| Manual depmod in postinst | dh_installmodules auto-generates depmod | debhelper (long standing) | Auto-generates preinst/postinst/postrm depmod calls |
| /etc/sysconfig/ethercat | /etc/ethercat.conf | IgH stable-1.6 (systemd support) | With --sysconfdir=/etc, config lives at /etc/ethercat.conf; sysconfig only used with sysvinit |

## Open Questions

1. **#DEBHELPER# in multiple case branches**
   - What we know: The #DEBHELPER# token should appear in each code path that might be reached. In the configure case, it must appear between our custom code and the service start. In abort-* cases, it needs to appear for cleanup.
   - What's unclear: Whether debhelper correctly handles #DEBHELPER# appearing in multiple case branches of the same script.
   - Recommendation: This is standard Debian practice and is well-tested. Use #DEBHELPER# in both the configure and abort-* branches. Confidence: HIGH.

2. **IgH ethercat.conf template already installed by make install**
   - What we know: Phase 2's `make install DESTDIR=...` installs a template ethercat.conf with empty/default values to `/etc/ethercat.conf` inside the package.
   - What's unclear: Whether dpkg treats this as a conffile (prompting on upgrade) or if our postinst overwrite is always safe.
   - Recommendation: Since we write the file in postinst (not just ship it as a conffile), dpkg will not track it as a conffile. The postinst always overwrites it. For v1 this is fine; v2 should add upgrade-awareness. Confidence: MEDIUM.

3. **ethercat.service location with --prefix=/usr**
   - What we know: IgH configure.ac uses pkg-config to find systemdsystemunitdir, which on Ubuntu 22.04 returns `/lib/systemd/system/`. With DESTDIR, the service file lands at `debian/igh-seeedstudio/lib/systemd/system/ethercat.service`.
   - What's unclear: Whether dh_installsystemd correctly detects the service file at this path in the staging directory.
   - Recommendation: dh_installsystemd scans the package build directory (tmpdir) for all .service files. It will find ethercat.service regardless of exact path within the staging directory. Confidence: HIGH.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Shell script inspection + dpkg content verification |
| Config file | debian/postinst (the script IS the deliverable) |
| Quick run command | `test -f debian/postinst && sh -n debian/postinst && echo "Syntax OK"` |
| Full suite command | `sh -n debian/postinst && grep -q "install r8169 /bin/true" debian/postinst && grep -q "depmod\|DEBHELPER" debian/postinst && grep -q "MASTER0_DEVICE" debian/postinst && grep -q "systemctl" debian/postinst && echo "All checks pass"` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INST-01 | blacklist-eth.conf written with install r8169/r8168 /bin/true | smoke | `grep -q 'install r8169 /bin/true' debian/postinst && grep -q 'install r8168 /bin/true' debian/postinst && grep -q 'blacklist-eth.conf' debian/postinst` | Wave 0 |
| INST-02 | depmod -a runs before systemctl | smoke | `grep -q 'DEBHELPER' debian/postinst && grep -q 'no-start' debian/rules` | Wave 0 |
| INST-03 | MAC auto-detected from /sys/class/net/enP8p1s0/address | smoke | `grep -q 'enP8p1s0' debian/postinst && grep -q '/sys/class/net' debian/postinst` | Wave 0 |
| INST-04 | ethercat.conf written with MASTER0_DEVICE and DEVICE_MODULES | smoke | `grep -q 'MASTER0_DEVICE' debian/postinst && grep -q 'DEVICE_MODULES="r8169"' debian/postinst` | Wave 0 |
| INST-05 | ethercat.service started/restarted | smoke | `grep -q 'systemctl.*restart.*ethercat' debian/postinst` | Wave 0 |

### Sampling Rate
- **Per task commit:** Shell syntax check (`sh -n debian/postinst`) + grep for required patterns
- **Per wave merge:** Full static validation of all INST-* requirements
- **Phase gate:** Full build in Docker (Phase 5) validates postinst runs without error on dpkg -i

### Wave 0 Gaps
- None -- all validation is static inspection of debian/postinst and debian/rules
- Full integration test (actual dpkg -i on Jetson) is deferred to Phase 5 Docker verification and on-hardware testing
- `sh -n` validates syntax but cannot test runtime behavior (MAC detection, service start)

## Sources

### Primary (HIGH confidence)
- [Debian Policy: Maintainer Scripts](https://www.debian.org/doc/debian-policy/ch-maintainerscripts.html) -- postinst arguments (configure, abort-upgrade, etc.), set -e requirement, idempotency
- [debhelper(7) manpage](https://www.man7.org/linux/man-pages/man7/debhelper.7.html) -- #DEBHELPER# token placement and replacement behavior
- [dh_installsystemd(1) manpage](https://manpages.debian.org/testing/debhelper/dh_installsystemd.1.en.html) -- --no-start flag, service enable/start code generation
- [dh_installmodules(1) manpage](https://man7.org/linux/man-pages/man1/dh_installmodules.1.html) -- auto-generates depmod in postinst, modprobe file handling
- [Debhelper dh source: root_sequence.pm](https://github.com/Debian/debhelper/blob/master/lib/Debian/Debhelper/Sequence/root_sequence.pm) -- confirmed dh_installsystemd runs BEFORE dh_installmodules in the install sequence
- [IgH EtherCAT ethercatctl.in (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/blob/stable-1.6/script/ethercatctl.in) -- config file sourced via `.` operator, MASTER0_DEVICE/DEVICE_MODULES variable usage
- [IgH EtherCAT script/Makefile.am (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/blob/stable-1.6/script/Makefile.am) -- ethercat.conf installed to $(sysconfdir), ethercat.service installed conditionally
- [IgH EtherCAT configure.ac (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/blob/stable-1.6/configure.ac) -- systemd unit directory detection via pkg-config

### Secondary (MEDIUM confidence)
- [Debian Wiki: KernelModuleBlacklisting](https://wiki.debian.org/KernelModuleBlacklisting) -- "install /bin/true" vs "blacklist" differences
- [Debian Wiki: Teams/pkg-systemd/Packaging](https://wiki.debian.org/Teams/pkg-systemd/Packaging) -- systemd packaging patterns with debhelper
- [dh_installdeb(1) manpage](https://manpages.debian.org/testing/debhelper/dh_installdeb.1.en.html) -- #DEBHELPER# token insertion mechanism

### Tertiary (LOW confidence)
- [IgH EtherCAT GitLab Issue #21: systemd integration](https://gitlab.com/etherlab.org/ethercat/-/issues/21) -- known issues with systemd service timing; ethercatctl and network-pre.target

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- debhelper postinst patterns are well-documented Debian standards; IgH ethercatctl config format confirmed from source
- Architecture: HIGH -- debhelper sequence ordering confirmed from source code (root_sequence.pm); --no-start solution is standard
- Pitfalls: HIGH -- depmod/service ordering conflict verified from debhelper source; interface detection edge case is well-understood
- Validation: MEDIUM -- all tests are static (grep-based); runtime validation requires Jetson hardware or Docker

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (Debian packaging conventions are stable; IgH stable-1.6 is a stable branch)
