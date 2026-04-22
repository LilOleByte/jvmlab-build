# jvmlab threat model

This document exists so every future security-relevant decision in
`jvmlab-build`, `lsh`, and `jvmlab-toybox` can be judged against a
stated rubric. It is deliberately short. Every defence below is
traced to a file or commit; every non-goal is stated out loud so a
reader cannot accidentally assume protection we never promised.

Audience: a student who wants to know *what* the appliance protects,
an auditor who wants to know *how*, and a future maintainer who wants
to know *why* a given flag exists.

## 1. What the appliance is

- A single bootable ISO: BIOS bootloader (ISOLINUX), a monolithic
  Linux kernel, a gzipped cpio initramfs containing one shell (`lsh`,
  PID 1) and one multicall binary (`jvmlab-toybox`) with a small
  applet set.
- Runs on x86_64 hardware or in a VM. No network brought up; no
  persistent storage written; no multi-user support.
- Purpose: teach Linux internals and secure-systems engineering by
  being short enough to read end-to-end. Everything that could be
  left out, is.

## 2. Assets we protect

| # | Asset | Why it matters |
|---|-------|----------------|
| A1 | **Integrity of the shipped ISO** | A user who downloaded `minimal.iso` should be able to prove they are running the exact bytes CI built. |
| A2 | **Integrity of the build recipe** | A reader should be able to rebuild from source and obtain the same bytes. Drift here breaks A1. |
| A3 | **Runtime integrity of the kernel** | A local bug or a malicious device should not be able to take full control of the running system. |
| A4 | **Runtime integrity of userspace** | A bug in `lsh` or `jvmlab-toybox` should not be turnable into arbitrary code execution at the same privilege. |
| A5 | **Code transparency** | Every binary in the ISO has an upstream we can name, pin, and audit. |

Assets we explicitly do **not** protect: confidentiality of on-disk
data (there is none), confidentiality of kernel memory against a
privileged user (the appliance has no privilege boundary), anything
that would require a DRM-style model.

## 3. Actors and their capabilities

| # | Actor | Capability |
|---|-------|------------|
| T1 | **Curious reader / student** | Source access. Runs the ISO in QEMU. |
| T2 | **Auditor** | Same as T1 plus intent to verify claims. |
| T3 | **Local console user** | Runs the ISO on real hardware; can type arbitrary input; can plug in removable media. |
| T4 | **In-transit tamperer** | Substitutes a different `minimal.iso` between CI's release page and the user (e.g., compromised mirror, MITM on HTTP). |
| T5 | **Upstream mirror compromise** | Replaces `linux-6.18.23.tar.xz` or `syslinux-6.03.tar.xz` on `cdn.kernel.org` or a CI-reachable mirror with a tampered tarball. |
| T6 | **Upstream repo compromise** | Pushes a malicious commit to `LilOleByte/jvmlab-toybox` or `LilOleByte/jvmlab-lsh` upstream. |
| T7 | **Compromised build host** | Runs the build with a backdoored `gcc`, `musl-gcc`, or `xorriso`. |
| T8 | **Physical attacker** | DMA, DRAM probes, JTAG, flash reprogramming. Full hardware access. |

## 4. Threats and current defences

Each threat is numbered; the "Defence" column points at the file
and/or phase where the mitigation lives. Phases are from the
development roadmap (Phase 1 = supply chain, Phase 2 = kernel,
Phase 3.1 = userspace, Phase 3.2 = verifiable boot).

| # | Threat | Assets | Defence | Status |
|---|--------|--------|---------|--------|
| Th-1 | User can't verify the ISO matches CI's build. | A1 | CI publishes SHA256 of `minimal.iso`, `rootfs.gz`, `bzImage` on every build (`minimal.sh` prints them on completion; CI uploads `artefact-digests.txt`). | In place (Phase 1). |
| Th-2 | Two fresh checkouts produce different ISOs. | A2 | `SOURCE_DATE_EPOCH` + sorted + `root:root` + `cpio --reproducible` + `gzip -n` for the initramfs; xorriso honours `SOURCE_DATE_EPOCH` for the ISO; `KBUILD_BUILD_*` pinned for the kernel. CI publishes SHA256 digests on every build; anyone can rebuild locally at the same commit / `SOURCE_DATE_EPOCH` and compare. | In place (Phase 1). |
| Th-3 | Tampered kernel or syslinux tarball on the build host. | A2 | SHA256 of both tarballs pinned in `minimal.sh`; values sourced from kernel.org's signed `sha256sums.asc`; `fetch()` aborts on mismatch. | In place (Phase 1). |
| Th-4 | Tampered `jvmlab-toybox` or `jvmlab-lsh` source. | A2 | Git refs pinned via `JVMLAB_TOYBOX_REF` / `JVMLAB_LSH_REF`; for release builds the pin is a commit SHA. Full plan documented in `LICENSES.md` ("Pinning strategy"). | Partial — currently tracks `main`; moving refs to signed tags is tracked as a Phase 1 follow-up. |
| Th-5 | A local bug in the kernel is exploited from userspace. | A3 | Attack-surface fragment (`configs/x86_64-minimal.config`) removes `CONFIG_NET`, `CONFIG_MODULES`, `CONFIG_USER_NS`, `CONFIG_IO_URING`, `CONFIG_BPF_SYSCALL`, `CONFIG_KPROBES/UPROBES`, `CONFIG_DEVMEM/DEVPORT`, `CONFIG_MAGIC_SYSRQ`, legacy syscall paths. Self-protection enables KASLR, stack canaries, `HARDENED_USERCOPY`, `INIT_ON_ALLOC/FREE`, `INIT_STACK_ALL_ZERO`, `SLAB_FREELIST_HARDENED`, `STRICT_KERNEL_RWX`, `SECURITY_YAMA`, `SECURITY_DMESG_RESTRICT`. | In place (Phase 2). |
| Th-6 | Kernel oops leaves the system in an undefined state. | A3 | Kernel command line: `oops=panic panic=10`. | In place (Phase 2). |
| Th-7 | A memory-safety bug in `jvmlab-lsh` or `jvmlab-toybox` is turned into code execution. | A4 | Userspace built with `-fcf-protection=full` (Intel CET), `-fstack-protector-strong`, `-fstack-clash-protection`, `-ftrivial-auto-var-init=zero`, `-D_FORTIFY_SOURCE=2`, `-static-pie` (ASLR), `-Wl,-z,relro -Wl,-z,now`, `-Wl,-z,noexecstack`. Format-string injection refused at compile time. | In place (Phase 3.1). |
| Th-8 | An attacker substitutes `minimal.iso` in transit. | A1 | Currently: user must verify the published SHA256 out-of-band (visible on the CI run summary). | Partial. Closes fully with Th-9. |
| Th-9 | User runs a wrong-but-plausibly-signed ISO. | A1 | Planned: sign the ISO + kernel image with a project key; publish the public key alongside the recipe; document how to verify. | **Not in place yet — Phase 3.2.** |
| Th-10 | Malicious firmware / DMA device tampers with the running kernel at boot. | A3 | Planned: Secure Boot chain, `efi_stub` kernel, or a shim that verifies the kernel signature before jumping. Today nothing stops this. | **Not in place yet — Phase 3.2.** |
| Th-11 | The build host is backdoored (T7). | A2, A4 | Partial: reproducible builds mean two independent builders can compare SHAs and notice a divergence. No full defence (a truly compromised toolchain can backdoor both). Mitigation direction: publish builds from two independent CI providers and diff. | Partial (reproducibility gives us the primitive). |
| Th-12 | A local user gets root and tries to persist. | A3 | No writable root; initramfs lives in tmpfs; rebooting restores pristine state. `CONFIG_MODULES=n` blocks LKM persistence paths. | In place (design). |

