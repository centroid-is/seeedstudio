# Phase 1: Debian Scaffold - Research

**Researched:** 2026-03-17
**Domain:** Debian packaging metadata files (debian/ directory scaffold)
**Confidence:** HIGH

## Summary

Phase 1 creates the `debian/` directory at the project root with all required Debian packaging metadata files: `control`, `rules`, `changelog`, `copyright`, and `compat` (or its modern equivalent). The scope is narrow and well-understood -- this is pure infrastructure with no build logic, no lifecycle scripts, and no IgH EtherCAT source code. The files must be syntactically valid and declare the correct package name (`igh-seeedstudio`), version (`1.6.0`), architecture (`arm64`), and build dependencies.

The key finding is that `debian/compat` is no longer needed when using `debhelper-compat (= 13)` in `Build-Depends`. The modern approach declares the compat level via the `debhelper-compat` virtual package dependency, making a separate `compat` file unnecessary and redundant. However, the roadmap explicitly lists "compat" as a required file. The resolution: either create the file with the value `13` for backward compatibility (debhelper 13 still supports this), or omit it and rely on the `Build-Depends` declaration. The recommended approach is to use `Build-Depends: debhelper-compat (= 13)` and omit the `debian/compat` file -- this is the current standard. If the success criteria strictly require a compat file, create it containing just `13`.

Validation of the scaffold uses `dpkg-parsechangelog` (validates changelog syntax), `dpkg-checkbuilddeps` (validates control file Build-Depends syntax), and a `debian/source/format` file declaring `3.0 (native)`. The success criterion "dpkg-buildpackage --no-check-builddeps parses without errors" will be satisfied if all files are syntactically valid and `debian/rules` exists as an executable Makefile. Note: `dpkg-buildpackage -d` will attempt to call `debian/rules clean` -- the standard `dh $@` pattern handles this gracefully even without source code present.

**Primary recommendation:** Create 5-6 files in `debian/` following current Debian packaging standards (debhelper-compat 13, DEP-5 copyright, 3.0 native format), validate with `dpkg-parsechangelog` and `dpkg-buildpackage -d`.

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
| DEB-01 | debian/ directory with control, rules, changelog, copyright, and maintainer scripts | Standard Stack section covers exact file format for each; Architecture Patterns section provides templates |
| DEB-02 | Package builds as `igh-seeedstudio_1.6.0_arm64.deb` | Control file `Source:` and `Package:` fields, changelog version entry, Architecture field -- all documented in Standard Stack |
| DEB-03 | Package declares Architecture: arm64 | Explicit field in debian/control binary package stanza -- documented in Code Examples |
</phase_requirements>

## Standard Stack

### Core

| File | Format | Purpose | Why Standard |
|------|--------|---------|--------------|
| debian/control | RFC 822-style key-value paragraphs | Package metadata, architecture, build-deps, runtime deps | Required by dpkg; two stanzas: Source (build-time) and Package (binary) |
| debian/rules | GNU Makefile with `dh $@` | Build instructions; debhelper dispatches to standard targets | Required by dpkg-buildpackage; `dh $@` is the modern minimal pattern |
| debian/changelog | dpkg changelog format | Package version, distribution, maintainer, date | Required by dpkg; version in filename comes from here; parsed by dpkg-parsechangelog |
| debian/copyright | DEP-5 machine-readable format | License and copyright declaration | Required by Debian policy; IgH EtherCAT is GPL-2.0 (kernel) + LGPL-2.1 (userspace library) |
| debian/source/format | Single-line text file | Declares source package format | `3.0 (native)` -- simplest for single-repo packages without separate upstream tarball |

### Supporting

| File | Format | Purpose | When to Use |
|------|--------|---------|-------------|
| debian/compat | Single integer | Legacy debhelper compat level | NOT needed when using `debhelper-compat (= 13)` in Build-Depends; include only if success criteria explicitly require it |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `3.0 (native)` source format | `3.0 (quilt)` | Quilt requires a separate upstream tarball (.orig.tar.gz); native is simpler for a single-repo project where debian/ and source live together |
| `debhelper-compat (= 13)` in Build-Depends | `debian/compat` file with `13` | Both work; Build-Depends method is modern standard, compat file is legacy but still supported |
| DEP-5 machine-readable copyright | Free-form text copyright | DEP-5 is machine-parseable and preferred by lintian; free-form is valid but generates lintian warnings |

