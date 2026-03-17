# Pitfalls Research

**Domain:** IgH EtherCAT .deb packaging for Jetson/Tegra aarch64
**Researched:** 2026-03-17
**Confidence:** HIGH (most pitfalls verified by multiple community reports and official documentation)

---

## Critical Pitfalls

### Pitfall 1: ethercat.conf Written to Wrong Path

**What goes wrong:**
The postinst script writes `ethercat.conf` to `/etc/ethercat.conf`, but `ethercatctl` reads from `$PREFIX/etc/ethercat.conf`. With the default IgH build prefix of `/usr/local`, the runtime path is `/usr/local/etc/ethercat.conf`. The service starts, `ec_master` loads, and immediately fails with `EtherCAT ERROR: MAC address may not be empty.` because it read the empty template at `/usr/local/etc/`, not the populated file at `/etc/`.

**Why it happens:**
Developers assume `/etc/` is the canonical system config path (it usually is on Debian). IgH EtherCAT's configure/install bakes the prefix into the `ethercatctl` script at compile time, so the path is determined by `--prefix`, not by FHS convention. This trips everyone who doesn't set `--prefix=/usr`.

**How to avoid:**
Either:
- Use `--prefix=/usr` in the configure invocation so that `$PREFIX/etc` resolves to `/etc/ethercat.conf`, or
- In the postinst, install the conf to `$(ethercat_prefix)/etc/ethercat.conf` where prefix is known from the build.

For a .deb package targeting `/usr/local`, the postinst must write to `/usr/local/etc/ethercat.conf` and the package must install that directory. Using `--prefix=/usr` is simpler and aligns with Debian FHS conventions.

**Warning signs:**
- `systemctl status ethercat` shows `Active: failed` immediately after install
- `journalctl -u ethercat` shows `EtherCAT ERROR: MAC address may not be empty`
- `modprobe ec_master` returns `ERROR: could not insert 'ec_master': Invalid argument`

**Phase to address:** Package build configuration phase (configure flags + postinst script authoring)

---

### Pitfall 2: Module Built Against Wrong Kernel Version

**What goes wrong:**
The EtherCAT kernel modules (`ec_master.ko`, `ec_r8169.ko`) are compiled against kernel headers for version X but installed on a system running kernel version Y. The result is `modprobe: ERROR: could not insert 'ec_master': Exec format error` — the module refuses to load because the kernel vermagic doesn't match.

**Why it happens:**
On Jetson, the running kernel is `5.15.148-tegra` — a downstream NVIDIA patch series. If the build uses generic Ubuntu `linux-headers-5.15.0-generic` or fetches headers by uname from a different host, the vermagic string will differ. Even a minor patch-level difference (e.g. `5.15.148-tegra` vs `5.15.148`) breaks loading. This is especially acute in CI: the GitHub Actions runner kernel is an Azure-patched Ubuntu variant for which no matching headers exist in public apt repos.

**How to avoid:**
- Obtain the exact L4T headers package from NVIDIA's apt repository: `nvidia-l4t-kernel-headers` or `linux-headers-$(uname -r)` on the target Jetson.
- In CI/Dockerfile, install the Tegra headers .deb explicitly — do not rely on `linux-headers-$(uname -r)` resolving to the correct package in a generic Ubuntu environment.
- Pin the headers package version to match the target kernel exactly. Document the exact package name and version in the Dockerfile.

**Warning signs:**
- `modprobe ec_master` returns `Exec format error`
- `modinfo ec_master.ko | grep vermagic` shows a different string than `uname -r` output on the target device
- CI build succeeds but install on device immediately fails

**Phase to address:** Dockerfile / CI setup (build environment must provide correct Tegra headers)

---

### Pitfall 3: r8169 Stock Driver Still Loads Despite Blacklist

**What goes wrong:**
The package installs a blacklist file to `/etc/modprobe.d/blacklist-eth.conf`, but the stock `r8169` driver loads anyway on boot. The EtherCAT `ec_r8169` native driver then fails to claim the NIC, EtherCAT master finds no devices, and the service stays idle.

**Why it happens:**
`blacklist` in `modprobe.d` only prevents `modprobe` from loading a module on-demand. It does NOT prevent kernel auto-loading via hotplug/udev when the device is detected at boot. To fully prevent a module from loading via any path, the entry must be `install <module> /bin/true` (a fake install) rather than just `blacklist <module>`. This is documented in the Debian KernelModuleBlacklisting wiki and is a common trap.

