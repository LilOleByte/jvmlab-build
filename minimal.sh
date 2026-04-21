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

# `jvmlab-toybox` source selection.
JVMLAB_TOYBOX_URL=${JVMLAB_TOYBOX_URL:-https://github.com/LilOleByte/jvmlab-toybox.git}
JVMLAB_TOYBOX_REF=${JVMLAB_TOYBOX_REF:-main}
JVMLAB_TOYBOX_DIR="${SCRIPT_DIR}/jvmlab-toybox-src"
# Userspace is built with musl by default (static, small). Only passed to jvmlab-toybox
# make — do not export CC here or the kernel build may pick it up.
JVMLAB_CC=${JVMLAB_CC:-musl-gcc}

ISO_DIR="${SCRIPT_DIR}/isoimage"
ROOTFS_DIR="${SCRIPT_DIR}/rootfs"
OUT_ISO="${SCRIPT_DIR}/minimal.iso"

fetch() {
  out=$1
  url=$2
  wget -O "$out" "$url"
}

fetch kernel.tar.xz "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
fetch syslinux.tar.xz "https://cdn.kernel.org/pub/linux/utils/boot/syslinux/syslinux-${SYSLINUX_VERSION}.tar.xz"

rm -rf "${SCRIPT_DIR}/linux-${KERNEL_VERSION}" "${SCRIPT_DIR}/syslinux-${SYSLINUX_VERSION}"
tar -xf kernel.tar.xz
tar -xf syslinux.tar.xz

rm -rf "$JVMLAB_TOYBOX_DIR"
git clone --depth 1 --branch "$JVMLAB_TOYBOX_REF" "$JVMLAB_TOYBOX_URL" "$JVMLAB_TOYBOX_DIR"

mkdir -p "$ISO_DIR"

command -v "$JVMLAB_CC" >/dev/null 2>&1 || die "need '${JVMLAB_CC}' for jvmlab-toybox (e.g. pacman -S musl, or apt install musl-tools)"
make -C "$JVMLAB_TOYBOX_DIR" "CC=${JVMLAB_CC}"

rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR/bin" "$ROOTFS_DIR/dev" "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys"
install -m 0755 "$JVMLAB_TOYBOX_DIR/jvmlab-toybox" "$ROOTFS_DIR/bin/jvmlab-toybox"
for applet in sh ls clear cat echo pwd mount; do
  ln -sf jvmlab-toybox "$ROOTFS_DIR/bin/$applet"
done

cat >"$ROOTFS_DIR/init" <<'EOF'
#!/bin/sh
/bin/mount devtmpfs /dev devtmpfs
/bin/mount proc /proc proc
/bin/mount sysfs /sys sysfs
exec /bin/sh
EOF
chmod +x "$ROOTFS_DIR/init"

( cd "$ROOTFS_DIR" && find . | cpio -R root:root -H newc -o | gzip > "${ISO_DIR}/rootfs.gz" )

cd "${SCRIPT_DIR}/linux-${KERNEL_VERSION}" || die "missing kernel tree"
make mrproper defconfig
case ${KERNEL_NO_NETWORK:-0} in
  1 | y | Y | yes | YES | true | TRUE)
    ./scripts/config --disable NET
    make olddefconfig
    ;;
esac
make bzImage
cp arch/x86/boot/bzImage "${ISO_DIR}/bzImage"

cd "$ISO_DIR" || die "missing iso dir"
cp "${SCRIPT_DIR}/syslinux-${SYSLINUX_VERSION}/bios/core/isolinux.bin" .
cp "${SCRIPT_DIR}/syslinux-${SYSLINUX_VERSION}/bios/com32/elflink/ldlinux/ldlinux.c32" .

cat >./isolinux.cfg <<'EOF'
DEFAULT linux
TIMEOUT 0
PROMPT 0
LABEL linux
  KERNEL bzImage
  APPEND initrd=rootfs.gz
EOF

xorriso \
  -as mkisofs \
  -o "$OUT_ISO" \
  -b isolinux.bin \
  -c boot.cat \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  ./
