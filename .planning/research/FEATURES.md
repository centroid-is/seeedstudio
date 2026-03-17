# Feature Research

**Domain:** Debian kernel module packaging for industrial automation (IgH EtherCAT on Jetson)
**Researched:** 2026-03-17
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete, broken, or dangerous to install.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `postinst` runs `depmod -a` | Kernel module packaging convention — without it the module won't load | LOW | Must run after module files are placed; `depmod -a` rebuilds module dependency map |
| `postinst` starts/enables ethercat service | Users expect `dpkg -i` to leave a working, running service | LOW | Use `dh_installsystemd` pattern or manually call `systemctl enable --now ethercat`; must be idempotent |
| `prerm` stops ethercat service before removal | Service must be stopped before module files are removed or it will hold locks | LOW | `systemctl stop ethercat` in prerm; `systemctl disable ethercat` in postrm |
| `prerm` unloads kernel modules | `rmmod ec_r8169 ec_master` before files are removed | LOW | Module files cannot be deleted while loaded; prerm must call `modprobe -r` or `rmmod` with error tolerance |
| Blacklist file: `/etc/modprobe.d/blacklist-eth-ethercat.conf` | Stock r8168 and r8169 drivers conflict with EtherCAT native driver — without blacklist system randomly loads wrong driver | MEDIUM | Must blacklist both `r8168` and `r8169`; use `install r8169 /bin/false` pattern not just `blacklist` keyword (blacklist alone doesn't prevent manual `modprobe`); must be removed on package purge |
| `/etc/ethercat.conf` with `MASTER0_DEVICE` and `DEVICE_MODULES` | IgH ethercat init/systemd service reads this file to know which NIC and driver to use; without it the service fails to start | LOW | `MASTER0_DEVICE` = MAC of enP8p1s0; `DEVICE_MODULES="r8169"`; must be declared as conffile so user edits survive upgrades |
| Conffile protection for `/etc/ethercat.conf` | Debian policy: user-edited config files must not be silently overwritten on upgrade | LOW | Declare in `debian/conffiles` or use `ucf`; dpkg will prompt user on upgrade if conf diverged from default |
| Correct package dependencies declared | `Build-Depends` and `Depends` must cover all required libs so package installs on a clean system | LOW | Runtime: none special beyond system libs; Build: `build-essential`, `automake`, `linux-headers-5.15.148-tegra` or equivalent |
| Kernel module binary in correct location | Modules must land in `/lib/modules/$(uname -r)/extra/` or `/updates/` | LOW | EtherCAT build system places them; package must capture them under the right path |
| `debian/control` Architecture: `arm64` | Package must declare correct arch to prevent installation on wrong platform | LOW | Must NOT be `all` since it contains compiled kernel modules |
| Version string in package filename | Package consumers (CI, ops) identify versions from filename | LOW | Standard `dpkg-deb` convention: `igh-seeedstudio_1.6.x_arm64.deb` |

### Differentiators (Competitive Advantage)

Features that set this package apart from "compile it yourself" or ad-hoc installation scripts.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| `postinst` auto-detects MAC from `enP8p1s0` | Eliminates manual `ip link show` + editing ethercat.conf — a known friction point for every new Jetson setup | MEDIUM | Use `ip -j link show enP8p1s0 \| python3 -c "import json,sys; print(json.load(sys.stdin)[0]['address'])"` or `cat /sys/class/net/enP8p1s0/address`; only write conf if not already customized (idempotent); fall back to `ff:ff:ff:ff:ff:ff` broadcast wildcard if interface not found |
| Dockerfile for build verification | Proves the package builds cleanly from a fresh environment — catches missing build deps before CI runs on real hardware | MEDIUM | Docker can't load kernel modules, so scope is strictly build + `dpkg -i` install verification (not runtime test); use nvidia-l4t-base or ubuntu:22.04-aarch64 |
| GitHub Actions CI on push + release on `v*` tag | Trusted, reproducible artifact delivery — no more "which .deb did you build?" | MEDIUM | Two-job pipeline: (1) build .deb on every push, (2) attach .deb as release asset on `v*` tags using `softprops/action-gh-release`; artifact name includes version |
| `postrm purge` removes blacklist and conf files | Clean uninstall — no leftover modprobe.d blacklists that would prevent r8169 from working after package removal | LOW | `postrm` script with `if [ "$1" = "purge" ]` guard; removes `/etc/modprobe.d/blacklist-eth-ethercat.conf`; does NOT remove `/etc/ethercat.conf` on plain `remove` (only on purge) |
| Explicit kernel version in package name or Provides | Makes it obvious the package is kernel-tied — prevents accidental install on wrong kernel | LOW | Either encode kernel version in package name (`igh-seeedstudio-5.15.148-tegra`) or add a `Provides: ethercat-kernel-5.15.148` virtual package |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem helpful but create maintenance debt, complexity, or violate packaging conventions.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| DKMS integration | Survive kernel upgrades without re-installing | Tegra kernel headers are not available in a standard apt repo — DKMS build would silently fail on any kernel update because headers won't be present; DKMS adds significant complexity (source tree in `/usr/src/`, DKMS config, dkms.conf) for a target that has a fixed kernel | Pin to exact kernel version; document that kernel upgrades require a new `.deb` build; this is acceptable for an embedded Jetson deployment where the kernel is managed by L4T, not apt |
| Multi-NIC auto-discovery | Flexible deployment across different carrier boards | Requires complex heuristics to identify the EtherCAT NIC vs management NIC; wrong selection silently breaks network; for SeeedStudio Jetson the interface is always `enP8p1s0` | Hardcode `enP8p1s0` with a documented override mechanism (edit `/etc/ethercat.conf` manually) |
| GUI or TUI configurator | Friendlier than editing conf files | Adds Python/Qt/ncurses dependency to an industrial package; conf file with comments is the industry standard for EtherCAT configuration; GUI is never available over SSH | Ship a well-commented `/etc/ethercat.conf` template with inline documentation |
| Interactive debconf prompts during install | Ask user to confirm MAC address | Breaks unattended/automated installation (no `DEBIAN_FRONTEND=noninteractive` equivalent exists that would satisfy EtherCAT config); industrial deployments are scripted | Auto-detect from known interface; fall back to `ff:ff:ff:ff:ff:ff` wildcard MAC which is documented in IgH upstream |
| Runtime slave device testing in CI | Validate EtherCAT works end-to-end | Requires physical EtherCAT slave hardware attached to runner; no affordable CI-friendly simulation exists for kernel module + real NIC combination | CI validates build + `dpkg -i` install + `systemctl is-enabled` check; runtime testing is a manual acceptance test gate |
| Split dev package (`igh-seeedstudio-dev`) | Provide headers for application development | Adds packaging complexity and is only useful if anyone builds EtherCAT applications on the Jetson itself (vs. cross-compiling); scope is a working master, not a dev SDK | Can be added later as a separate package if demand exists; defer for v1 |

## Feature Dependencies

```
[postinst: depmod -a]
    └──requires──> [kernel module .ko files installed to /lib/modules/]

[postinst: start ethercat service]
    └──requires──> [/etc/ethercat.conf exists with MASTER0_DEVICE]
                       └──requires──> [MAC auto-detection or manual conf]
    └──requires──> [ec_master + ec_r8169 modules loadable]
                       └──requires──> [depmod -a already run]
    └──requires──> [blacklist file installed]
                       └──reason──> stock r8169 must not load first or ec_r8169 bind fails

[prerm: stop service]
    └──must precede──> [prerm: rmmod modules]
                           └──must precede──> [dpkg removes .ko files]

[postrm purge: remove blacklist + conf]
    └──must NOT run on plain remove──> [preserve user-edited ethercat.conf]

[Dockerfile build verification]
    └──requires──> [debian/ packaging files complete]
    └──enhances──> [GitHub Actions CI] (same Dockerfile used as CI build environment)

[GitHub Actions CI release]
    └──requires──> [Dockerfile build verification working]
    └──requires──> [version tag convention established (v*)]
```

### Dependency Notes

- **`depmod -a` must precede `systemctl start ethercat`**: The service loads modules via `modprobe ec_master`; if `depmod` hasn't run yet, modprobe fails silently and the service starts in a broken state.
- **Blacklist must precede first boot after install**: If the system reboots before the blacklist takes effect and r8169 loads, it will grab the NIC before ec_r8169 can claim it. `postinst` must run `update-initramfs -u` or at minimum instruct the user to reboot — a cold-start test is required.
- **MAC auto-detection only works if the interface is already up**: `enP8p1s0` naming is udev-assigned; during `postinst` the interface should be present if on physical Jetson hardware, but won't exist inside Docker (fallback to `ff:ff:ff:ff:ff:ff` required).
- **Conffile declaration conflicts with auto-written conf**: If `/etc/ethercat.conf` is both a `conffile` (dpkg-tracked) and modified by `postinst` (MAC injection), dpkg will flag it as modified every upgrade. Resolution: ship a static default conffile with `MASTER0_DEVICE=ff:ff:ff:ff:ff:ff`; let `postinst` only write the file if it does not exist yet (first install only).

## MVP Definition

### Launch With (v1)

Minimum viable: `dpkg -i` on a Jetson results in a working EtherCAT master without any manual steps.

- [ ] Kernel module `.ko` files built against Tegra 5.15.148 kernel headers and installed to `/lib/modules/`
- [ ] `postinst` runs `depmod -a`
- [ ] `postinst` installs `/etc/modprobe.d/blacklist-eth-ethercat.conf` (blacklists r8168 + r8169 stock drivers)
- [ ] `postinst` writes `/etc/ethercat.conf` with MAC from `enP8p1s0` (or `ff:ff:ff:ff:ff:ff` fallback)
- [ ] `postinst` enables and starts ethercat systemd service
- [ ] `prerm` stops service and unloads modules
- [ ] `postrm purge` removes blacklist and conf files
- [ ] Dockerfile verifies the package builds and installs without errors
- [ ] GitHub Actions CI builds `.deb` on push, creates GitHub Release artifact on `v*` tag

### Add After Validation (v1.x)

- [ ] `update-initramfs -u` call in `postinst` — add if field testing shows the blacklist doesn't take effect until reboot after kernel initrd loads old module list
- [ ] Explicit kernel version in `Provides:` virtual package — add when a second kernel target is considered (helps conflict resolution)
- [ ] `postrm` calls `update-initramfs -u` on purge — add if blacklist removal must survive into initrd

### Future Consideration (v2+)

- [ ] Split `igh-seeedstudio-dev` package with headers — only if applications will be built on-device
- [ ] Support for additional NIC interfaces beyond `enP8p1s0` — only if deployed on other carrier boards
- [ ] DKMS package variant — only if the Tegra kernel becomes a standard apt-managed kernel with headers in the repo

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| `postinst`: depmod + service enable/start | HIGH | LOW | P1 |
| `prerm`: stop service + rmmod | HIGH | LOW | P1 |
| Blacklist `/etc/modprobe.d/blacklist-eth-ethercat.conf` | HIGH | LOW | P1 |
| `/etc/ethercat.conf` with conffile protection | HIGH | LOW | P1 |
| MAC auto-detection from `enP8p1s0` | HIGH | MEDIUM | P1 |
| `postrm purge` cleanup | MEDIUM | LOW | P1 |
| Dockerfile build verification | HIGH | MEDIUM | P1 |
| GitHub Actions CI + tag release | HIGH | MEDIUM | P1 |
| Kernel version in `Provides:` virtual package | LOW | LOW | P2 |
| `update-initramfs` in postinst/postrm | MEDIUM | LOW | P2 |
| Split dev package | LOW | MEDIUM | P3 |
| DKMS support | MEDIUM | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

Compared against existing EtherCAT packaging approaches in the wild:

| Feature | ec-debianize (sittner/zultron) | ethercat_igh_dkms (ICube-Robotics) | Our Approach |
|---------|-------------------------------|-------------------------------------|--------------|
| Kernel version targeting | Generic, any kernel | DKMS — rebuilds for each kernel | Hard-pinned to Tegra 5.15.148 |
| NIC configuration | `/etc/default/ethercat` config | Interactive script with auto-detect | postinst auto-detect + conffile |
| Blacklist management | `update-ethercat-config` script | Managed by DKMS/init scripts | Explicit `/etc/modprobe.d/` file, removed on purge |
| CI / release pipeline | None | None | GitHub Actions + tagged GitHub Release |
| Build verification | Manual | Manual | Dockerfile + CI |
| Service integration | SysV init + systemd unit | systemd | systemd via postinst |
| Architecture | Generic (x86/arm) | Generic | Explicit arm64 / Tegra |
| Complexity | Medium (two packages: driver + dev) | High (Python installer, DKMS overhead) | Low (single package, shell scripts) |

**Assessment:** Existing solutions are either too generic (must manually specify kernel headers, NIC) or too complex (DKMS + Python installer adds failure modes). Our approach favors a minimal, explicit, single-target package that is maximally reliable for the specific Jetson + SeeedStudio carrier context.

## Sources

- IgH EtherCAT upstream: https://gitlab.com/etherlab.org/ethercat
- ec-debianize packaging reference: https://github.com/sittner/ec-debianize
- ethercat_igh_dkms package: https://github.com/ICube-Robotics/ethercat_igh_dkms
- DKMS Debian packaging guide: https://wiki.debian.org/DkmsPackaging
- Vincent Bernat DKMS packaging: https://vincent.bernat.ch/en/blog/2018-packaging-driver-debian-dkms
- Debian systemd packaging: https://wiki.debian.org/Teams/pkg-systemd/Packaging
- dh_installsystemd man page: https://manpages.debian.org/testing/debhelper/dh_installsystemd.1.en.html
- Debian conffiles/ucf policy: https://wiki.debian.org/ConfigPackages
- Kernel module blacklisting: https://wiki.debian.org/KernelModuleBlacklisting
- GitHub Actions release artifact: https://trstringer.com/github-actions-create-release-upload-artifacts/
- IgH ethercat.conf reference: https://github.com/ribalda/ethercat/blob/master/script/ethercat.conf
- Jetson r8169 removal discussion: https://forums.developer.nvidia.com/t/how-to-remove-r8169-linux-kernel-module/249718

---
*Feature research for: IgH EtherCAT .deb packaging on Jetson (igh-seeedstudio)*
*Researched: 2026-03-17*
