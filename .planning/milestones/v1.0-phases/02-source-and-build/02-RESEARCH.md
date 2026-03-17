# Phase 2: Source and Build - Research

**Researched:** 2026-03-17
**Domain:** IgH EtherCAT source fetch, autotools configure, and kernel module compilation within debian/rules
**Confidence:** HIGH

## Summary

Phase 2 wires up the actual IgH EtherCAT source fetch and compilation pipeline inside the `debian/rules` file created in Phase 1. The key tasks are: (1) fetching the IgH EtherCAT source from the official GitLab stable-1.6 branch during build, (2) running the autotools bootstrap and configure with correct flags, (3) building both userspace tools and kernel modules, and (4) installing everything into the correct package staging directory so that `dpkg-deb` produces a well-formed `.deb`.

The most important discovery is that the IgH EtherCAT stable-1.6 branch **does** support the r8169 driver for kernel 5.15 via the `devices/r8169/` subdirectory. The available kernel-versioned r8169 driver files include 5.10, 5.14, **5.15**, 6.1, 6.4, and 6.12. The configure script auto-detects the kernel major.minor version (extracting "5.15" from "5.15.148-tegra") and matches it against available source files, so `--with-r8169-kernel` does NOT need to be explicitly specified.

A second critical finding is that the IgH EtherCAT `configure.ac` defaults `INSTALL_MOD_DIR` to `ethercat` (not `extra`). This means modules install under `/lib/modules/<version>/ethercat/` by default. The roadmap success criterion says "under /lib/modules/5.15.148-tegra/extra/" -- this requires passing `--with-module-dir=extra` to configure, or the planner should update the success criterion to match the IgH default of `ethercat/`. Using `--with-module-dir=extra` is the simpler fix.

**Primary recommendation:** Use `override_dh_update_autotools_config` to fetch the IgH source (git clone), `override_dh_auto_configure` for bootstrap + configure, and `override_dh_auto_install` for both `make install` and `make modules_install` with DESTDIR/INSTALL_MOD_PATH. Add `git` to `Build-Depends`. Assert `ec_r8169.ko` exists after build.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None -- all implementation choices are at Claude's discretion (pure infrastructure phase).

### Claude's Discretion
All implementation choices are at Claude's discretion -- pure infrastructure phase.

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SRC-01 | Package fetches IgH EtherCAT 1.6 source from official GitLab repo (stable-1.6) | Standard Stack section documents the git clone command; Architecture Patterns section shows override_dh_update_autotools_config hook for source fetch |
| SRC-02 | Package installs build-essential and automake as build dependencies | Standard Stack section lists all Build-Depends; debian/control already declares these from Phase 1 but needs `git` added |
| SRC-03 | Configure runs with --enable-r8169 --with-linux-dir pointing to Tegra 5.15.148 kernel headers | Architecture Patterns section documents exact configure invocation with all flags; Code Examples section provides the complete debian/rules override |
| SRC-04 | make and make modules produce ec_master and ec_r8169 kernel modules | Architecture Patterns section documents the build and verification assertion; Don't Hand-Roll section covers the module install path |
</phase_requirements>

## Standard Stack

### Core

| Tool/File | Version/Value | Purpose | Why Standard |
|-----------|---------------|---------|--------------|
| IgH EtherCAT Master | stable-1.6 branch | EtherCAT kernel modules + userspace tools | Official production branch; supports r8169 on kernel 5.15 |
| git | any (Build-Depends) | Clone IgH source during build | Required to fetch source from GitLab; must be in Build-Depends |
| autoconf | >= 2.60 (Ubuntu 22.04 ships 2.71) | Run autoreconf via bootstrap script | Required by IgH's `./bootstrap` script |
| automake | >= 1.9 (Ubuntu 22.04 ships 1.16) | Generate Makefiles from Makefile.am | Required by IgH's build system |
| libtool | any recent | Shared library portability | Required by IgH's configure.ac |
| pkg-config | any recent | Build system dependency detection | Used by configure.ac for library detection |
| nvidia-l4t-kernel-headers | matching 5.15.148-tegra | Kernel headers for .ko compilation | Must match target kernel exactly for vermagic |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| fakeroot | Build .deb as non-root | Required by dpkg-buildpackage |
| debhelper (compat 13) | Build system orchestration | Already declared from Phase 1 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| git clone during build | Vendor tarball in repo | Vendoring is simpler and more reproducible, but increases repo size (~15MB); git clone keeps repo clean and always builds from upstream; PROJECT.md specifies fetch during build |
| `--with-module-dir=extra` | Default `ethercat` directory | Roadmap says "extra/"; IgH defaults to "ethercat/"; use `--with-module-dir=extra` to match success criterion |
| `override_dh_update_autotools_config` for fetch | `override_dh_auto_clean` for fetch | dh_update_autotools_config runs before autoreconf/configure, making it the correct hook point; interacts better with pbuilder/sbuild |

