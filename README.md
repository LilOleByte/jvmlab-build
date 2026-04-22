# jvmlab-build

**[JVMLAB.org](https://jvmlab.org/)** — a single-script pipeline that builds a tiny, bootable live Linux ISO (kernel, userspace, ISOLINUX). This tree is `minimal.sh`, `clean.sh`, and related tooling.

**Userspace** is split across two sibling repositories:

- **[jvmlab-toybox](https://github.com/LilOleByte/jvmlab-toybox)** — static multicall binary for the non-shell applets.
- **[lsh](https://github.com/LilOleByte/lsh)** — minimal C shell that runs as PID 1 and ships as `/bin/sh`.

`minimal.sh` clones `jvmlab-toybox` at build time; it can either clone `lsh` or use a local sibling checkout at `../lsh`. See "Supply chain & reproducibility" below and `LICENSES.md` for exact URLs, pinned versions, and checksums.

## What the build does

`minimal.sh` fetches, builds, verifies, and assembles:

| Component | Source | Integrity |
|-----------|--------|-----------|
| **Linux** | Longterm 6.18.x from kernel.org | SHA256 pinned in `minimal.sh` |
| **Syslinux** | 6.03 from kernel.org | SHA256 pinned in `minimal.sh` |
| **jvmlab-toybox** | [LilOleByte/jvmlab-toybox](https://github.com/LilOleByte/jvmlab-toybox) | Git ref pinned via `JVMLAB_TOYBOX_REF` |
| **lsh** | [LilOleByte/lsh](https://github.com/LilOleByte/lsh) (or `../lsh`) | Git ref pinned via `JVMLAB_LSH_REF` |

## Userspace

The initramfs ships two static binaries plus symlinks:

- `/bin/lsh` — the shell. `/bin/sh` is a symlink to it. Also runs as PID 1:
  sets `PATH`, reaps orphans, handles `SIGCHLD`, and provides `poweroff`,
  `reboot`, `halt`, `true`, `false`, and `:` as builtins so the ISO can
  cleanly shut itself down without external binaries.
- `/bin/jvmlab-toybox` — multicall binary with `ls`, `clear`, `cat`,
  `echo`, `pwd`, `mount` wired in by symlink.

Why this split instead of one big toybox/busybox:

- **Smaller TCB** — only what's shipped; no setuid, no networking tools,
  no POSIX surface we don't use.
- **PID 1 correctness** — `lsh` is written for init duties; the
  multicall binary stays a plain applet runner.
- **Easy to review** — short C files; two repos you can audit in an
  afternoon.

Details: [jvmlab-toybox README](https://github.com/LilOleByte/jvmlab-toybox/blob/main/README.md), [lsh README](https://github.com/LilOleByte/lsh/blob/main/README.md).

## Supply chain & reproducibility

`minimal.sh` is written so every byte of `minimal.iso` is traceable to a
pinned source:

- **Upstream tarballs are verified.** The authoritative SHA256 for the
  Linux and Syslinux tarballs is baked into `minimal.sh` (values sourced
  from the signed `sha256sums.asc` files on `cdn.kernel.org`). A
  mismatch is fatal and any cached tarball that doesn't match gets
  re-downloaded.
- **Git refs are explicit.** `jvmlab-toybox` and `lsh` are fetched at
  the ref set by `JVMLAB_TOYBOX_REF` / `JVMLAB_LSH_REF`. For archival
  builds set these to a commit SHA or signed tag, not `main`. See
  `LICENSES.md` for the pinning strategy.
- **Timestamps are deterministic.** The script honours
  `SOURCE_DATE_EPOCH` and exports `KBUILD_BUILD_TIMESTAMP`,
  `KBUILD_BUILD_USER`, `KBUILD_BUILD_HOST` for the kernel build. The
  cpio pack is sorted (`LC_ALL=C`), forced to `root:root`, stamped to
  `SOURCE_DATE_EPOCH`, and uses `cpio --reproducible`. The gzip wrapper
  uses `-n`. The ISO uses a fixed volume id (`JVMLAB`) and
  `--modification-date` derived from `SOURCE_DATE_EPOCH`.
- **Bit-identical rebuilds are tested in CI.**
  `.github/workflows/ci.yml` runs `minimal.sh` twice on the same commit
  under different parallelism/locale and `diff`s the SHA256s of
  `minimal.iso`, `rootfs.gz`, and `bzImage`. A regression there fails
  the build.
- **Every build emits digests.** `minimal.sh` prints the SHA256 of
  `minimal.iso`, `rootfs.gz`, and `bzImage` on completion.

See [`LICENSES.md`](LICENSES.md) for the full component list with
versions, licences, checksum sources, and the userspace pinning plan.

## Kernel hardening profile

`configs/x86_64-minimal.config` is a kconfig *fragment* (not a full
`.config`) merged on top of `make defconfig` by `minimal.sh`. Every
directive has a one-line rationale in the file itself; the high-level
story is:

**Attack-surface reduction** — removed because nothing in the image
uses them: `CONFIG_NET`, `CONFIG_MODULES`, `CONFIG_KEXEC`,
`CONFIG_DEVMEM`, `CONFIG_DEVPORT`, `CONFIG_MAGIC_SYSRQ`,
`CONFIG_DEBUG_FS`, `CONFIG_PROC_KCORE`, `CONFIG_KPROBES`,
`CONFIG_UPROBES`, `CONFIG_BPF_SYSCALL`, `CONFIG_USER_NS`,
`CONFIG_IO_URING`, `CONFIG_HIBERNATION`, `CONFIG_SUSPEND`,
`CONFIG_IA32_EMULATION`, `CONFIG_X86_VSYSCALL_EMULATION`,
`CONFIG_LEGACY_PTYS`, `CONFIG_AUDIT`, `CONFIG_BINFMT_MISC`.

**Kernel self-protection** — pinned on so a future `defconfig` change
can't regress us silently: `STACKPROTECTOR_STRONG`, `FORTIFY_SOURCE`,
`INIT_STACK_ALL_ZERO`, `INIT_ON_ALLOC_DEFAULT_ON`,
`INIT_ON_FREE_DEFAULT_ON`, `HARDENED_USERCOPY`, `SLAB_FREELIST_RANDOM`,
`SLAB_FREELIST_HARDENED`, `RANDOMIZE_BASE` (KASLR),
`RANDOMIZE_MEMORY`, `SECURITY_DMESG_RESTRICT`,
`SCHED_STACK_END_CHECK`, `BUG_ON_DATA_CORRUPTION`, `SECURITY_YAMA`,
`STRICT_KERNEL_RWX`.

**Kernel command line** (set in the generated `isolinux.cfg`):
`panic=10 oops=panic page_alloc.shuffle=1 vsyscall=none slab_nomerge`.
An oops escalates to a panic, the box reboots 10 s later, page
allocator and slab layout are randomised, and vsyscall is refused at
runtime in addition to being compiled out.

Set `KERNEL_HARDENING=0 ./minimal.sh` to skip the fragment and build
stock `defconfig` — useful when bisecting a boot regression. CI runs
both the hardened default path and the reproducibility diff on every
push, so any flag that regresses the boot-smoke test fails the build
immediately.

## Userspace hardening

Both static binaries shipped in the initramfs (`/bin/lsh` and
`/bin/jvmlab-toybox`) are built with the same set of toolchain
defences so an exploit bug in either one has as few exploitation
primitives as possible. The flags live in each project's `Makefile`
and require GCC >= 12 or clang >= 16 (ubuntu-24.04 and CachyOS both
satisfy; older Debian stable does not).

**Compile-time**:

- `-fstack-protector-strong` — canaries on any function with a local
  buffer or pointer-typed local.
- `-fstack-clash-protection` — guard-page probes on large stack
  allocations; a VLA / `alloca` cannot jump over the guard into
  adjacent VM.
- `-fcf-protection=full` — Intel CET: `endbr64` at indirect-call
  targets (IBT) plus shadow-stack annotations (SHSTK). Zero-cost NOPs
  on non-CET CPUs; enforced in hardware on Tiger Lake / Alder Lake and
  newer.
- `-ftrivial-auto-var-init=zero` — zero every uninitialised stack
  variable on function entry. Pairs with the kernel's
  `CONFIG_INIT_STACK_ALL_ZERO=y`.
- `-fPIE` — required for the link step below.
- `-Wformat=2 -Werror=format-security` — user-controlled format
  strings refuse to compile.
- `-D_FORTIFY_SOURCE=2` — compile-time bounds checks on mem/str*
  (active with glibc; a no-op with musl but harmless and costs nothing
  if someone rebuilds against glibc).

**Link-time**:

- `-static-pie` — produces a static binary that is *also* relocatable,
  so the kernel applies ASLR on every `exec`. This is what makes ROP
  / JOP work hard: the gadget addresses differ on each run. Requires
  musl >= 1.1.20 (rolling-release distros and ubuntu-24.04 are fine).
- `-Wl,-z,noexecstack` — `GNU_STACK` is non-executable.
- `-Wl,-z,relro -Wl,-z,now` — full RELRO + immediate bind: all
  relocations are resolved at load time and the relocatable pages are
  then mapped read-only, so a single arbitrary write cannot be
  escalated to code execution via a GOT overwrite.
- `-Wl,--gc-sections` — combined with `-ffunction-sections
  -fdata-sections`, drops every unreferenced function/datum so the
  shipped binary is exactly the code we use. Smaller TCB.

To verify the shipped binaries actually have these properties, see
`tests/` in each repo and the post-build instructions at the bottom of
`lsh/README.md`. Any build that silently loses a flag (toolchain
downgrade, CFLAGS override) would stop stripping ELF segments in a
detectable way; we could add a `checksec`-style assertion to the CI
boot-smoke job later if drift becomes a concern.

## Requirements

On Ubuntu or Linux Mint:

    sudo apt install wget git make gcc bc bison flex xorriso libelf-dev libssl-dev python3 cpio musl-tools

`musl-tools` supplies `musl-gcc` for static **jvmlab-toybox**. On Arch, install `musl`.

The build does **not** require root.

## Build

Clone and run:

    git clone https://github.com/LilOleByte/jvmlab-build.git
    cd jvmlab-build
    ./minimal.sh

Output: **`minimal.iso`** in the project directory.

### Run in QEMU

    qemu-system-x86_64 -m 512 -cdrom minimal.iso -boot d

The image is intentionally minimal; the kernel may include a network stack, but nothing in userspace brings interfaces up.

## `minimal.sh` options (environment variables)

Optional. Example: `VAR=value ./minimal.sh`.

| Variable | Purpose |
|----------|---------|
| `JOBS` | Parallel `make` jobs. Default: all CPUs (`nproc` / `getconf _NPROCESSORS_ONLN`, else 4). Example: `JOBS=8 ./minimal.sh`. |
| `KERNEL_HARDENING` | `1` (default) applies `configs/x86_64-minimal.config` on top of `defconfig` using `scripts/kconfig/merge_config.sh` + `olddefconfig`. Set to `0` to ship stock defconfig (useful for bisecting a boot regression). See "Kernel hardening profile" below. |
| `JVMLAB_CC` | Compiler for **jvmlab-toybox only** (default `musl-gcc`). The kernel still uses your normal `gcc`. Example: `JVMLAB_CC=cc ./minimal.sh` for glibc userspace. |
| `JVMLAB_TOYBOX_URL` | Git URL for jvmlab-toybox. Default: `https://github.com/LilOleByte/jvmlab-toybox.git`. |
| `JVMLAB_TOYBOX_REF` | Branch, tag, or commit SHA to clone. Default: `main`. Pin to a tag or SHA for archival builds. |
| `JVMLAB_LSH_URL` | Git URL for `lsh`. Unset (default) means "use `LSH_LOCAL`". |
| `JVMLAB_LSH_REF` | Branch, tag, or commit SHA to clone when `JVMLAB_LSH_URL` is set. Default: `main`. |
| `LSH_LOCAL` | Local sibling checkout used when `JVMLAB_LSH_URL` is unset. Default: `../lsh`. |
| `KERNEL_SHA256` | Override the pinned SHA256 for `linux-${KERNEL_VERSION}.tar.xz`. Only needed when bumping `KERNEL_VERSION`; grab the new value from `https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc`. |
| `SYSLINUX_SHA256` | Override the pinned SHA256 for `syslinux-${SYSLINUX_VERSION}.tar.xz`. Source: `https://cdn.kernel.org/pub/linux/utils/boot/syslinux/sha256sums.asc`. |
| `SOURCE_DATE_EPOCH` | Unix timestamp to stamp all build outputs with. Defaults to the commit time of HEAD in this checkout, or `1700000000` if not a git tree. Pin this to make two different checkouts build byte-identical ISOs. |

jvmlab-toybox and `lsh` set their own hardening in their `Makefile`s; adjust `CFLAGS` / `LDFLAGS` there if needed.

The script sets `MAKEFLAGS=-j$JOBS` so jvmlab-toybox, the kernel, and other `make` steps share the same parallelism.

## Cleaning

`./clean.sh` removes extracted sources, the cloned `jvmlab-toybox-src/` tree, generated rootfs, `isoimage/`, and the ISO (paths are relative to the script directory).

| Variable | Purpose |
|----------|---------|
| `KEEP_DOWNLOADS` | If `1`, keeps downloaded tarballs (`kernel.tar.xz`, `syslinux.tar.xz`) and only removes extracted dirs, the clone, `rootfs/`, `isoimage/`, and `*.iso`. Otherwise full clean. Example: `KEEP_DOWNLOADS=1 ./clean.sh`. |

## JVMLAB

Documentation and releases: **[https://jvmlab.org/](https://jvmlab.org/)**.

## License

[BSD Zero Clause License (0BSD)](LICENSE).
