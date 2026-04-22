#!/bin/sh
set -eu

if [ "${DEBUG:-0}" = "1" ]; then
  set -x
fi

die() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

# All paths are relative to the directory this script lives in.
SCRIPT_DIR=$(
  CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P
) || exit 1

# Parallel make (override: `JOBS=4 ./minimal.sh`).
JOBS=${JOBS:-$(
  nproc 2>/dev/null ||
    getconf _NPROCESSORS_ONLN 2>/dev/null ||
    printf '%s\n' 4
)}
export MAKEFLAGS="-j${JOBS}"

# Versions.
KERNEL_VERSION=${KERNEL_VERSION:-6.18.23}
SYSLINUX_VERSION=${SYSLINUX_VERSION:-6.03}

# Authoritative SHA256 checksums for the upstream tarballs. Source:
# https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc
# https://cdn.kernel.org/pub/linux/utils/boot/syslinux/sha256sums.asc
# (both signed by kernel.org). Override when bumping versions.
KERNEL_SHA256=${KERNEL_SHA256:-2a2d8e76bfcd135ab861bb9795211574eeff6d4ede9cc920f7c137587e835134}
SYSLINUX_SHA256=${SYSLINUX_SHA256:-26d3986d2bea109d5dc0e4f8c4822a459276cf021125e8c9f23c3cca5d8c850e}