**Updated Build-Depends line for debian/control:**
```
Build-Depends: debhelper-compat (= 13),
               build-essential,
               autoconf,
               automake,
               libtool,
               pkg-config,
               git,
               nvidia-l4t-kernel-headers
```

Note: `git` is the key addition for Phase 2.

## Architecture Patterns

### Recommended debian/rules Structure

The `debian/rules` file needs four override targets:

```
debian/rules (Phase 2 scope)
  override_dh_update_autotools_config  # Fetch IgH source via git clone
  override_dh_auto_configure           # bootstrap + ./configure
  override_dh_auto_build               # make all modules + assertion
  override_dh_auto_install             # make install + make modules_install with DESTDIR
```

### Pattern 1: Source Fetch via override_dh_update_autotools_config

**What:** Hijack the `dh_update_autotools_config` hook to clone the IgH EtherCAT source before configure runs. This hook runs early in the dh sequence -- before `dh_autoreconf` and `dh_auto_configure`.

**When to use:** When upstream source must be fetched during build (not vendored in the repo).

**Why this hook:** The dh binary build sequence runs in this order:
1. `dh_update_autotools_config` -- our fetch hook
2. `dh_autoreconf` -- runs autoreconf (we skip this, run bootstrap manually)
3. `dh_auto_configure` -- our configure hook
4. `dh_auto_build` -- our build hook
5. `dh_auto_test` -- skipped (no tests for kernel modules)
6. `dh_auto_install` -- our install hook
7. ... (dh_fixperms, dh_shlibdeps, dh_gencontrol, etc.)

**Example:**
```makefile
# Source: https://vincent.bernat.ch/en/blog/2019-pragmatic-debian-packaging
override_dh_update_autotools_config:
	git clone --depth 1 --branch stable-1.6 \
	    https://gitlab.com/etherlab.org/ethercat.git ethercat-src
```

### Pattern 2: Bootstrap + Configure via override_dh_auto_configure

**What:** Run the IgH `bootstrap` script (which calls `autoreconf -i`) followed by `./configure` with all required flags.

**When to use:** Always for IgH EtherCAT builds.

**Critical flags:**
- `--prefix=/usr` -- ensures ethercatctl reads /etc/ethercat.conf (not /usr/local/etc/)
- `--sysconfdir=/etc` -- places ethercat.conf at /etc/ethercat.conf
- `--with-linux-dir=/usr/src/linux-headers-5.15.148-tegra` -- Tegra kernel headers path
- `--enable-r8169` -- builds the EtherCAT-native r8169 driver (ec_r8169.ko)
- `--with-module-dir=extra` -- installs modules under /lib/modules/<ver>/extra/ instead of default /lib/modules/<ver>/ethercat/
- `--disable-8139too` -- exclude unneeded driver
- `--disable-e1000` -- exclude unneeded driver
- `--disable-e1000e` -- exclude unneeded driver
- `--enable-generic` -- builds ec_generic.ko as a fallback driver

**What NOT to specify:**
- `--with-r8169-kernel` -- auto-detected from kernel headers (extracts "5.15" from "5.15.148-tegra"); manual specification is unnecessary and error-prone

**Example:**
```makefile
KDIR := /usr/src/linux-headers-5.15.148-tegra

override_dh_auto_configure:
	cd ethercat-src && ./bootstrap
	cd ethercat-src && ./configure \
	    --prefix=/usr \
	    --sysconfdir=/etc \
	    --with-linux-dir=$(KDIR) \
	    --with-module-dir=extra \
	    --enable-r8169 \
	    --enable-generic \
	    --disable-8139too \
	    --disable-e1000 \
	    --disable-e1000e
```

