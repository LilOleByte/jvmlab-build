# jvmlab-build

Builds the **jvmlab minimal Linux ISO** (kernel + initramfs + ISOLINUX) with a
single script: `./minimal.sh`.

Userspace is two sibling repos:

- **[jvmlab-lsh](https://github.com/LilOleByte/jvmlab-lsh)**: minimal shell that runs as **PID 1** (ships as `/bin/sh`).
- **[jvmlab-toybox](https://github.com/LilOleByte/jvmlab-toybox)**: tiny multicall binary for the non-shell applets.

## Quickstart

```sh
git clone https://github.com/LilOleByte/jvmlab-build.git
cd jvmlab-build
./minimal.sh
```

Output: `minimal.iso` (plus `isoimage/rootfs.gz` and `isoimage/bzImage`).

## Requirements (Ubuntu)

```sh
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  wget git make gcc bc bison flex xorriso libelf-dev libssl-dev python3 cpio musl-tools
```

No root is needed to run the build.

## Run

```sh
qemu-system-x86_64 -m 512 -cdrom minimal.iso -boot d
```

## What’s inside the initramfs

- `/bin/lsh` and `/bin/sh -> lsh`
- `/bin/jvmlab-toybox` with symlinked applets: `ls`, `clear`, `cat`, `echo`, `pwd`, `mount`

See the upstream READMEs for details:
- `https://github.com/LilOleByte/jvmlab-lsh`
- `https://github.com/LilOleByte/jvmlab-toybox`

## Reproducibility & integrity (short)

- Kernel + syslinux tarballs are **SHA256-verified** (pins live in `minimal.sh`).
- Build timestamps are **deterministic** via `SOURCE_DATE_EPOCH`.
- CI uploads the ISO plus `artefact-digests.txt` and `artefact-info.md`.

The security posture and non-goals are documented in `THREAT_MODEL.md`.

## Configuration knobs

Set as environment variables: `VAR=value ./minimal.sh`.

- **`JOBS`**: parallelism for `make` (default: all CPUs).
- **`KERNEL_HARDENING`**: `1` (default) merges `configs/x86_64-minimal.config`; `0` uses stock `defconfig`.
- **`JVMLAB_CC`**: userspace compiler for `jvmlab-lsh` + `jvmlab-toybox` (default: `musl-gcc`).
- **`JVMLAB_LSH_REF` / `JVMLAB_TOYBOX_REF`**: branch/tag/SHA to fetch (default: `main`).
- **`LSH_LOCAL`**: prefer a local sibling checkout (default probes `../jvmlab-lsh`, then `../lsh`).
- **`SOURCE_DATE_EPOCH`**: override deterministic timestamp (defaults to git commit time).

## Cleaning

`./clean.sh` removes extracted sources, cloned trees, `rootfs/`, `isoimage/`, and `minimal.iso`.

## License

[BSD Zero Clause License (0BSD)](LICENSE). See `LICENSES.md` for third-party component licences.