# Reproducibility: timestamps in cpio/gzip/ISO/kernel are derived from
# SOURCE_DATE_EPOCH. Defaults to the commit time of HEAD when this is a
# git checkout, else a fixed documented epoch (2023-11-14 22:13:20 UTC).
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(git -C "$SCRIPT_DIR" log -1 --format=%ct 2>/dev/null || printf '1700000000')
fi
export SOURCE_DATE_EPOCH
KBUILD_BUILD_TIMESTAMP=$(date -u -d "@${SOURCE_DATE_EPOCH}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || printf '2023-11-14 22:13:20 UTC')
export KBUILD_BUILD_TIMESTAMP
export KBUILD_BUILD_USER=jvmlab
export KBUILD_BUILD_HOST=jvmlab

# `jvmlab-toybox` source selection.
JVMLAB_TOYBOX_URL=${JVMLAB_TOYBOX_URL:-https://github.com/LilOleByte/jvmlab-toybox.git}
JVMLAB_TOYBOX_REF=${JVMLAB_TOYBOX_REF:-main}
JVMLAB_TOYBOX_DIR="${SCRIPT_DIR}/jvmlab-toybox-src"

# `lsh` source selection. `lsh` ships as /bin/sh on the ISO. By default the
# build uses a local sibling checkout at ../lsh (override with LSH_LOCAL).
# Set JVMLAB_LSH_URL to clone instead.
JVMLAB_LSH_URL=${JVMLAB_LSH_URL:-}
JVMLAB_LSH_REF=${JVMLAB_LSH_REF:-main}
JVMLAB_LSH_DIR="${SCRIPT_DIR}/lsh-src"
LSH_LOCAL=${LSH_LOCAL:-${SCRIPT_DIR}/../lsh}

# Userspace is built with musl by default (static, small). Only passed to jvmlab-toybox
# and lsh make — do not export CC here or the kernel build may pick it up.
JVMLAB_CC=${JVMLAB_CC:-musl-gcc}

ISO_DIR="${SCRIPT_DIR}/isoimage"
ROOTFS_DIR="${SCRIPT_DIR}/rootfs"
OUT_ISO="${SCRIPT_DIR}/minimal.iso"

# Download-and-verify. A cached tarball that still matches the pinned
# checksum is reused; a mismatch is loud and fatal (integrity before
# convenience).
fetch() {
  out=$1
  url=$2
  expected=$3
  if [ -f "$out" ]; then
    actual=$(sha256sum "$out" | awk '{print $1}')
    if [ "$actual" = "$expected" ]; then
      printf 'fetch: %s: cached, sha256 ok\n' "$out"
      return 0
    fi
    printf 'fetch: %s: checksum mismatch, re-downloading\n' "$out" >&2
    rm -f "$out"
  fi
  wget -O "$out" "$url"
  actual=$(sha256sum "$out" | awk '{print $1}')
  [ "$actual" = "$expected" ] || die "sha256 mismatch for $out: expected $expected, got $actual"
  printf 'fetch: %s: sha256 ok\n' "$out"
}

fetch kernel.tar.xz \
  "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz" \
  "$KERNEL_SHA256"
fetch syslinux.tar.xz \
  "https://cdn.kernel.org/pub/linux/utils/boot/syslinux/syslinux-${SYSLINUX_VERSION}.tar.xz" \
  "$SYSLINUX_SHA256"

rm -rf "${SCRIPT_DIR}/linux-${KERNEL_VERSION}" "${SCRIPT_DIR}/syslinux-${SYSLINUX_VERSION}"
tar -xf kernel.tar.xz
tar -xf syslinux.tar.xz

rm -rf "$JVMLAB_TOYBOX_DIR"
git clone --depth 1 --branch "$JVMLAB_TOYBOX_REF" "$JVMLAB_TOYBOX_URL" "$JVMLAB_TOYBOX_DIR"

# Resolve lsh source: clone if URL given, else use the local sibling tree.
if [ -n "$JVMLAB_LSH_URL" ]; then
  rm -rf "$JVMLAB_LSH_DIR"
  git clone --depth 1 --branch "$JVMLAB_LSH_REF" "$JVMLAB_LSH_URL" "$JVMLAB_LSH_DIR"
  LSH_BUILD_DIR="$JVMLAB_LSH_DIR"
else
  [ -d "$LSH_LOCAL" ] || die "no lsh source: set JVMLAB_LSH_URL or place lsh at $LSH_LOCAL"
  LSH_BUILD_DIR="$LSH_LOCAL"
fi

mkdir -p "$ISO_DIR"

command -v "$JVMLAB_CC" >/dev/null 2>&1 || die "need '${JVMLAB_CC}' for jvmlab-toybox and lsh (e.g. pacman -S musl, or apt install musl-tools)"
make -C "$JVMLAB_TOYBOX_DIR" "CC=${JVMLAB_CC}"
make -C "$LSH_BUILD_DIR" clean
make -C "$LSH_BUILD_DIR" "CC=${JVMLAB_CC}"

rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR/bin" "$ROOTFS_DIR/dev" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys"
install -m 0755 "$JVMLAB_TOYBOX_DIR/jvmlab-toybox" "$ROOTFS_DIR/bin/jvmlab-toybox"
# `sh` is lsh, installed below. jvmlab-toybox supplies the other applets.
for applet in ls clear cat echo pwd mount; do
  ln -sf jvmlab-toybox "$ROOTFS_DIR/bin/$applet"
done
install -m 0755 "$LSH_BUILD_DIR/lsh" "$ROOTFS_DIR/bin/lsh"
ln -sf lsh "$ROOTFS_DIR/bin/sh"

# /init is run by lsh in script mode (since /bin/sh -> lsh). lsh sets
# PATH=/bin itself and, when PID 1, execs an interactive /bin/sh after the
# script finishes, so no `export` / `exec` builtins are needed here.
cat >"$ROOTFS_DIR/init" <<'EOF'
#!/bin/sh
/bin/mount devtmpfs /dev devtmpfs
/bin/mount proc /proc proc
/bin/mount sysfs /sys sysfs
EOF
chmod +x "$ROOTFS_DIR/init"

# Reproducible initramfs: stamp every file's mtime to SOURCE_DATE_EPOCH,
# feed cpio a locale-stable sorted list, force root:root ownership, use
# cpio --reproducible (renumbered inodes, zeroed devno), and gzip -n to
# drop the gzip header timestamp+filename. Result is byte-identical
# across hosts for a given source tree.
( cd "$ROOTFS_DIR" \
  && find . -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} + \
  && find . -print0 \
     | LC_ALL=C sort -z \
     | cpio --null --reproducible -R root:root -H newc -o 2>/dev/null \
     | gzip -n -9 > "${ISO_DIR}/rootfs.gz" )

cd "${SCRIPT_DIR}/linux-${KERNEL_VERSION}" || die "missing kernel tree"
make mrproper defconfig

# Apply the jvmlab hardening fragment: attack-surface reduction
# (CONFIG_NET/MODULES/BPF/... off) plus kernel self-protection knobs.
# See ../configs/x86_64-minimal.config for the per-flag rationale.
# `merge_config.sh -m` merges onto the existing .config; the trailing
# `make olddefconfig` propagates consequences (everything gated on
# disabled subsystems collapses automatically). Set KERNEL_HARDENING=0
# to build stock defconfig (useful for bisecting a boot regression).
KCONFIG_FRAGMENT="${SCRIPT_DIR}/configs/x86_64-minimal.config"
if [ "${KERNEL_HARDENING:-1}" = "1" ]; then
  [ -f "$KCONFIG_FRAGMENT" ] || die "missing kconfig fragment: $KCONFIG_FRAGMENT"
  ./scripts/kconfig/merge_config.sh -m .config "$KCONFIG_FRAGMENT"
  make olddefconfig
else
  printf 'minimal.sh: KERNEL_HARDENING=0, shipping stock defconfig\n' >&2
fi
make bzImage
cp arch/x86/boot/bzImage "${ISO_DIR}/bzImage"

cd "$ISO_DIR" || die "missing iso dir"
cp "${SCRIPT_DIR}/syslinux-${SYSLINUX_VERSION}/bios/core/isolinux.bin" .
cp "${SCRIPT_DIR}/syslinux-${SYSLINUX_VERSION}/bios/com32/elflink/ldlinux/ldlinux.c32" .

# Kernel command line hardening:
#   panic=10              -- auto-reboot 10s after a panic (appliance
#                            isn't watched by a human).
#   oops=panic            -- escalate any oops to a panic rather than
#                            letting the kernel continue in an
#                            undefined state.
#   page_alloc.shuffle=1  -- randomise the page allocator freelist.
#   vsyscall=none         -- refuse all vsyscall accesses (defence in
#                            depth alongside CONFIG_X86_VSYSCALL_EMULATION=n).
#   slab_nomerge          -- keep slab caches distinct so cross-cache
#                            attacks cannot reuse a type-confused chunk.
cat >./isolinux.cfg <<'EOF'
DEFAULT linux
TIMEOUT 0
PROMPT 0
LABEL linux
  KERNEL bzImage
  APPEND initrd=rootfs.gz panic=10 oops=panic page_alloc.shuffle=1 vsyscall=none slab_nomerge
EOF

# Reproducible ISO: stamp staging contents and pin the volume id.
# xorriso 1.4.8+ honours SOURCE_DATE_EPOCH on its own (it prints a NOTE
# at startup when it picks the env var up), so we don't pass an
# explicit modification-date here -- that flag is spelled differently
# across xorriso versions and emulation modes and just causes trouble.
find "$ISO_DIR" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
xorriso \
  -as mkisofs \
  -volid JVMLAB \
  -o "$OUT_ISO" \
  -b isolinux.bin \
  -c boot.cat \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  ./

printf '\n== build complete ==\n'
sha256sum "$OUT_ISO" "${ISO_DIR}/rootfs.gz" "${ISO_DIR}/bzImage"
