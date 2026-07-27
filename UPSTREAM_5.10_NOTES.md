# Mi 11 Ultra (star / sm8350) — real Linux 5.10.261 port (branch `5.10.261`)

**Status: EXPERIMENTAL / for testing. Expect build fixups needed; boot untested.**

## What this branch is
- Base: `ASB-2024-10-05` = Linux **5.4.283** (CAF msm-5.4 + Xiaomi + EndCredits)
- Merged: Google ACK `android12-5.10-lts` = **Linux 5.10.260** (GKI/android12)
- Then merged: kernel.org tag **v5.10.261** (newest 5.10 ever released; 5.10 EOL Dec 2026)
- `make kernelversion` → **5.10.261** — real 5.10, not an edited Makefile.

## How it differs from the old `5.10.257` branch
The old branch was made from a history-less snapshot (`--allow-unrelated-histories`,
28,255 add/add conflicts, everything nuked to Google's side). This branch is a TRUE
3-way merge — the clone has full history and shares the android-mainline ancestor
`54e301676a79` with ACK, so git auto-merged everything except 5,866 files:
- 4,992 resolved to 5.10 (our side only had 5.4.y-stable/ACK backports already in 5.10.260)
- 874 vendor-touched files hand-resolved (36 subagent batches + doctrine):
  5.10 base with CAF/Qualcomm/Xiaomi hunks re-applied, or CAF stacks kept wholesale
  where the vendor ecosystem depends on them (qcom clk framework, SCM, UFS, sdhci-msm,
  dwc3+dwc3-msm, glink, rpmh/cmd-db/socinfo/smp2p, icc-rpmh, io-pgtable-arm,
  qcom-cpufreq-hw, qcom-pdc, WALT scheduler, iommu fastmap stack).

## Preserved device-critical pieces (verified present)
techpack/ (incl. camera_star, bootinfo) wired into build; star/lahaina DTS under
arch/arm64/boot/dts/vendor/qcom; star/lahaina QGKI defconfigs; qcacld-3.0;
kernel/sched/walt + hooks in core/fair/rt/schedutil; ION/msm_dma_iommu; minidump;
Xiaomi charger/thermal/touch/misc/mi-reclaim; GitHub Actions workflows (KernelSU is
injected by the workflows at build time — the 5.4 tree never had inline ksu hooks).

## Build-fix status (2026-07-26)
Around 30 follow-up commits took the tree from "fails at kconfig" to compiling ~770 C files.
The important ones were not compile errors but silent boot-breakers:
- `scripts/Makefile.dtbo` used the deprecated `always` variable, so **no dtb/dtbo was built
  at all** and mkdtboimg produced an empty image.
- mainline `arm-smmu` has no `qcom,qsmmu-v500`, the compatible both lahaina SMMUs use, so
  `apps_smmu` would never have probed and all 30 consumers would sit in -EPROBE_DEFER.
- 5.10's `icc_node_add()` performs an initial hardware sync; the CAF 5.4 RPMh providers were
  not written for that and would have pushed INT_MAX bandwidth votes into DDR/GEM/MMSS.
- `qcom_pdc_gic_set_type()` dereferenced `d->parent_data` before the GPIO_NO_WAKE_IRQ check.
- The merge had lost a closing brace in `__sched_setscheduler()`.

Subsystems re-based on Qualcomm's own msm-5.10 (`clo/kernel.lnx.5.10.r7-rel`, which is itself
android12-5.10): UFS core from ACK + vendor driver/PHY from CLO; clk/regulator/interconnect
ported surgically; iommu/pinctrl/pdc/glink ported; display, camera, audio and touch moved off
`struct timeval`/`getnstimeofday` (both removed for kernel code in 5.10).

## Known follow-ups for CI build (expected errors)
- CAF leaf drivers kept wholesale still call some 5.4-era APIs (keyslot-manager in
  ufshcd-crypto/cqhci-crypto-qti, coresight byte-cntr/csr vs 5.10 coresight-core,
  sdhci-msm vs 5.10 sdhci, dwc3-msm vs auto-merged drd.c) — fix as compiler reports.
- coresight_disable_all_source_link/enable_all_source_link declared but the 5.10
  coresight-core.c doesn't implement them (CAF tmc-etr/etf call them).
- crypto-qti-common.h still includes removed linux/bio-crypt-ctx.h.
- mm/kasan/shadow.c lacks the 5.4 vendor __GFP_ZERO hotplug hunk (KASAN-only).
- Degraded on purpose: coresight `*_all_source_link` are no-ops (5.10 removed the machinery),
  SMMU "fastmap" is inert and CAF SMMU domain attrs (ATOS, secure VMID, dynamic domains) are
  gone with mainline arm-smmu, so camera/display/kgsl lose those optimisations but still probe.
- Dropped (deliberate): QCOM_INITIAL_LOGBUF (incompatible with 5.10 printk ringbuffer),
  CAF energy_model debugfs (superseded), CAF arm32 IOMMU-DMA rework (arm64 device),
  wil6210 CAF fork (CONFIG_WIL6210 not set for star), vendor exfat 6.0 (5.10 GKI exfat used).
- Renumbered to avoid 5.10 collisions: VM_LOWMEM 0x400, FAULT_FLAG_PREFAULT_OLD 0x800,
  DMA_ATTR_FORCE_(NON_)COHERENT bits 18/19, IOMMU_USE_UPSTREAM_HINT/LLC_NWA bits 8/9,
  IO_PGTABLE quirk bits 6/7, BPF_SOCK_OPS_VOIP_CB appended after 5.10 callbacks.