### Pattern 3: Build + Assert via override_dh_auto_build

**What:** Run `make all modules` then assert that `ec_r8169.ko` was actually produced. The assertion is critical because IgH's configure silently disables r8169 if kernel headers lack expected symbols.

**When to use:** Always.

**Example:**
```makefile
override_dh_auto_build:
	$(MAKE) -C ethercat-src all modules
	@# Assert ec_r8169.ko was built (configure silently drops it otherwise)
	test -f ethercat-src/devices/r8169/ec_r8169.ko || \
	    (echo "ERROR: ec_r8169.ko was not built -- check configure output"; exit 1)
```

**Key detail:** The r8169 module for kernel 5.15 is built in the `devices/r8169/` subdirectory (not `devices/` root). The file to check is `ethercat-src/devices/r8169/ec_r8169.ko`. For older kernel versions (3.x-4.x), it would be `ethercat-src/devices/ec_r8169.ko`.

### Pattern 4: Install via override_dh_auto_install

**What:** Run both `make install` (userspace tools, libraries, service files) and `make modules_install` (kernel modules) with the correct DESTDIR/INSTALL_MOD_PATH pointing to the package staging directory.

**When to use:** Always.

**Example:**
```makefile
PKGDIR := $(CURDIR)/debian/igh-seeedstudio

override_dh_auto_install:
	$(MAKE) -C ethercat-src DESTDIR=$(PKGDIR) install
	$(MAKE) -C ethercat-src INSTALL_MOD_PATH=$(PKGDIR) modules_install
```

**Critical distinction:**
- `DESTDIR=$(PKGDIR)` -- for `make install` (userspace: ethercat CLI, libethercat.so, ethercat.service, ethercat.conf template)
- `INSTALL_MOD_PATH=$(PKGDIR)` -- for `make modules_install` (kernel modules: ec_master.ko, ec_r8169.ko into lib/modules/)

### Pattern 5: Clean via override_dh_auto_clean

**What:** Clean the cloned source directory to support rebuilds.

**Example:**
```makefile
override_dh_auto_clean:
	rm -rf ethercat-src
```

### Anti-Patterns to Avoid

- **Fetching source in override_dh_auto_configure:** Mixing fetch and configure in one target is fragile. Use `override_dh_update_autotools_config` for fetch so that failures are isolated and the dh sequence is respected.

- **Running `./bootstrap` and `./configure` separately in different override targets:** The bootstrap must run before configure but both operate on the same source tree. Combining them in `override_dh_auto_configure` keeps them together logically.

- **Using `DESTDIR` for `make modules_install`:** IgH EtherCAT's modules_install target uses `INSTALL_MOD_PATH`, not `DESTDIR`. Using `DESTDIR` for modules_install may install to the wrong location or fail silently.

- **Omitting the ec_r8169.ko assertion:** IgH's configure silently disables r8169 if it cannot detect compatible kernel headers. Without an explicit assertion, the build succeeds but produces a package without the r8169 driver -- a silent, critical failure.

- **Specifying `--with-r8169-kernel=5.15.148`:** The configure script extracts major.minor only ("5.15") from the kernel headers. Passing the full version string will fail to match any available driver files. Let it auto-detect.

- **Not adding `git` to Build-Depends:** The build will fail in clean environments (pbuilder, sbuild) where git is not installed by default.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Source fetch | wget + tar for tarball | `git clone --depth 1 --branch stable-1.6` | IgH publishes on GitLab with git; stable-1.6 is a branch not a release tarball |
| Autotools bootstrap | Manual autoreconf commands | IgH's `./bootstrap` script | Bootstrap script handles m4 directory creation and ChangeLog touch that autoreconf alone misses |
| Module install path | Manual cp of .ko files | `make modules_install INSTALL_MOD_PATH=...` | The kernel build system handles module compression, depmod metadata, and directory structure correctly |
| Kernel version extraction | grep/sed on uname -r | Let configure auto-detect via --with-linux-dir | Configure reads kernel.release from the headers directory and extracts the correct major.minor version |
| debhelper install orchestration | Manual dpkg-deb commands | `dh $@` with override targets | debhelper handles permissions, shlibs, control substitutions, md5sums, and 100+ edge cases |