Additionally, if the stock module is listed in `initramfs`, it will load before `modprobe.d` rules are consulted. The blacklist file must also be included in `initramfs` via `update-initramfs`.

**How to avoid:**
- Use `install r8169 /bin/true` and `install r8168 /bin/true` in the blacklist conf, not just `blacklist r8169`.
- Run `update-initramfs -u` in the postinst script after installing the blacklist conf.
- Verify at runtime: `lsmod | grep r8169` should show only `ec_r8169`, not the stock `r8169`.

**Warning signs:**
- `lsmod | grep r8169` shows both `r8169` and `ec_r8169` loaded simultaneously
- EtherCAT master log shows `No EtherCAT-capable network devices found`
- `ethercat master` output shows `0 slave(s)`

**Phase to address:** Package configuration files authoring (blacklist conf content) + postinst script (update-initramfs call)

---

### Pitfall 4: depmod Not Run After Module Install, modprobe Fails

**What goes wrong:**
The `.ko` files are copied into `/lib/modules/$(uname -r)/`, but `depmod -a` has not yet been run. `modprobe ec_master` fails with `Module ec_master not found` even though the file exists on disk. The postinst script then calls `modprobe` before `depmod` completes, causing the service restart to fail on first install.

**Why it happens:**
`modprobe` uses `modules.dep` — the dependency database generated by `depmod`. That file is stale until `depmod -a` is explicitly called. If the postinst script runs `modprobe` or `systemctl restart ethercat` before calling `depmod -a`, the module isn't findable. Ordering matters: `depmod -a` must complete before any `modprobe` or service restart.

**How to avoid:**
Postinst ordering must be:
1. Install `.ko` files (done by dpkg unpacking)
2. `depmod -a` — rebuild module dependency database
3. `modprobe ec_master` or `systemctl restart ethercat` — load module

Never combine steps 2 and 3 in a background shell or subshell where ordering isn't guaranteed.

**Warning signs:**
- `modprobe ec_master` returns `modprobe: FATAL: Module ec_master not found in directory /lib/modules/...`
- `dmesg` shows no EtherCAT entries after install
- Running `depmod -a` manually fixes the issue

**Phase to address:** postinst script authoring

---

### Pitfall 5: MAC Address Detection Fails When NIC Is Not Yet Up in postinst

**What goes wrong:**
The postinst script attempts to auto-detect the MAC address via `ip link show enP8p1s0 | awk ...` or `cat /sys/class/net/enP8p1s0/address`. If `enP8p1s0` isn't up yet (e.g. during first boot after install, or in a chroot-based install), the interface doesn't exist, the MAC is empty, and the generated `ethercat.conf` contains `MASTER0_DEVICE=""`. The EtherCAT master then fails to load with the "MAC address may not be empty" error.

**Why it happens:**
PCIe NICs on Jetson (especially with SeeedStudio carrier boards) may not appear as kernel network interfaces until the relevant PCIe driver finishes probing — which happens later in boot than package installation. A postinst running in a live system may catch the interface in a transient state. In container-based CI or during dpkg-based image construction, the NIC is never present.

**How to avoid:**
- Use a `try_detect` approach: attempt MAC detection but fall back to a recognizable sentinel value (e.g. `ff:ff:ff:ff:ff:ff` or `MASTER0_DEVICE=""` with a clear comment) rather than silently leaving the field empty.
- Print a clear post-install message: `"EtherCAT: Set MASTER0_DEVICE in /etc/ethercat.conf to your NIC MAC address before starting the service."`
- Do NOT fail the package install if MAC detection fails — that would break headless deployments.
- Add a `systemd` `ExecStartPre` that validates the MAC is non-empty before starting the master.

**Warning signs:**
- `grep MASTER0_DEVICE /etc/ethercat.conf` returns an empty string
- Install log shows no MAC detection output
- Interface `enP8p1s0` is absent in `ip link` during postinst execution

**Phase to address:** postinst script authoring (MAC detection with graceful fallback)

---

### Pitfall 6: IgH configure --enable-r8169 Silently Skipped if Driver Source Not Detected

**What goes wrong:**
Running `./configure --enable-r8169` does NOT fail if the r8169 driver source can't be found or the kernel headers don't expose the right symbols. The configure step succeeds, `make` proceeds, and the resulting package contains only the generic driver — silently omitting the native r8169 driver. The package installs cleanly but EtherCAT operates in generic mode with potentially degraded real-time performance.

