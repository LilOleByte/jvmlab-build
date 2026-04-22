# Third-party components shipped in the jvmlab ISO

This file is the lightweight SBOM for the artefacts produced by `minimal.sh`.
Every component fetched or linked into the ISO is listed with its pinned
version, upstream URL, authoritative checksum or git ref, and licence. Bump
versions here *and* in `minimal.sh`/the build system at the same time.

Checksums for upstream tarballs are sourced from the signed
`sha256sums.asc` files published by kernel.org.

## Linux kernel

- Version: `6.18.23`
- URL: https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.18.23.tar.xz
- SHA256: `2a2d8e76bfcd135ab861bb9795211574eeff6d4ede9cc920f7c137587e835134`
- Checksum source: https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc
- Licence: GPL-2.0-only with the syscall-boundary exception (see `COPYING`
  in the source tree).
- Shipped as: `isoimage/bzImage` inside `minimal.iso`.
- Build config: `make defconfig` + the `configs/x86_64-minimal.config`
  fragment (merged via `scripts/kconfig/merge_config.sh`) +
  `make olddefconfig`. See the README section "Kernel hardening
  profile" for the flag list and rationale.

## SYSLINUX (isolinux BIOS bootloader)

- Version: `6.03`
- URL: https://cdn.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
- SHA256: `26d3986d2bea109d5dc0e4f8c4822a459276cf021125e8c9f23c3cca5d8c850e`
- Checksum source: https://cdn.kernel.org/pub/linux/utils/boot/syslinux/sha256sums.asc
- Licence: GPL-2.0-or-later.
- Shipped as: `isolinux.bin` and `ldlinux.c32` inside `minimal.iso`.

## jvmlab-toybox

- Upstream: https://github.com/LilOleByte/jvmlab-toybox
- Pinned ref: `main` (to be moved to a signed tag for release builds;
  see "Pinning strategy" in `README.md`).
- Licence: see `LICENSE` in the upstream repository.
- Shipped as: `/bin/jvmlab-toybox` (plus the `ls`, `cat`, `echo`, `pwd`,
  `mount`, `clear` symlinks) inside the initramfs.

## jvmlab-lsh

- Upstream: https://github.com/LilOleByte/jvmlab-lsh (or sibling checkout
  at `../jvmlab-lsh` / `../lsh`; see `LSH_LOCAL` / `JVMLAB_LSH_URL` in
  `minimal.sh`).
- Pinned ref: `main` (to be moved to a signed tag for release builds).
- Licence: 0BSD — a derivative of Stephen Brennan's original `lsh`
  (released under the Unlicense, which explicitly permits relicensing
  of derivatives). See `LICENSE` in the upstream repository for the
  full text and attribution.
- Shipped as: `/bin/lsh` and the `/bin/sh` symlink inside the initramfs.
  Runs as PID 1.

## Build-time dependencies (not shipped)

These live on the build host only; they never end up inside the ISO.

| Tool       | Purpose                                           |
|------------|---------------------------------------------------|
| `musl-gcc` | Static C toolchain used for jvmlab-toybox / jvmlab-lsh. |
| `gcc`      | Host toolchain used to build the kernel.          |
| `wget`     | Fetch upstream tarballs.                          |
| `tar`      | Extract upstream tarballs.                        |
| `cpio`     | Pack the initramfs (GNU cpio >= 2.12 required for `--reproducible`). |
| `gzip`     | Compress the initramfs.                           |
| `xorriso`  | Build the bootable ISO.                           |
| `git`      | Clone `jvmlab-toybox` / `jvmlab-lsh` when not using a local checkout. |

## Pinning strategy for the userspace refs

`jvmlab-toybox` and `jvmlab-lsh` are still tracked at `main` while the feature
set stabilises. Before cutting a release:

1. Tag each repository with a signed tag, e.g. `v0.1.0`.
2. Update the defaults of `JVMLAB_TOYBOX_REF` and `JVMLAB_LSH_REF` in
   `minimal.sh` to point at that tag.
3. Record the commit SHAs in this file alongside the tags so a cold
   rebuild can be verified without GitHub.

Until those tags exist, set `JVMLAB_TOYBOX_REF` / `JVMLAB_LSH_REF` to an
explicit commit SHA on the command line for any build that needs to be
archived or audited.