**Key insight:** The IgH EtherCAT build system is standard autotools. The debian/rules file should delegate to it, not re-implement it. The only custom logic needed is: (1) fetch source, (2) pass correct configure flags, (3) assert ec_r8169.ko was built.

## Common Pitfalls

### Pitfall 1: ec_r8169.ko Silently Not Built
**What goes wrong:** `./configure --enable-r8169` succeeds but the r8169 driver is silently disabled because kernel headers lack expected symbols or structures. The build completes successfully with only ec_master.ko and ec_generic.ko.
**Why it happens:** IgH's configure.ac performs feature detection for native drivers. If detection fails, the driver is disabled without error.
**How to avoid:** After `make`, assert that the r8169 module exists: `test -f devices/r8169/ec_r8169.ko`. Fail the build if absent. This is documented in STATE.md as a locked decision.
**Warning signs:** Build succeeds but `find . -name "ec_r8169.ko"` returns nothing.

### Pitfall 2: Module Install Path Mismatch (ethercat/ vs extra/)
**What goes wrong:** Modules install under `/lib/modules/<ver>/ethercat/` but the package expects them under `/lib/modules/<ver>/extra/`.
**Why it happens:** IgH's configure defaults `INSTALL_MOD_DIR` to `ethercat`. The roadmap success criterion specifies `extra/`.
**How to avoid:** Pass `--with-module-dir=extra` to configure.
**Warning signs:** `.deb` contains modules in unexpected path; `modprobe ec_master` fails because depmod indexed the wrong directory.

### Pitfall 3: Wrong DESTDIR Variable for modules_install
**What goes wrong:** `make modules_install DESTDIR=...` installs modules to the system's actual `/lib/modules/` rather than the package staging directory.
**Why it happens:** IgH's Makefile.kbuild passes `INSTALL_MOD_PATH` (not `DESTDIR`) to the kernel build system's modules_install target. DESTDIR is for userspace install only.
**How to avoid:** Use `INSTALL_MOD_PATH=$(PKGDIR)` for `make modules_install` and `DESTDIR=$(PKGDIR)` for `make install`.
**Warning signs:** Package is missing .ko files; `dpkg -c *.deb` shows no modules.

### Pitfall 4: Missing `git` in Build-Depends
**What goes wrong:** Build fails in clean environments (pbuilder, sbuild, Docker) because git is not installed.
**Why it happens:** Git is commonly pre-installed on developer machines but not in minimal build containers.
**How to avoid:** Add `git` to `Build-Depends` in `debian/control`.
**Warning signs:** `git: command not found` during dpkg-buildpackage.

### Pitfall 5: ethercat.conf Path Determined by --prefix
**What goes wrong:** The `ethercatctl` script has the config file path baked in at compile time. With `--prefix=/usr/local` (the autotools default), it reads `/usr/local/etc/ethercat.conf` instead of `/etc/ethercat.conf`.
**Why it happens:** IgH bakes `$PREFIX/etc/ethercat.conf` into the ethercatctl script during configure.
**How to avoid:** Use `--prefix=/usr` (locked decision from STATE.md) and `--sysconfdir=/etc`.
**Warning signs:** Service fails with "MAC address may not be empty" despite /etc/ethercat.conf being correct.

### Pitfall 6: Kernel Version Auto-Detection Fails
**What goes wrong:** Configure cannot determine the kernel version from the headers, or determines a wrong version that doesn't match any r8169 driver files.
**Why it happens:** The Tegra kernel headers path or internal version file format differs from what configure expects. Configure reads `include/config/kernel.release` inside the headers directory.
**How to avoid:** Verify the kernel headers package installs to the expected path (`/usr/src/linux-headers-5.15.148-tegra/`) and that `include/config/kernel.release` inside it contains the full version string. If auto-detection fails, override with `--with-r8169-kernel=5.15`.
**Warning signs:** Configure output shows "checking for r8169 kernel... not found" or similar.

