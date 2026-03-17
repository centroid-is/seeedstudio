# Phase 5: Docker Verification - Research

**Researched:** 2026-03-17
**Domain:** Docker-based Debian package build verification for NVIDIA Jetson aarch64
**Confidence:** HIGH

## Summary

Phase 5 creates a Dockerfile that builds the `.deb` package from scratch in an aarch64 ubuntu:22.04 container, verifies `dpkg -i` succeeds, and confirms `ec_r8169.ko` was produced. This is the end-to-end smoke test that validates all work from Phases 1-4.

The primary technical challenge is installing `nvidia-l4t-kernel-headers` inside Docker. The package depends on `nvidia-l4t-kernel`, which pre-depends on `nvidia-l4t-core`. The `nvidia-l4t-core` package has a preinst script that checks `/proc/device-tree/compatible`, which does not exist in Docker containers. The recommended workaround is to use `apt-get download` + `dpkg -x` to extract the kernel headers without triggering the dependency chain's preinst scripts. The `nvidia-l4t-kernel-headers` package itself has no package scripts, making extraction safe.

**Primary recommendation:** Download `nvidia-l4t-kernel-headers` via `apt-get download` and extract with `dpkg -x` to bypass `nvidia-l4t-core` preinst device-tree check. Use `dpkg-buildpackage -us -uc -b` to build the .deb, then verify with `dpkg -i` (postinst is Docker-safe due to existing systemd guards).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None -- all implementation choices at Claude's discretion (pure infrastructure phase).

### Claude's Discretion
All implementation choices are at Claude's discretion -- pure infrastructure phase.

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DOC-01 | Dockerfile builds the .deb from scratch in an aarch64 ubuntu:22.04 environment | Dockerfile pattern with L4T repo setup, build-depends installation, and dpkg-buildpackage |
| DOC-02 | Dockerfile verifies the .deb installs without errors (dpkg -i succeeds) | postinst is Docker-safe (systemd guard, MAC detection graceful fallback); dpkg -i will exit 0 |
| DOC-03 | Docker build runs before r8168 driver is unloaded (tests build in safe environment) | Docker builds in isolated container; no kernel module operations occur; depmod targets 5.15.148-tegra specifically |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Docker | 20.10+ | Container build environment | Standard CI/CD build isolation |
| ubuntu:22.04 | 22.04 LTS | Base image | Matches target Jetson L4T rootfs (JetPack 6.x uses Ubuntu 22.04) |
| dpkg-buildpackage | from dpkg-dev | Build .deb package | Standard Debian package builder |
| dpkg | from base | Install .deb for verification | Standard Debian package manager |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| apt-get download | Download .deb without installing | Fetching nvidia-l4t-kernel-headers without triggering nvidia-l4t-core preinst |
| dpkg -x | Extract .deb contents without running scripts | Placing kernel headers in /usr/src without dependency chain |
| fakeroot | Privilege simulation for dpkg-buildpackage | Used by dpkg-buildpackage -rfakeroot (default behavior) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| apt-get download + dpkg -x | apt-get install with --force flags | Force-install risks partial state; extract is cleaner and predictable |
| apt-get download + dpkg -x | nvcr.io/nvidia/l4t-base image | Pre-built L4T base images exist but are heavy and tied to specific R36 releases |
| ubuntu:22.04 base | nvcr.io/nvidia/l4t-base:r36.2.0 | L4T base has headers pre-installed but adds unnecessary NVIDIA runtime deps |

## Architecture Patterns

### Recommended Dockerfile Structure
```dockerfile
# Dockerfile at project root
FROM ubuntu:22.04

# 1. System setup (noninteractive, ca-certificates for HTTPS repos)
# 2. Add NVIDIA L4T apt repo (GPG key + sources.list)
# 3. Install build dependencies from debian/control
# 4. Download + extract nvidia-l4t-kernel-headers (bypass preinst)
# 5. Copy project source into container
# 6. Run dpkg-buildpackage
# 7. Assert ec_r8169.ko exists
# 8. Install .deb with dpkg -i
# 9. Verify install succeeded
```