## 5. Explicit non-goals

These are not defended against, and a reader should not assume they
are. Each is called out here so "the docs implied…" arguments are
impossible.

- **Physical tampering (T8).** DRAM probes, JTAG, direct flash
  rewrites, evil-maid attacks on the disk holding the ISO. If the
  attacker owns the hardware, the appliance does not pretend to stop
  them. Threats gated on physical access are not in scope.
- **Confidentiality of data at rest.** The appliance has no
  persistent storage by design; protecting bytes that do not exist is
  not a goal.
- **Sandboxing between applications.** There is only PID 1 and its
  children. No containers, no users, no capabilities split. A bug in
  `lsh` and a bug in `jvmlab-toybox` share one privilege level.
- **Post-boot kernel live-patching.** Blocked by `CONFIG_MODULES=n`;
  to patch, you rebuild and reboot. Not a gap — a design choice.
- **Network-based attackers.** The stack is compiled out (`CONFIG_NET=n`).
  Nothing in the appliance talks to the network. If a downstream fork
  re-enables `CONFIG_NET`, the entire network portion of the threat
  model must be re-derived.
- **Users escalating past the kernel.** We reduce exploitability; we
  don't claim unexploitability. Zero-days in the retained kernel
  surface (filesystems, devtmpfs, VM, syscall entry) remain possible.

## 6. Validation checklist

A maintainer can convince themselves this model is real by running,
in order:

1. `./minimal.sh` locally. Last line prints SHA256 triplet.
2. Compare those SHAs to the CI run that built the same commit
   (job summary + `artefact-digests.txt` inside the uploaded
   artifact). They must match byte-for-byte when `SOURCE_DATE_EPOCH`
   matches.
3. Rebuild the same commit a second time locally (or on a second
   machine) and diff the digests. Mismatch = unreproducibility bug,
   open an issue before trusting the ISO.
4. Against the installed binaries:
   `file jvmlab-lsh/lsh jvmlab-toybox/jvmlab-toybox` reports
   `ELF 64-bit LSB pie executable ... statically linked`.
5. `readelf -d` on each binary shows `BIND_NOW` in `FLAGS_1` (full
   RELRO).
6. `readelf -l` on each shows `GNU_STACK` is `RW ` (no `E`).
7. In QEMU: boot the ISO, confirm `cat /proc/1/comm` reports `lsh`.
   `cat /proc/1/status | grep -i cap` shows a fully privileged PID 1
   (expected: single-user appliance, no capability split claimed).
8. In the kernel: `zgrep '^CONFIG_MODULES' /proc/config.gz`
   returns nothing (because the config is not exposed; the point is
   that `modprobe` does not exist in the image and `finit_module(2)`
   returns `-ENOSYS`). Alternative: `strace -e finit_module /bin/sh -c :`
   from a debug build shows the syscall is unavailable.

## 7. When to revise this document

- Any time a `CONFIG_` flag in `configs/x86_64-minimal.config` is
  added, removed, or flipped: update Th-5 and re-run step 7.
- Any time a toolchain flag in `jvmlab-lsh/Makefile` or
  `jvmlab-toybox/Makefile` changes: update Th-7.
- Any time the ISO gains a new component (second binary, a config
  file, a data blob): add a row to the asset table and decide which
  threat class it falls under before shipping.
- When Phase 3.2 lands: Th-8, Th-9, Th-10 move from "partial /
  planned" to "in place", and the signing-key custody becomes a new
  asset (A6) with its own row here.
