# jvmlab-build

**[JVMLAB.org](https://jvmlab.org/)** — a single-script pipeline that builds a tiny, bootable live Linux ISO (kernel, userspace, ISOLINUX).

This repository holds `minimal.sh`, `clean.sh`, and related tooling.

**jvmlab-toybox** (the static C multicall userspace) is a **separate Git repository**. The build clones it when you run `minimal.sh`; override the URL or ref with `JVMLAB_TOYBOX_URL` and `JVMLAB_TOYBOX_REF` if needed. Source layout in this tree is only for local development if you vendor or symlink a copy.

## What the build does

`minimal.sh` fetches, builds, and assembles:

| Component | Source |
|-----------|--------|
| **Linux** | Longterm 6.18.x from kernel.org |
| **jvmlab-toybox** | Cloned from [LilOleByte/jvmlab-toybox](https://github.com/LilOleByte/jvmlab-toybox) |
| **Syslinux** | 6.03 (stable upstream) |

## Userspace: jvmlab-toybox

The live ISO ships one **static binary** at `/bin/jvmlab-toybox`, with symlinks per applet:

- **`sh`** — minimal shell (quoting, `cd`, `exit`, `$?`, external exec)
- **`ls`**, **`clear`**, **`cat`**, **`echo`**, **`pwd`**, **`mount`**

Why a custom multicall instead of upstream Toybox:

- **Smaller TCB** — only shipped applets; no bundled POSIX surface, setuid, or networking tools.
- **Simple dispatcher** — `main()` maps `basename(argv[0])` to a fixed table; no `setjmp`/`longjmp` or mutable global state that nested shells can corrupt.
- **Easy to review** — one short C file per applet; add a source file and one table entry.

Details: [`jvmlab-toybox/README.md`](jvmlab-toybox/README.md) (present after clone or if you have the repo alongside this tree).

## Requirements

On Ubuntu or Linux Mint:

    sudo apt install wget git make gcc bc bison flex xorriso libelf-dev libssl-dev python3 cpio musl-tools

`musl-tools` supplies `musl-gcc` for static **jvmlab-toybox**. On Arch, install `musl`.

The build does **not** require root.

## Build

From this repository:

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
| `KERNEL_NO_NETWORK` | `1`, `y`, `yes`, or `true` (case-insensitive for the last three) builds the kernel **without** `CONFIG_NET` (smaller `bzImage`). Uses the kernel’s `scripts/config` after `defconfig` (needs Python 3). Example: `KERNEL_NO_NETWORK=1 ./minimal.sh`. |
| `JVMLAB_CC` | Compiler for **jvmlab-toybox only** (default `musl-gcc`). The kernel still uses your normal `gcc`. Example: `JVMLAB_CC=cc ./minimal.sh` for glibc userspace. |
| `JVMLAB_TOYBOX_URL` | Git URL for jvmlab-toybox. Default: `https://github.com/LilOleByte/jvmlab-toybox.git`. |
| `JVMLAB_TOYBOX_REF` | Branch or tag to clone. Default: `main`. Pin for reproducible builds, e.g. `JVMLAB_TOYBOX_REF=v0.1.0 ./minimal.sh`. |

jvmlab-toybox sets its own hardening in its `Makefile`; adjust `CFLAGS` / `LDFLAGS` there if needed.

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