**No installation needed for Phase 1.** These are static text files. Validation requires `dpkg-dev` (provides `dpkg-parsechangelog`, `dpkg-buildpackage`, `dpkg-checkbuilddeps`) which is available on any Debian/Ubuntu system or macOS with dpkg installed.

## Architecture Patterns

### Recommended Project Structure (Phase 1 scope)

```
debian/
  control              # Package metadata + build-deps (2 stanzas)
  rules                # Makefile: dh $@ with override stubs
  changelog            # Version 1.6.0, distribution unstable
  copyright            # DEP-5 format, GPL-2.0 + LGPL-2.1
  source/
    format             # "3.0 (native)"
```

### Pattern 1: Minimal debian/control with Two Stanzas

**What:** The control file has exactly two stanzas separated by a blank line. The first (Source) declares build-time metadata. The second (Package) declares the binary package.

**When to use:** Always -- this is the required format for all Debian source packages.

**Key fields for this project:**

Source stanza:
- `Source: igh-seeedstudio` -- must match the package name convention
- `Section: kernel` -- appropriate for kernel module packages
- `Priority: optional` -- standard for non-essential packages (`extra` is deprecated since Debian Policy 4.0.1)
- `Maintainer:` -- must be a valid `Name <email>` pair
- `Build-Depends:` -- the critical field; must list `debhelper-compat (= 13)`, `build-essential`, `autoconf`, `automake`, and `nvidia-l4t-kernel-headers`

Package stanza:
- `Package: igh-seeedstudio` -- binary package name
- `Architecture: arm64` -- **must** be `arm64`, not `any` or `all` (contains compiled kernel modules)
- `Depends: ${misc:Depends}` -- debhelper substitution variable; additional runtime deps added later
- `Description:` -- short + long description

### Pattern 2: Skeleton debian/rules with dh

**What:** A minimal `debian/rules` that uses the `dh` sequencer. For Phase 1, override targets are stubs or empty -- they will be filled in Phase 2 when the IgH source is wired up.

**When to use:** Always for debhelper-based packages.

**Example:**
```makefile
#!/usr/bin/make -f
export DH_VERBOSE = 1

%:
	dh $@
```

**Key detail:** `debian/rules` must be executable (`chmod +x`). `dpkg-buildpackage` will fail if it is not executable.

### Pattern 3: Proper Changelog Entry Format

**What:** The changelog follows a strict format that `dpkg-parsechangelog` validates.

**Format:**
```
package (version) distribution; urgency=medium

  * Initial release.

 -- Maintainer Name <email@example.com>  Day, DD Mon YYYY HH:MM:SS +ZZZZ
```

**Critical formatting rules:**
- Two spaces before the `*` bullet
- Exactly one space before the `--` (maintainer line)
- Exactly two spaces between the email `>` and the date
- Date must be RFC 5322 format (obtainable via `date -R`)
- Distribution is typically `unstable` for initial releases (or the target Ubuntu codename like `jammy`)

### Pattern 4: DEP-5 Copyright Format

**What:** Machine-readable copyright file following the DEP-5 specification.

**Format for IgH EtherCAT:**
```
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: IgH EtherCAT Master
Upstream-Contact: fp@igh.de
Source: https://gitlab.com/etherlab.org/ethercat

Files: *
Copyright: 2006-2024 Ingenieurgemeinschaft IgH
License: GPL-2.0

Files: lib/*
Copyright: 2006-2024 Ingenieurgemeinschaft IgH
License: LGPL-2.1

License: GPL-2.0
 [GPL-2.0 license text reference]

License: LGPL-2.1
 [LGPL-2.1 license text reference]
```

**Key:** IgH EtherCAT uses dual licensing -- GPL-2.0 for kernel modules and CLI tool, LGPL-2.1 for the userspace library. Both must be declared.