### Pattern 1: L4T Apt Repository Setup in Docker
**What:** Add NVIDIA Jetson apt repository for R36.4.3 packages
**When to use:** Any Docker build that needs NVIDIA L4T packages

```dockerfile
# Download and install GPG key
ADD https://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
    /etc/apt/trusted.gpg.d/jetson-ota-public.asc
RUN chmod 644 /etc/apt/trusted.gpg.d/jetson-ota-public.asc

# Add L4T repos for Orin (t234) platform, R36 release
RUN echo "deb https://repo.download.nvidia.com/jetson/common r36.4 main" \
      > /etc/apt/sources.list.d/nvidia-l4t-apt-source.list && \
    echo "deb https://repo.download.nvidia.com/jetson/t234 r36.4 main" \
      >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list
```

**Key details:**
- GPG key URL: `https://repo.download.nvidia.com/jetson/jetson-ota-public.asc`
- Platform for Orin devices: `t234`
- Release designation: `r36.4` (kernel 5.15.148-tegra = L4T R36.4.x / JetPack 6.2.x)
- Both `common` and platform-specific repos are needed

### Pattern 2: Kernel Headers Extraction (Bypass nvidia-l4t-core)
**What:** Get nvidia-l4t-kernel-headers into the container without triggering nvidia-l4t-core's preinst device-tree check
**When to use:** Any Docker build needing Tegra kernel headers

```dockerfile
# Download the .deb without installing (avoids dependency chain)
RUN apt-get update && \
    apt-get download nvidia-l4t-kernel-headers && \
    dpkg -x nvidia-l4t-kernel-headers_*.deb / && \
    rm nvidia-l4t-kernel-headers_*.deb
```

**Why this works:**
- `apt-get download` fetches the .deb file without installing or resolving pre-depends
- `dpkg -x` extracts file contents without running any package scripts
- `nvidia-l4t-kernel-headers` has no package scripts, so extraction is lossless
- Headers land in `/usr/src/linux-headers-5.15.148-tegra/` where debian/rules expects them (KDIR)

### Pattern 3: dpkg-buildpackage in Docker
**What:** Build .deb package as root user in container
**When to use:** CI/CD package builds

```dockerfile
COPY . /build/igh-seeedstudio
WORKDIR /build/igh-seeedstudio
RUN dpkg-buildpackage -us -uc -b
# Output lands in /build/igh-seeedstudio_1.6.0_arm64.deb (parent dir)
```

**Flags:**
- `-us`: Do not sign source package
- `-uc`: Do not sign .changes file
- `-b`: Binary-only build (no source package)

### Pattern 4: Post-build Verification
**What:** Install .deb and verify it works in Docker
**When to use:** Verification stage of Dockerfile

```dockerfile
# Install the built .deb
RUN dpkg -i /build/igh-seeedstudio_1.6.0_arm64.deb || true
RUN apt-get install -f -y  # Fix any missing runtime deps

# Verify key files exist
RUN test -f /lib/modules/5.15.148-tegra/extra/ec_master.ko
RUN test -f /lib/modules/5.15.148-tegra/extra/ec_r8169.ko
RUN test -f /usr/bin/ethercat
RUN test -f /etc/ethercat.conf
```

### Anti-Patterns to Avoid
- **Using `apt-get install nvidia-l4t-kernel-headers`:** Triggers nvidia-l4t-core preinst which checks /proc/device-tree/compatible (fails in Docker)
- **Using `--force-depends` with dpkg:** Creates partially installed package state, can break subsequent apt operations
- **Running `docker build` with QEMU emulation for arm64:** Extremely slow (45-90 min); use native arm64 runner or build on Jetson device
- **Skipping the ec_r8169.ko assertion:** Silent build failures are the #1 risk; the build must fail loudly if r8169 support was not compiled
- **Using `depmod -a` in verification:** Use `depmod 5.15.148-tegra` (specific version) since `depmod -a` targets the running kernel which is the Docker host kernel

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| L4T apt repo setup | Manual wget + apt-key commands | ADD + trusted.gpg.d pattern | apt-key is deprecated; trusted.gpg.d is the modern approach |
| Kernel header extraction | Complex dpkg --force chains | apt-get download + dpkg -x | Clean, predictable, no side effects |
| Build dependency list | Manually listing packages | Parse debian/control Build-Depends | Single source of truth; stays in sync with actual build |
| .deb file location | Hardcoded paths | Glob pattern `../*.deb` | dpkg-buildpackage always outputs to parent directory |