### Pitfall 7: dh_shlibdeps Fails on .ko Files
**What goes wrong:** `dh_shlibdeps` tries to analyze kernel module files and fails because they are not standard ELF shared libraries.
**Why it happens:** debhelper scans all files in the package for shared library dependencies.
**How to avoid:** If this occurs, add `override_dh_shlibdeps: dh_shlibdeps -X.ko` to exclude kernel modules. Note: this may not be needed with debhelper 13 which is smarter about .ko files, but include the override as a safety measure.
**Warning signs:** `dpkg-shlibdeps: error: ...ec_master.ko: file format not recognized`

## Code Examples

### Complete debian/rules (Phase 2)

```makefile
#!/usr/bin/make -f
# Source: IgH EtherCAT 1.6 Debian packaging
export DH_VERBOSE = 1

KDIR   := /usr/src/linux-headers-5.15.148-tegra
SRCDIR := ethercat-src
PKGDIR := $(CURDIR)/debian/igh-seeedstudio

%:
	dh $@

# Fetch IgH EtherCAT source from official GitLab
override_dh_update_autotools_config:
	git clone --depth 1 --branch stable-1.6 \
	    https://gitlab.com/etherlab.org/ethercat.git $(SRCDIR)

# Bootstrap autotools and configure
override_dh_auto_configure:
	cd $(SRCDIR) && ./bootstrap
	cd $(SRCDIR) && ./configure \
	    --prefix=/usr \
	    --sysconfdir=/etc \
	    --with-linux-dir=$(KDIR) \
	    --with-module-dir=extra \
	    --enable-r8169 \
	    --enable-generic \
	    --disable-8139too \
	    --disable-e1000 \
	    --disable-e1000e

# Build userspace + kernel modules, then assert ec_r8169.ko exists
override_dh_auto_build:
	$(MAKE) -C $(SRCDIR) all modules
	@# Fail loudly if r8169 was silently dropped by configure
	test -f $(SRCDIR)/devices/r8169/ec_r8169.ko || \
	    (echo "ERROR: ec_r8169.ko was not built"; exit 1)

# Install userspace tools + kernel modules into package staging
override_dh_auto_install:
	$(MAKE) -C $(SRCDIR) DESTDIR=$(PKGDIR) install
	$(MAKE) -C $(SRCDIR) INSTALL_MOD_PATH=$(PKGDIR) modules_install

# Clean cloned source
override_dh_auto_clean:
	rm -rf $(SRCDIR)

# Skip autoreconf -- we run bootstrap manually
override_dh_autoreconf:
	@true

# Exclude .ko from shlibdeps analysis (safety measure)
override_dh_shlibdeps:
	dh_shlibdeps -X.ko
```

### Updated debian/control (additions for Phase 2)

```
Build-Depends: debhelper-compat (= 13),
               build-essential,
               autoconf,
               automake,
               libtool,
               pkg-config,
               git,
               nvidia-l4t-kernel-headers
```

**Changes from Phase 1:**
- Added `git` (required for source fetch)
- Added `pkg-config` (required by configure.ac)

### IgH Bootstrap Script Internals

The `./bootstrap` script does three things:
1. `touch ChangeLog` -- creates empty ChangeLog
2. `mkdir -p m4` -- creates m4 directory for older aclocal
3. `autoreconf -i` -- generates configure and Makefiles

It runs with `set -e` (fail on error) and `set -x` (verbose).

### Verifying the Built Package Contents