### Anti-Patterns to Avoid

- **Using `Architecture: any` for a kernel module package:** Kernel modules are architecture-specific and compiled against a specific kernel. Use `arm64` explicitly -- `any` would allow building on architectures where the Tegra kernel headers don't exist.
- **Using `Priority: extra`:** Deprecated since Debian Policy 4.0.1. Use `optional` instead. Lintian will warn.
- **Omitting `debian/source/format`:** Without this file, dpkg-source defaults to format `1.0`, which has different behaviors and generates lintian warnings.
- **Non-executable `debian/rules`:** `dpkg-buildpackage` requires `debian/rules` to be executable. Missing `chmod +x` is the most common "it doesn't work" mistake for new packagers.
- **Wrong date format in changelog:** The changelog date must be RFC 5322 (`Thu, 17 Mar 2026 12:00:00 +0000`). Any deviation causes `dpkg-parsechangelog` to fail.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Changelog formatting | Manual text editing | `dch --create` or follow exact template | dpkg-parsechangelog is strict about whitespace, date format, and structure |
| Build system orchestration | Custom Makefile calling configure/make | `dh $@` with override targets | debhelper handles 100+ edge cases (permissions, shlibs, strip, etc.) |
| Copyright file format | Free-form text | DEP-5 machine-readable template | Lintian validates DEP-5; free-form generates warnings |

**Key insight:** Every file in `debian/` has a strict format that tools validate. Hand-editing without understanding the exact whitespace, indentation, and field ordering rules causes silent failures. Use templates and validate with `dpkg-parsechangelog` / lintian.

## Common Pitfalls

### Pitfall 1: debian/rules Not Executable
**What goes wrong:** `dpkg-buildpackage` fails with `permission denied` when trying to invoke `debian/rules`.
**Why it happens:** Files created by text editors or `cat > file` do not have execute permission by default.
**How to avoid:** Always `chmod +x debian/rules` immediately after creating it. Verify with `ls -la debian/rules` -- should show `-rwxr-xr-x`.
**Warning signs:** `dpkg-buildpackage: error: debian/rules clean: Permission denied`

### Pitfall 2: Changelog Date Format Wrong
**What goes wrong:** `dpkg-parsechangelog` fails to parse the changelog, and `dpkg-buildpackage` aborts.
**Why it happens:** The date must be RFC 5322 format with exact spacing. Common mistakes: wrong day-of-week, missing timezone, wrong spacing between email and date.
**How to avoid:** Generate the date with `date -R` and paste it directly. The format is: `Day, DD Mon YYYY HH:MM:SS +ZZZZ` with exactly TWO spaces between `>` and the date.
**Warning signs:** `dpkg-parsechangelog: error: expected date`

### Pitfall 3: Missing Blank Line Between Control Stanzas
**What goes wrong:** `dpkg` parses both stanzas as one, leading to confusing errors about duplicate fields or missing required fields.
**Why it happens:** The Source and Package stanzas in `debian/control` must be separated by exactly one blank line. Extra blank lines or missing blank lines cause parse failures.
**How to avoid:** Use exactly one blank line between the Source stanza and the Package stanza. No trailing whitespace on the blank line.
**Warning signs:** `dpkg-checkbuilddeps: error: cannot read debian/control: field name must not be empty`

### Pitfall 4: Mixing Tabs and Spaces in debian/rules
**What goes wrong:** `make` fails because recipe lines must start with tabs, not spaces.
**Why it happens:** `debian/rules` is a Makefile. GNU Make requires recipe lines (commands under targets) to begin with a hard tab character. Editors that convert tabs to spaces break this.
**How to avoid:** Use a hard tab for recipe indentation. Configure editor to preserve tabs in Makefiles. Verify with `cat -A debian/rules` -- tab shows as `^I`.
**Warning signs:** `make: *** No rule to make target` or `missing separator`