**Why it happens:**
IgH EtherCAT's `configure.ac` performs feature detection for native drivers. If the kernel headers lack the expected r8169 symbols/structures for the version of the driver shipped with IgH, the feature is silently disabled. There is no build-time error — you must inspect `config.log` or the make output to confirm whether `ec_r8169.ko` was actually built.

**How to avoid:**
- After `make`, explicitly check that `ec_r8169.ko` was produced: `ls devices/ec_r8169.ko` — fail the build if absent.
- Add an assertion in the Dockerfile: `test -f /build/ethercat/devices/ec_r8169.ko || (echo "ERROR: ec_r8169 not built" && exit 1)`
- Review `config.log` for r8169-related configure output to confirm the driver was enabled.

**Warning signs:**
- Build succeeds but no `ec_r8169.ko` in the modules output directory
- `DEVICE_MODULES="r8169"` in ethercat.conf but `lsmod | grep ec_r8169` shows nothing after service start
- `ethercat master` output shows generic driver in use

**Phase to address:** Dockerfile / build verification

---

### Pitfall 7: GitHub Actions Runner Cannot Build Tegra Kernel Modules Without Emulation

**What goes wrong:**
Tegra kernel module builds require arm64 headers and an arm64 cross-compiler. Native GitHub Actions `ubuntu-latest` runners are amd64. Using QEMU emulation (e.g. `docker/setup-qemu-action`) for the full build inflates build times from minutes to 45-90 minutes, making CI impractical. Alternatively, using cross-compilation from amd64 requires the exact Tegra kernel headers be installable on an amd64 host, which is possible but requires careful multiarch setup.

**Why it happens:**
Kernel module Makefiles often use `$(CC)` without respecting `CROSS_COMPILE`, or autoconf scripts run test programs that fail under emulation. IgH EtherCAT uses autoconf (`./configure`) which may attempt runtime tests during cross-compilation, failing with "cannot run test program" unless properly configured.

**How to avoid:**
- Use GitHub Actions native arm64 runners (available for free since January 2025 via `ubuntu-24.04-arm`). This eliminates QEMU overhead entirely.
- Alternatively: install `gcc-aarch64-linux-gnu`, cross-compile headers, and set `ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-` — but verify that IgH's autoconf does not run aarch64 test programs.
- Set `--build=x86_64-linux-gnu --host=aarch64-linux-gnu` on the configure invocation when cross-compiling to prevent autoconf from trying to execute test programs.

**Warning signs:**
- CI job takes >30 minutes for a module build step
- QEMU-based jobs hit GitHub Actions 6-hour timeout
- `configure: error: cannot run test program while cross compiling` in CI logs

**Phase to address:** GitHub Actions workflow authoring

---

### Pitfall 8: Kernel Update via apt Breaks Installed EtherCAT Modules

**What goes wrong:**
After the EtherCAT package is installed, a routine `sudo apt upgrade` on the Jetson updates `nvidia-l4t-kernel` to a new patchlevel (e.g. `5.15.148-tegra+1` to `5.15.148-tegra+2`). The pre-compiled `.ko` files in the package are now for the old kernel version. `modprobe ec_master` starts returning `Exec format error` after the next reboot.

**Why it happens:**
Pre-compiled (non-DKMS) kernel modules are tied to an exact kernel vermagic. Unlike DKMS, they are not automatically rebuilt when the kernel updates. Jetson L4T kernel packages are updated by NVIDIA as part of JetPack updates, and `apt upgrade` applies them silently.

**How to avoid:**
- Document clearly: pin the `nvidia-l4t-kernel` package or hold it: `sudo apt-mark hold nvidia-l4t-kernel nvidia-l4t-kernel-headers`
- Add a postinst warning: `"WARNING: Do not upgrade nvidia-l4t-kernel without reinstalling igh-seeedstudio."`
- The package's `Depends:` control field should specify the exact kernel version it was built against, so dpkg will warn on mismatch.
- Consider DKMS as a future option to auto-rebuild on kernel update (see Technical Debt section).

**Warning signs:**
- EtherCAT service fails after `apt upgrade` and reboot
- `uname -r` output changed since package was installed
- `modinfo ec_master.ko | grep vermagic` no longer matches `uname -r`

**Phase to address:** Package control file (`Depends:` on exact kernel version) + user-facing documentation

---