## Common Pitfalls

### Pitfall 1: nvidia-l4t-core preinst Fails in Docker
**What goes wrong:** `apt-get install nvidia-l4t-kernel-headers` fails because nvidia-l4t-core's preinst script reads `/proc/device-tree/compatible`, which doesn't exist in containers
**Why it happens:** nvidia-l4t-kernel-headers depends on nvidia-l4t-kernel, which pre-depends on nvidia-l4t-core; apt enforces the full dependency chain
**How to avoid:** Use `apt-get download nvidia-l4t-kernel-headers && dpkg -x` to extract headers without installing
**Warning signs:** Error message: "preinst: line 40: /proc/device-tree/compatible: No such file or directory"

### Pitfall 2: L4T Release Version Mismatch
**What goes wrong:** Wrong L4T release in apt source causes headers version mismatch with KDIR in debian/rules
**Why it happens:** Kernel 5.15.148-tegra maps to L4T R36.4.x, not R35.x or R36.2
**How to avoid:** Use `r36.4` as the release designation in the apt sources.list
**Warning signs:** `apt-get download` finds no package, or headers install to wrong directory name

### Pitfall 3: dpkg-buildpackage Output Location
**What goes wrong:** Dockerfile can't find the built .deb file
**Why it happens:** dpkg-buildpackage always outputs to the parent directory (`../`), not the current directory
**How to avoid:** Set up WORKDIR so parent directory is known (e.g., WORKDIR /build/src so .deb goes to /build/)
**Warning signs:** `No such file or directory` when trying to dpkg -i the .deb

### Pitfall 4: depmod Runs Against Wrong Kernel Version
**What goes wrong:** depmod -a in postinst targets the Docker host kernel, not 5.15.148-tegra
**Why it happens:** `depmod -a` uses `uname -r` which returns the host kernel version in Docker
**How to avoid:** The dh_installmodules autoscript generates `depmod KVERS` with the specific version from the module path, not `depmod -a`. This should work correctly. If manual depmod is needed, specify the version explicitly: `depmod 5.15.148-tegra`
**Warning signs:** depmod warning about missing Module.symvers (when targeting wrong kernel)

### Pitfall 5: postinst Fails in Docker Due to systemd/sysfs
**What goes wrong:** postinst tries to restart ethercat.service or read /sys/class/net/enP8p1s0/address
**Why it happens:** Docker containers don't have systemd or the target network interface
**How to avoid:** Already handled -- postinst has `[ -d /run/systemd/system ]` guard for service restart, and MAC detection has graceful fallback (empty string + stderr warning)
**Warning signs:** Non-zero exit from dpkg -i

### Pitfall 6: Git Clone Fails in Docker Build
**What goes wrong:** `git clone` in debian/rules fails because git is not installed or network is unavailable
**Why it happens:** debian/rules override_dh_update_autotools_config clones IgH EtherCAT from GitLab
**How to avoid:** Ensure `git` is in Build-Depends (already listed in debian/control) and DNS/network works in Docker build
**Warning signs:** "git: command not found" or "Could not resolve host" errors

### Pitfall 7: DEBIAN_FRONTEND Not Set
**What goes wrong:** Package installation prompts block the Docker build
**Why it happens:** Some packages have interactive prompts by default
**How to avoid:** Set `ENV DEBIAN_FRONTEND=noninteractive` early in the Dockerfile
**Warning signs:** Docker build hangs at apt-get install

## Code Examples