```bash
# After dpkg-buildpackage completes, verify the .deb contents
dpkg -c igh-seeedstudio_1.6.0_arm64.deb | grep -E "ec_master|ec_r8169"
# Expected output should show:
#   ./lib/modules/5.15.148-tegra/extra/ec_master.ko
#   ./lib/modules/5.15.148-tegra/extra/ec_r8169.ko
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single-file r8169 driver (devices/r8169-3.2-ethercat.c) | Multi-file r8169 driver in subdirectory (devices/r8169/) | IgH stable-1.6 (recent updates) | Kernel 5.10+ uses subdirectory layout with r8169_main, r8169_firmware, r8169_phy_config files |
| `--with-r8169-kernel` required | Auto-detection from kernel headers | Always worked but documentation was unclear | Configure extracts major.minor from kernel.release; manual specification only needed if auto-detection fails |
| `debian/compat` file | `debhelper-compat (= 13)` in Build-Depends | debhelper 12+ | Already applied in Phase 1 |
| `override_dh_auto_clean` for source fetch | `override_dh_update_autotools_config` | Best practice from pragmatic packaging guides | Better interaction with pbuilder/sbuild; runs at correct point in dh sequence |

**Important version note:** The IgH EtherCAT stable-1.6 branch r8169 subdirectory supports:
- 5.10 (verified)
- 5.14 (verified)
- **5.15** (verified -- matches our target kernel)
- 6.1 (verified)
- 6.4 (verified)
- 6.12 (verified)

## Open Questions

1. **Exact kernel headers path on NVIDIA Jetson**
   - What we know: The package is `nvidia-l4t-kernel-headers` and convention is `/usr/src/linux-headers-5.15.148-tegra/`
   - What's unclear: Whether the actual path includes additional suffixes (e.g., `-ubuntu22.04_aarch64`). One NVIDIA forum post suggests a longer path variant.
   - Recommendation: Use `/usr/src/linux-headers-5.15.148-tegra` as the default. If it fails, check `dpkg -L nvidia-l4t-kernel-headers` inside the build container to discover the actual path. Consider making KDIR dynamic: `KDIR := $(shell dpkg -L nvidia-l4t-kernel-headers | grep '/usr/src/linux-headers' | head -1)`

2. **Whether dh_autoreconf needs explicit skip**
   - What we know: `dh_autoreconf` runs automatically in the dh sequence and calls `autoreconf -fi` in the source tree root. Since our source is in a subdirectory (`ethercat-src/`), it would run in the wrong directory and potentially interfere.
   - What's unclear: Whether dh_autoreconf is smart enough to detect no configure.ac in the project root and skip itself.
   - Recommendation: Override with `override_dh_autoreconf: @true` to be safe.

3. **Network access during dpkg-buildpackage**
   - What we know: The git clone requires network access. In standard Debian build environments (pbuilder, sbuild), network is sometimes disabled.
   - What's unclear: Whether the Docker-based build environment (Phase 5) and GitHub Actions CI (Phase 6) will have network access during the build step.
   - Recommendation: Both Docker builds and GitHub Actions have network access by default. This is only an issue for strict Debian policy compliance, which is not a concern for this internal packaging project.

4. **ec_r8169.ko path in the source tree**
   - What we know: For kernel 5.15, the r8169 driver builds in `devices/r8169/` subdirectory, so the built module should be at `devices/r8169/ec_r8169.ko`.
   - What's unclear: Whether `make modules_install` flattens this hierarchy into `lib/modules/<ver>/extra/` or preserves subdirectory structure (e.g., `lib/modules/<ver>/extra/r8169/ec_r8169.ko`).
   - Recommendation: After the first build attempt, inspect the installed tree with `find $(PKGDIR)/lib -name "*.ko"` to verify exact paths. Adjust assertions accordingly.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | dpkg-buildpackage + dpkg content inspection |
| Config file | debian/rules (the build system IS the test) |
| Quick run command | `dpkg-buildpackage -us -uc -b 2>&1; echo "Exit: $?"` |
| Full suite command | `dpkg-buildpackage -us -uc -b && dpkg -c *.deb \| grep ec_r8169` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SRC-01 | IgH EtherCAT source fetched from GitLab stable-1.6 | smoke | `grep -q "git clone.*stable-1.6.*etherlab" debian/rules` | Wave 0 |
| SRC-02 | build-essential and automake in Build-Depends | unit | `grep -q "build-essential" debian/control && grep -q "automake" debian/control && grep -q "git" debian/control` | Wave 0 |
| SRC-03 | Configure runs with --enable-r8169 --with-linux-dir | smoke | `grep -q "enable-r8169" debian/rules && grep -q "with-linux-dir" debian/rules && grep -q "prefix=/usr" debian/rules && grep -q "sysconfdir=/etc" debian/rules` | Wave 0 |
| SRC-04 | make produces ec_master.ko and ec_r8169.ko | integration | `dpkg-buildpackage -us -uc -b && dpkg -c *.deb \| grep -q ec_master.ko && dpkg -c *.deb \| grep -q ec_r8169.ko` | Cannot run locally (requires arm64 + Tegra headers) |

### Sampling Rate
- **Per task commit:** Static checks on debian/rules and debian/control (grep for required flags and dependencies)
- **Per wave merge:** Full static validation suite
- **Phase gate:** Full build in Docker (Phase 5) or on arm64 hardware

### Wave 0 Gaps
- No test infrastructure needed beyond `dpkg-dev` tools and `grep`
- Full integration test (actual build producing .ko files) requires arm64 environment with Tegra headers -- deferred to Phase 5 Docker verification
- Local macOS development can only validate debian/rules syntax, not actual compilation

## Sources

### Primary (HIGH confidence)
- [IgH EtherCAT configure.ac (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/raw/stable-1.6/configure.ac) -- r8169 kernel version auto-detection logic, INSTALL_MOD_DIR default, --with-module-dir option
- [IgH EtherCAT INSTALL.md (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/blob/stable-1.6/INSTALL.md) -- bootstrap command (`./bootstrap`), configure flags, `make all modules`, `make modules_install install`
- [IgH EtherCAT devices/r8169/Makefile.am (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/raw/stable-1.6/devices/r8169/Makefile.am) -- confirmed r8169 support for kernel 5.10, 5.14, 5.15, 6.1, 6.4, 6.12
- [IgH EtherCAT devices/r8169/Kbuild.in (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/raw/stable-1.6/devices/r8169/Kbuild.in) -- ec_r8169.ko build from r8169_main + r8169_firmware + r8169_phy_config
- [IgH EtherCAT bootstrap script (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/raw/stable-1.6/bootstrap) -- touch ChangeLog, mkdir m4, autoreconf -i
- [Pragmatic Debian Packaging (Vincent Bernat)](https://vincent.bernat.ch/en/blog/2019-pragmatic-debian-packaging) -- override_dh_update_autotools_config for source fetch pattern, DESTDIR pattern
- [dh_shlibdeps manpage](https://manpages.debian.org/testing/debhelper/dh_shlibdeps.1.en.html) -- -X option to exclude .ko files

### Secondary (MEDIUM confidence)
- [sittner/ec-debianize](https://github.com/sittner/ec-debianize) -- Reference debian/ directory for IgH EtherCAT packaging; uses separate get_source.sh for fetch
- [IgH EtherCAT devices/Makefile.am (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/raw/stable-1.6/devices/Makefile.am) -- SUBDIRS includes r8169/, EXTRA_DIST lists older kernel version files
- [IgH EtherCAT devices/Kbuild.in (stable-1.6)](https://gitlab.com/etherlab.org/ethercat/-/raw/stable-1.6/devices/Kbuild.in) -- R8169_IN_SUBDIR conditional for subdirectory vs root-level build
- [LinuxCNC EtherCAT build instructions](https://forum.linuxcnc.org/ethercat/49771-ethercat-build-from-source-full-instructions) -- community-verified build steps
- [NVIDIA Developer Forum: EtherCAT on Jetson](https://forums.developer.nvidia.com/t/jetson-nano-install-preempt-rt-successfull-and-build-ethercat-igh-module-problem/232271) -- kernel header path format

### Tertiary (LOW confidence)
- [Vectioneer etherlab fork r8169-5.14-ethercat.h](https://git.vectioneer.com/pub/etherlab/-/blob/original/stable-1.6/devices/r8169/r8169-5.14-ethercat.h) -- corroborates r8169 subdirectory structure in stable-1.6
- r8169 on kernel 5.15.148-tegra compatibility -- no direct community reports found for this exact kernel; compatibility is inferred from the kernel major.minor match (5.15). The build assertion will surface any actual incompatibility.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- IgH EtherCAT build process is well-documented; confirmed r8169 support for kernel 5.15 in stable-1.6
- Architecture: HIGH -- debian/rules override patterns are standard debhelper practice; verified against official docs
- Pitfalls: HIGH -- INSTALL_MOD_DIR default, r8169 silent failure, DESTDIR vs INSTALL_MOD_PATH all verified from configure.ac and Makefile.kbuild
- Validation: MEDIUM -- full integration test requires arm64 hardware; static checks are high confidence

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (IgH stable-1.6 is a stable branch; Debian packaging conventions change slowly)