### Pitfall 9: Blacklist File Not Taking Effect Because initramfs Not Rebuilt

**What goes wrong:**
The postinst installs `/etc/modprobe.d/blacklist-eth.conf` correctly. However, on the next boot, the stock `r8169` driver still loads because it was embedded in the initramfs image before the blacklist was installed. The blacklist only applies to modules loaded after initramfs hands off to the main rootfs.

**Why it happens:**
On Debian/Ubuntu, modules that are used for network interfaces are often pulled into initramfs. The `modprobe.d` blacklist files are also included in initramfs — but only when `update-initramfs` is run after the blacklist is installed. If the postinst script does not call `update-initramfs -u`, the old initramfs (without the blacklist) is used on the next boot.

**How to avoid:**
- Always call `update-initramfs -u` in the postinst script after installing any modprobe.d file.
- Ordering in postinst: (1) install `.ko` files, (2) install modprobe.d blacklist, (3) `update-initramfs -u`, (4) `depmod -a`, (5) service restart.
- In the corresponding postrm script, call `update-initramfs -u` after removing the blacklist file.

**Warning signs:**
- Blacklist file exists at `/etc/modprobe.d/blacklist-eth.conf` but `lsmod` shows stock `r8169` loaded
- Issue only occurs on reboot, not after manual `rmmod r8169` + `modprobe ec_r8169`
- `/boot/initrd.img-*` has an older timestamp than the blacklist file

**Phase to address:** postinst script authoring

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Pre-compiled .ko (not DKMS) | Simple package, no build tools needed on device | Breaks on every kernel update; requires package rebuild and reinstall | Acceptable for locked-down industrial deployments where kernel updates are controlled |
| Hardcode enP8p1s0 | No NIC discovery logic needed | Package fails if carrier board NIC naming changes with new JetPack | Acceptable for v1 targeting a single hardware SKU |
| Static MAC in ethercat.conf | Simple postinst | Wrong device MAC if cloned to another board | Acceptable if deployment is single-unit; add warning in postinst output |
| Docker for build verification only (no runtime test) | CI can run on amd64, fast | Cannot catch runtime driver load failures in CI | Acceptable for v1; plan a physical hardware integration test step |
| Generic GitHub Actions runner with arm64 QEMU | Zero cost, easy setup | Extremely slow (30-90 min builds) | Never for kernel module CI — use native arm64 runners |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| IgH EtherCAT + systemd | Copying ethercat.service to `/etc/systemd/system/` verbatim; it references ethercatctl with hardcoded prefix path | Review the installed service file path for ExecStart; confirm it matches the --prefix used at build time |
| IgH EtherCAT + modprobe.d | Using `blacklist r8169` without `install r8169 /bin/true` | Use `install r8169 /bin/true` to block all load paths including udev hotplug |
| NVIDIA L4T apt repo + kernel headers | Installing `linux-headers-$(uname -r)` hoping it resolves to Tegra headers | Install the specific NVIDIA package `nvidia-l4t-kernel-headers` from NVIDIA's apt repo |
| GitHub Actions + aarch64 module build | Using `docker/setup-qemu-action` for arm64 emulation | Use `runs-on: ubuntu-24.04-arm` for native arm64 execution (available free since Jan 2025) |
| depmod + modprobe in postinst | Calling modprobe before depmod finishes | Always sequence: depmod -a first, then modprobe / service restart |

---

## "Looks Done But Isn't" Checklist