### Complete Dockerfile Structure
```dockerfile
# Build verification for igh-seeedstudio .deb package
# Validates: .deb builds from scratch, dpkg -i succeeds, ec_r8169.ko present
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install ca-certificates first (needed for HTTPS repos)
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates

# Add NVIDIA L4T apt repository
ADD https://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
    /etc/apt/trusted.gpg.d/jetson-ota-public.asc
RUN chmod 644 /etc/apt/trusted.gpg.d/jetson-ota-public.asc && \
    echo "deb https://repo.download.nvidia.com/jetson/common r36.4 main" \
      > /etc/apt/sources.list.d/nvidia-l4t-apt-source.list && \
    echo "deb https://repo.download.nvidia.com/jetson/t234 r36.4 main" \
      >> /etc/apt/sources.list.d/nvidia-l4t-apt-source.list

# Install build dependencies (mirrors debian/control Build-Depends)
RUN apt-get update && apt-get install -y --no-install-recommends \
    dpkg-dev \
    debhelper \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    git \
    fakeroot \
    && rm -rf /var/lib/apt/lists/*

# Install nvidia-l4t-kernel-headers via extraction (bypass nvidia-l4t-core preinst)
RUN apt-get update && \
    cd /tmp && \
    apt-get download nvidia-l4t-kernel-headers && \
    dpkg -x nvidia-l4t-kernel-headers_*.deb / && \
    rm -f nvidia-l4t-kernel-headers_*.deb && \
    rm -rf /var/lib/apt/lists/*

# Verify kernel headers are in place
RUN test -d /usr/src/linux-headers-5.15.148-tegra

# Copy project source
COPY . /build/igh-seeedstudio
WORKDIR /build/igh-seeedstudio

# Build the .deb package
RUN dpkg-buildpackage -us -uc -b

# The ec_r8169.ko assertion is already in debian/rules override_dh_auto_build
# It fails the build if ec_r8169.ko was not produced

# Install the .deb and verify
RUN dpkg -i /build/igh-seeedstudio_1.6.0_arm64.deb

# Final assertions
RUN test -f /lib/modules/5.15.148-tegra/extra/ec_r8169.ko && \
    echo "PASS: ec_r8169.ko is present"
```

### .dockerignore File
```
.git
.planning
*.deb
```

### Build Command (native arm64)
```bash
docker build -t igh-seeedstudio-verify .
```