### Pitfall 5: Package Name in Changelog Doesn't Match Control
**What goes wrong:** `dpkg-buildpackage` produces a `.deb` with an unexpected name, or source/binary package name mismatches cause build failures.
**Why it happens:** The package name in the first line of `debian/changelog` must exactly match the `Source:` field in `debian/control`. If they differ, dpkg is confused about which source package it's building.
**How to avoid:** Ensure `igh-seeedstudio` appears identically in both `debian/changelog` first line and `debian/control` `Source:` field.
**Warning signs:** `dpkg-buildpackage: source changed by` or version mismatch warnings.

## Code Examples

Verified patterns for the five required files:

### debian/control
```
Source: igh-seeedstudio
Section: kernel
Priority: optional
Maintainer: SeeedStudio <support@seeedstudio.com>
Build-Depends: debhelper-compat (= 13),
               build-essential,
               autoconf,
               automake,
               libtool,
               nvidia-l4t-kernel-headers (= 5.15.148-tegra)
Standards-Version: 4.6.1

Package: igh-seeedstudio
Architecture: arm64
Depends: ${misc:Depends}, kmod
Description: IgH EtherCAT Master for SeeedStudio Jetson
 Pre-compiled IgH EtherCAT Master 1.6 with the r8169 native driver
 for NVIDIA Jetson platforms running Tegra L4T kernel 5.15.148.
 Includes ec_master.ko and ec_r8169.ko kernel modules, the ethercat
 CLI tool, and systemd service integration.
```

**Notes:**
- `Build-Depends` continuation lines are indented with at least one space (convention: align to column)
- `nvidia-l4t-kernel-headers (= 5.15.148-tegra)` -- exact version pin; the `=` operator requires exact match
- `${misc:Depends}` -- debhelper substitution variable; resolved at build time
- `kmod` -- provides `modprobe`, `depmod` needed by postinst (added in later phase)
- Long description lines start with a single space; empty lines use ` .` (space-dot)
- `Standards-Version: 4.6.1` -- latest standards version available in Ubuntu 22.04

### debian/rules
```makefile
#!/usr/bin/make -f
export DH_VERBOSE = 1

%:
	dh $@
```

**Notes:**
- Must be executable: `chmod +x debian/rules`
- The `%:` is a match-anything target; `dh $@` dispatches to the appropriate debhelper sequence
- `DH_VERBOSE = 1` enables detailed build output (useful for debugging)
- The tab before `dh $@` MUST be a hard tab character, not spaces
- Override targets (e.g., `override_dh_auto_configure`) will be added in Phase 2

### debian/changelog
```
igh-seeedstudio (1.6.0) unstable; urgency=medium

  * Initial release.
  * IgH EtherCAT Master 1.6 for Jetson aarch64 with r8169 native driver.

 -- SeeedStudio <support@seeedstudio.com>  Mon, 17 Mar 2026 12:00:00 +0000
```

**Notes:**
- Package name `igh-seeedstudio` must match `Source:` in `debian/control`
- Version `1.6.0` without a Debian revision (no `-1` suffix) because this is a native package
- Distribution `unstable` is conventional for initial releases (can also use target codename)
- Two spaces before `*` bullet points
- One space before `--` on the maintainer line
- Exactly two spaces between `>` and the date
- Date is RFC 5322 format; generate with `date -R`

### debian/copyright (DEP-5)
```
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: IgH EtherCAT Master
Upstream-Contact: fp@igh.de
Source: https://gitlab.com/etherlab.org/ethercat

Files: *
Copyright: 2006-2024 Ingenieurgemeinschaft IgH, Essen
License: GPL-2.0-only

Files: lib/*
Copyright: 2006-2024 Ingenieurgemeinschaft IgH, Essen
License: LGPL-2.1-only

Files: debian/*
Copyright: 2026 SeeedStudio
License: GPL-2.0-only

License: GPL-2.0-only
 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; version 2 of the License.
 .
 On Debian systems, the complete text of the GNU General Public License
 version 2 can be found in /usr/share/common-licenses/GPL-2.

License: LGPL-2.1-only
 This library is free software; you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as published
 by the Free Software Foundation; version 2.1 of the License.
 .
 On Debian systems, the complete text of the GNU Lesser General Public
 License version 2.1 can be found in /usr/share/common-licenses/LGPL-2.1.
```

