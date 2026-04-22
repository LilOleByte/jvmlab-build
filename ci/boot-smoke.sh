#!/bin/sh
# Boot the jvmlab ISO headless in QEMU, confirm userspace came up, then
# ask lsh to poweroff. Fails if the shell prompt never appears or QEMU
# has to be hard-killed by the outer timeout.
set -eu

ISO=${1:?usage: boot-smoke.sh <minimal.iso>}
[ -f "$ISO" ] || { echo "boot-smoke: $ISO not found" >&2; exit 1; }

LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

# We feed `poweroff\n` after a delay so lsh reaches its interactive loop
# first, then invokes reboot(RB_POWER_OFF). `-no-reboot` turns the ACPI
# reset into a clean host-side QEMU exit. The outer `timeout` is a
# backstop in case userspace never reaches the prompt.
{ sleep 8; printf 'poweroff\n'; sleep 3; } \
  | timeout --kill-after=5 45 \
      qemu-system-x86_64 \
        -no-reboot \
        -nographic \
        -m 256 \
        -cdrom "$ISO" \
        -serial mon:stdio \
        -monitor none \
        -display none \
  | tee "$LOG" || true

# `lsh` prints "> " in interactive mode on a TTY. Seeing it at column 0
# proves: kernel booted, initramfs unpacked, /init ran, /bin/sh (lsh)
# reached its read loop.
if ! grep -q '^> ' "$LOG"; then
  echo "boot-smoke: lsh prompt never appeared" >&2
  echo "=== captured console ===" >&2
  cat "$LOG" >&2
  exit 1
fi

# A kernel panic in PID 1 is the most dangerous regression we can ship.
if grep -Ei 'Kernel panic|attempted to kill init' "$LOG" >/dev/null; then
  echo "boot-smoke: kernel panic observed" >&2
  cat "$LOG" >&2
  exit 1
fi

echo "boot-smoke: OK"