### Build Command (cross-platform with buildx, NOT recommended -- very slow)
```bash
docker buildx build --platform linux/arm64 -t igh-seeedstudio-verify .
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| apt-key adv --fetch-key | ADD to /etc/apt/trusted.gpg.d/ | apt-key deprecated 2022 | Use trusted.gpg.d for GPG keys |
| nvcr.io/nvidia/l4t-base images | ubuntu:22.04 + manual L4T repo | Ongoing | Lighter, more control, no NVIDIA runtime deps |
| r32/r34/r35 L4T releases | r36.4 for JetPack 6.2.x | 2024 | 5.15.148-tegra kernel, Ubuntu 22.04 rootfs |

**Important version mapping:**
- Kernel 5.15.148-tegra = L4T R36.4.x = JetPack 6.2.x
- Platform: Orin series = t234 (not t194/Xavier, not t210/Nano)

## Open Questions

1. **Exact L4T minor release for nvidia-l4t-kernel-headers**
   - What we know: Kernel 5.15.148-tegra is used across R36.4, R36.4.3, R36.4.4, R36.4.7
   - What's unclear: Whether `r36.4` in the sources.list resolves the correct headers package version, or if a more specific release like `r36.4.3` is needed
   - Recommendation: Start with `r36.4` (the base minor release); if `apt-get download` fails, try `r36.4.3`. The Dockerfile should make this configurable via an ARG.

2. **Header directory name verification**
   - What we know: KDIR in debian/rules is `/usr/src/linux-headers-5.15.148-tegra`
   - What's unclear: Whether the nvidia-l4t-kernel-headers package installs to exactly this path
   - Recommendation: Add a `RUN test -d /usr/src/linux-headers-5.15.148-tegra` assertion after header extraction; if it fails, `ls /usr/src/linux-headers-*` to discover the actual path

3. **dpkg -i behavior with missing runtime deps**
   - What we know: The package Depends on `kmod` (for depmod/modprobe), which should be in the base ubuntu:22.04 image
   - What's unclear: Whether `${misc:Depends}` expands to anything beyond kmod that might not be in the container
   - Recommendation: Use `dpkg -i ... || apt-get install -f -y` pattern to auto-resolve any missing deps

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Docker build (pass/fail) |
| Config file | Dockerfile (root of project) |
| Quick run command | `docker build -t igh-verify .` |
| Full suite command | `docker build --no-cache -t igh-verify .` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOC-01 | Dockerfile builds .deb from scratch in aarch64 ubuntu:22.04 | integration | `docker build -t igh-verify .` | No -- Wave 0 |
| DOC-02 | dpkg -i succeeds inside container | integration | Embedded in Dockerfile as `RUN dpkg -i` | No -- Wave 0 |
| DOC-03 | ec_r8169.ko confirmed present after build | integration | Embedded in Dockerfile as `RUN test -f` + debian/rules assertion | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `docker build -t igh-verify .` (full Dockerfile is the test)
- **Per wave merge:** `docker build --no-cache -t igh-verify .` (clean build)
- **Phase gate:** `docker build --no-cache` must exit 0

### Wave 0 Gaps
- [ ] `Dockerfile` -- the Dockerfile itself (does not exist yet)
- [ ] `.dockerignore` -- exclude .git, .planning, *.deb from build context

## Sources

### Primary (HIGH confidence)
- [NVIDIA Jetson Linux R36.4.3 Developer Guide - Software Packages](https://docs.nvidia.com/jetson/archives/r36.4.3/DeveloperGuide/SD/SoftwarePackagesAndTheUpdateMechanism.html) - L4T apt repo URL format, release designations, package dependencies
- [NVIDIA Developer Forums - Adding L4T repos to Docker](https://forums.developer.nvidia.com/t/adding-https-repo-download-nvidia-com-jetson-repositories-to-docker-image/121900) - GPG key URL, Dockerfile pattern for L4T repo setup
- [NVIDIA Developer Forums - Installing nvidia-l4t-core in Docker](https://forums.developer.nvidia.com/t/installing-nvidia-l4t-core-package-in-a-docker-layer/153412) - nvidia-l4t-core preinst /proc/device-tree/compatible failure in Docker
- [NVIDIA Minimized L4T Guide](https://nvidia-ai-iot.github.io/jetson-min-disk/jp5_minimal-l4t.html) - .nv-l4t-disable-boot-fw-update-in-preinstall pattern, dpkg-deb extraction pattern

### Secondary (MEDIUM confidence)
- [NVIDIA Developer Forums - nvidia-l4t-core in Docker R36](https://forums.developer.nvidia.com/t/how-to-install-nvidia-l4t-core-in-docker/329942) - Confirmed nvidia-l4t-kernel-headers has no package scripts
- [GitHub - dusty-nv/jetson-containers #1539](https://github.com/dusty-nv/jetson-containers/issues/1539) - Kernel 5.15.148-tegra = L4T R36.4.7 / JetPack 6.2.1
- [JetsonHacks - JetPack Versions](https://jetsonhacks.com/jetpack-and-jetson-linux-l4t-versions/) - L4T to JetPack version mapping
- [Seeed Studio Linux_for_Tegra](https://github.com/Seeed-Studio/Linux_for_Tegra) - SeeedStudio uses t234 platform, R36.x releases

### Tertiary (LOW confidence)
- L4T release `r36.4` as apt distribution name -- needs validation that this resolves correctly (may need `r36.4.3` or similar)
- Exact nvidia-l4t-kernel-headers install path -- needs verification via extraction in Docker

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Docker + dpkg-buildpackage is well-established; ubuntu:22.04 matches target
- Architecture: HIGH - Dockerfile pattern is straightforward; L4T repo setup is well-documented
- Pitfalls: HIGH - nvidia-l4t-core preinst issue is well-documented; postinst Docker safety already built into Phase 3/4 code
- L4T repo URL: MEDIUM - Release designation `r36.4` needs validation; kernel-to-release mapping confirmed by multiple sources

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (L4T repo URLs are stable; kernel version is pinned)