### debian/source/format
```
3.0 (native)
```

**Notes:**
- Single line, no trailing content
- `3.0 (native)` means no upstream tarball separation -- simplest for a single-repo project
- The `debian/source/` directory must be created (`mkdir -p debian/source`)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `debian/compat` file with integer | `debhelper-compat (= 13)` in Build-Depends | debhelper 12+ (2019) | No separate compat file needed; one less file to maintain |
| `Priority: extra` | `Priority: optional` | Debian Policy 4.0.1 (2017) | `extra` is deprecated; lintian warns |
| Free-form copyright | DEP-5 machine-readable | Debian Policy 4.0+ | Machine parseable; lintian validates |
| Source format 1.0 (implicit) | Source format `3.0 (native)` or `3.0 (quilt)` | dpkg-source 1.15.0 (2009) | Better compression, VCS file exclusion, explicit format declaration |

**Deprecated/outdated:**
- `debian/compat` file: Still supported by debhelper <= 14, but the Build-Depends method is recommended and will be required in future compat levels
- `Priority: extra`: Replaced by `optional` -- using `extra` triggers lintian `priority-extra-is-replaced-by-priority-optional`

## Open Questions

1. **Should debian/compat be created despite not being needed?**
   - What we know: The roadmap success criteria lists "compat" as a required file. However, `debhelper-compat (= 13)` in Build-Depends makes it unnecessary.
   - What's unclear: Whether the success criteria literally require the file, or just require compat level to be declared.
   - Recommendation: Create the `debian/compat` file containing `13` for explicit compliance with the stated criteria, even though it is technically redundant. This is harmless -- debhelper accepts both methods simultaneously as long as they agree on the compat level.

2. **Exact nvidia-l4t-kernel-headers version string for Build-Depends**
   - What we know: The package is called `nvidia-l4t-kernel-headers` and targets kernel `5.15.148-tegra`. The version string in the apt repository may differ from the kernel release string.
   - What's unclear: Whether the apt package version is exactly `5.15.148-tegra` or includes additional suffixes (e.g., `5.15.148-tegra-35.5.0`).
   - Recommendation: Use `nvidia-l4t-kernel-headers` without a version pin in Phase 1 control file (since Phase 1 only validates syntax, not installability). The exact version pin can be refined in Phase 2 when the build environment is set up and the actual package version is discoverable.

3. **Maintainer name and email for debian/control**
   - What we know: CONTEXT.md does not specify a maintainer.
   - What's unclear: Whether to use a generic project address or a specific person.
   - Recommendation: Use a project-level maintainer like `SeeedStudio Jetson Packaging <jetson-packaging@seeedstudio.com>` or the repository owner's identity. This can be updated later.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | dpkg-dev tooling (dpkg-parsechangelog, dpkg-checkbuilddeps, dpkg-buildpackage) |
| Config file | None -- tools read debian/ directory directly |
| Quick run command | `dpkg-parsechangelog -l debian/changelog` |
| Full suite command | `dpkg-buildpackage -d -T clean 2>&1; echo "Exit: $?"` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEB-01 | debian/control, rules, changelog, copyright, compat files exist and are syntactically valid | smoke | `dpkg-parsechangelog -l debian/changelog && grep -q "^Source:" debian/control && test -x debian/rules && test -f debian/copyright && test -f debian/source/format` | -- Wave 0 |
| DEB-02 | Package builds as igh-seeedstudio_1.6.0_arm64.deb (name + version correct) | smoke | `dpkg-parsechangelog -l debian/changelog -S Version` outputs `1.6.0` and `grep -q "^Package: igh-seeedstudio" debian/control` | -- Wave 0 |
| DEB-03 | Package declares Architecture: arm64 | unit | `grep -q "^Architecture: arm64" debian/control` | -- Wave 0 |