## Second build-fix phase (2026-07-27)
CI progress is measured in compiled objects: 770 -> 2400 -> 3388 and climbing. Most of the
remaining work was not conflict resolution but genuine 5.4 -> 5.10 API drift in vendor code.
The errors were found faster by *predicting* them than by waiting for 25-minute CI rounds:
`git archive` the 5.4 base's include/ to a temp tree, diff it against the working tree for
(a) symbols declared then but not now, (b) prototypes whose argument count changed,
(c) struct members removed, (d) macros and enum constants removed, (e) ops-table callback
signatures - then intersect each with what the vendor trees actually call or initialise.

Larger items in this phase:
- ASoC: 5.10 dissolved `struct snd_pcm_ops` into `snd_soc_component_driver`, with the
  component passed as a new first argument to every callback; `pcm_new`/`pcm_free` became
  `pcm_construct`/`pcm_destruct`. Twelve techpack/audio drivers converted. There is no
  `compat_ioctl` member any more and soc-pcm never wires one up, so the LSM drivers' 32-bit
  ioctl paths are gone (SNDRV_LSM_* from 32-bit userspace returns -ENOIOCTLCMD).
  Compressed audio is the same change: `snd_compr_ops` -> const `snd_compress_ops`.
- crypto: `drivers/crypto/msm` still registered ciphers through the ablkcipher interface that
  5.5 deleted. Every file there was byte-identical to the 5.4 CAF original, so the whole
  directory was replaced with CLO msm-5.10's, i.e. Qualcomm's own skcipher port.
- SCMI: 5.10 made protocols self-contained (transfers through the protocol handle's xops,
  `struct scmi_protocol` registration, consumers asking the handle for ops). The QTI memlat
  and PLH vendor protocols and their consumers were ported to that shape; `memlat_ops` and
  `plh_ops` are gone from `struct scmi_handle`.
- debugfs: 5.10 made `debugfs_create_u32()` and friends return void, but around sixty vendor
  files still assign and error-check the result. Rather than edit all of them, debugfs.h now
  wraps those helpers in macros that yield the parent dentry (never NULL, never an ERR_PTR),
  with `#undef`s where debugfs itself defines the real functions.
- Smaller renames applied across the vendor trees: `digital_mute` -> `mute_stream` +
  `no_capture_mute`, `rtd->cpu_dai`/`codec_dai` -> `asoc_rtd_to_cpu/codec()`,
  `VFL_TYPE_GRABBER` -> `VFL_TYPE_VIDEO`, `ndo_tx_timeout` gaining a queue index,
  `last_residency` -> `last_residency_ns`, thermal `get_mode`/`set_mode` ->
  `thermal_zone_device_{enable,disable}`, procfs entries needing `struct proc_ops`,
  `pr_warning` -> `pr_warn`, `probe_kernel_address` -> `get_kernel_nofault`,
  `ktime_to_timespec` -> `ktime_to_timespec64`, `iio_device_alloc` gaining a parent device,
  `kernel_read_file_from_path` moving header and gaining an offset.

Definitions that had to be restored because the merge replaced the file that held them:
`of_thermal_handle_trip{,_temp}` (of-thermal.c became thermal_of.c) and `iommu_get_fault_ids`
(CAF's arm-smmu.c became the mainline driver; it now reports the ids as unavailable, which
only affects a diagnostic print in the camera SMMU fault handler).

Two real bugs the merge had left behind, both found as compile errors: `struct mmc_host`
carried *both* the CAF `keyslot_manager *ksm` and 5.10's `blk_keyslot_manager ksm`, and
`cma_alloc()`'s last argument is a gfp_t in this tree, not the old `no_warn` bool - the
minidump and ION CMA heaps were passing `false`, i.e. no GFP flags at all.

## Proof that this is really 5.10-shaped (re-checked 2026-07-27, after ~40 fix commits)
`make kernelversion` -> 5.10.261.

Positive control - susfs4ksu's `gki-android12-5.10` patch, 23 files:
`patch -p1 --dry-run -F3` succeeds on all of them. Only `security/selinux/hooks.c`
needs the fuzz, and only because this tree wraps the definition in Qualcomm's RTIC
hardening:

    #ifdef CONFIG_QCOM_RTIC
    struct selinux_state selinux_state __rticdata;
    #else
    struct selinux_state selinux_state;
    #endif

where stock GKI has the bare line susfs's context expects. That is a vendor difference,
not a porting defect, and every other hunk lands with only line-number offsets.

Negative control - susfs4ksu's older `kernel-4.19` patch fails 9 hunks against this tree,
which is what you want to see: the tree no longer looks like the older kernel.

Re-run both after any large rebase:
    git clone --depth 1 -b gki-android12-5.10 https://gitlab.com/simonpunk/susfs4ksu.git
    patch -p1 --dry-run -F3 < susfs4ksu/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch

## Safety (flashing)
- Building/editing source touches no phone. Worst case flashing = bootloop (soft-brick):
  `fastboot flash boot <stock_boot.img>` recovers. Kernel flash does NOT wipe data
  (unlocking the bootloader is what wipes). Keep stock boot.img. EDL (9008) is the
  last-resort recovery; true hard-brick from a kernel flash is very unlikely.