- [ ] **ethercat.conf path:** Confirm `ethercatctl` reads from the path the postinst writes to — run `strings $(which ethercatctl) | grep etc` to find the compiled-in path
- [ ] **ec_r8169.ko built:** Verify `ec_r8169.ko` exists in the package — not just `ec_master.ko` and `ec_generic.ko`
- [ ] **Blacklist effectiveness:** After install + reboot, confirm `lsmod | grep r8169` shows only `ec_r8169`, not stock `r8169`
- [ ] **Kernel vermagic match:** Confirm `modinfo ec_master.ko | grep vermagic` matches `uname -r` on the target device exactly
- [ ] **depmod ran:** Confirm `modules.dep` was updated — check its timestamp post-install
- [ ] **Service actually claims NIC:** Run `ethercat master` and confirm device count is 1, not 0
- [ ] **initramfs updated:** Confirm `/boot/initrd.img-*` timestamp is newer than the blacklist file timestamp
- [ ] **Debian control Architecture field:** Confirm it is `arm64` not `amd64` or `all`

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong ethercat.conf path | LOW | Manually copy conf to correct `$PREFIX/etc/` path; restart service |
| Module vermagic mismatch | MEDIUM | Rebuild package against correct kernel headers; reinstall |
| Stock r8169 still loading | LOW | Run `install r8169 /bin/true` in modprobe.d manually; update-initramfs -u; reboot |
| depmod not run | LOW | Run `sudo depmod -a`; retry modprobe |
| MAC detection failed silently | LOW | Edit `/etc/ethercat.conf` (or `$PREFIX/etc/ethercat.conf`) manually; restart service |
| Kernel update broke modules | MEDIUM | Pin nvidia-l4t-kernel; rebuild/reinstall igh-seeedstudio .deb targeting new kernel |
| ec_r8169.ko not built | MEDIUM | Verify configure flags and kernel header symbols; rebuild with corrected configure invocation |
| QEMU CI timeout | LOW | Switch to native arm64 runner (`ubuntu-24.04-arm`) |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| ethercat.conf wrong path | Package build config (--prefix choice) + postinst authoring | `strings $(which ethercatctl) \| grep etc` matches postinst write target |
| Module wrong kernel version | Dockerfile / CI setup | `modinfo ec_master.ko \| grep vermagic` matches target device `uname -r` |
| Stock r8169 loads despite blacklist | Blacklist conf content authoring + postinst update-initramfs | Reboot + `lsmod \| grep r8169` shows only ec_r8169 |
| depmod ordering | postinst script authoring | Fresh install: `modprobe ec_master` succeeds without manual intervention |
| MAC detection failure | postinst script authoring | Install in containerized environment — service starts or gives clear human-readable error, not silent failure |
| ec_r8169.ko not built | Dockerfile build verification step | `test -f devices/ec_r8169.ko` assertion in Dockerfile |
| GitHub Actions QEMU slowness | CI workflow authoring | Job completes in <10 minutes |
| Kernel update breaks modules | Package control file + documentation | `Depends:` pins kernel version; README documents hold procedure |
| Blacklist not in initramfs | postinst script ordering | Reboot test confirms blacklist applied |

---

## Sources

- GitLab Forum — EtherCAT `modprobe: Invalid argument` / empty MAC: https://forum.gitlab.com/t/ethercat-install-on-ubuntu-23-04-rpi-gives-modprobe-invalid-argument-error-empty-mac-address/88658
- NVIDIA Developer Forums — IgH EtherCAT on Jetson Nano, `Exec format error` (vermagic mismatch): https://forums.developer.nvidia.com/t/jetson-nano-install-preempt-rt-successfull-and-build-ethercat-igh-module-problem/232271
- LinuxCNC Forum — EtherCAT build from source, gotchas (udev rules, depmod, generic driver): https://forum.linuxcnc.org/ethercat/49771-ethercat-build-from-source-full-instructions
- Debian Wiki — KernelModuleBlacklisting (`blacklist` vs `install /bin/true`): https://wiki.debian.org/KernelModuleBlacklisting
- Debian Wiki — depmod and postinst ordering: https://wiki.debian.org/depmod
- GitHub Community — Unable to install linux-headers in GitHub Action (Azure kernel mismatch): https://github.com/orgs/community/discussions/28607
- GitHub — QEMU aarch64 performance in GitHub Actions (45-90 min builds): https://github.com/docker/setup-qemu-action/issues/22
- GitHub — Native arm64 runners (available Jan 2025): https://github.com/orgs/community/discussions/19197
- NVIDIA Jetson Linux Developer Guide — Kernel Customization and apt upgrade impact: https://forums.developer.nvidia.com/t/apt-upgrade-uploads-nvidia-l4t-kernel/321141
- Debian CrossBuildPackagingGuidelines — autoconf cross-compilation test programs: https://wiki.debian.org/CrossBuildPackagingGuidelines
- IgH EtherCAT GitLab Issue #21 — systemd integration, ethercat.conf path confusion: https://gitlab.com/etherlab.org/ethercat/-/issues/21
- IgH EtherCAT GitLab Issue #1 — Compile errors on kernel 5.10 (timeval, function pointer): https://gitlab.com/etherlab.org/ethercat/-/issues/1

---
*Pitfalls research for: IgH EtherCAT .deb packaging for Jetson/Tegra aarch64*
*Researched: 2026-03-17*