### Additional Verification Commands
| Check | Command | Expected |
|-------|---------|----------|
| Changelog is parseable | `dpkg-parsechangelog -l debian/changelog` | Exits 0, outputs Source/Version/Distribution fields |
| Control has required fields | `grep -cE "^(Source|Package|Architecture|Build-Depends|Maintainer|Description):" debian/control` | Count >= 6 |
| Build-Depends includes required packages | `grep "Build-Depends" debian/control` | Contains `build-essential`, `autoconf`, `automake`, `nvidia-l4t-kernel-headers` |
| Architecture is arm64 | `grep "^Architecture:" debian/control` | `Architecture: arm64` |
| Rules is executable | `test -x debian/rules` | Exits 0 |
| Source format declared | `cat debian/source/format` | `3.0 (native)` |
| dpkg-buildpackage can start parsing | `dpkg-buildpackage -d -T clean 2>&1` | No parse errors on control/changelog (build will fail due to missing source, which is expected and acceptable for Phase 1) |

### Sampling Rate
- **Per task commit:** `dpkg-parsechangelog -l debian/changelog && grep "^Architecture: arm64" debian/control && test -x debian/rules`
- **Per wave merge:** Full validation suite (all commands above)
- **Phase gate:** All validation commands pass before `/gsd:verify-work`

### Wave 0 Gaps
- No test files needed -- validation uses system `dpkg-dev` tools directly against `debian/` files
- Requires `dpkg-dev` package installed on the development machine (provides `dpkg-parsechangelog`, `dpkg-buildpackage`, etc.)
- On macOS: `dpkg-dev` may not be available; validation can be deferred to CI or run via Docker

## Sources

### Primary (HIGH confidence)
- [Debian Maintainers' Guide Ch.4: Required files](https://www.debian.org/doc/manuals/maint-guide/dreq.en.html) -- control, rules, changelog, copyright format requirements
- [debhelper(7) man page](https://www.man7.org/linux/man-pages/man7/debhelper.7.html) -- debhelper-compat Build-Depends method, compat level 13 behavior
- [DEP-5 Copyright Format 1.0](https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/) -- machine-readable copyright file specification
- [deb-changelog(5)](https://manpages.debian.org/testing/dpkg-dev/deb-changelog.5.en.html) -- exact changelog format specification
- [dpkg-buildpackage(1)](https://man7.org/linux/man-pages/man1/dpkg-buildpackage.1.html) -- build process steps, `-d` flag behavior
- [dpkg-parsechangelog(1)](https://man7.org/linux/man-pages/man1/dpkg-parsechangelog.1.html) -- changelog validation tool
- [Debian source format 3.0](https://wiki.debian.org/Projects/DebSrc3.0) -- native vs quilt format
- [deb-src-control(5)](https://man7.org/linux/man-pages/man5/deb-src-control.5.html) -- control file field specifications

### Secondary (MEDIUM confidence)
- [sittner/ec-debianize](https://github.com/sittner/ec-debianize) -- Reference debian/ directory for IgH EtherCAT packaging; targets older Debian/Stretch with DKMS but file structure patterns are relevant
- [IgH EtherCAT licensing](https://gitlab.com/etherlab.org/ethercat) -- Confirmed GPL-2.0 (kernel) + LGPL-2.1 (userspace) dual licensing via COPYING and COPYING.LESSER files
- [Debian debmake-doc Ch.6: Basics for packaging](https://www.debian.org/doc/manuals/debmake-doc/ch06.en.html) -- Packaging basics and debhelper integration
- Project research files (`.planning/research/ARCHITECTURE.md`, `STACK.md`, `PITFALLS.md`) -- project-level research from initialization

### Tertiary (LOW confidence)
- None -- Phase 1 is a well-documented domain with high-confidence primary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Debian packaging file formats are thoroughly documented in official Debian policy and man pages
- Architecture: HIGH -- File structure for debian/ is standardized with no ambiguity
- Pitfalls: HIGH -- Common mistakes are well-catalogued in Debian packaging guides and community knowledge
- Validation: HIGH -- dpkg-dev tools provide definitive syntax validation

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (stable domain -- Debian packaging conventions change slowly)
