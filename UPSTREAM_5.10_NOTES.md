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

## Known follow-ups for CI build (expected errors)
- CAF leaf drivers kept wholesale still call some 5.4-era APIs (keyslot-manager in
  ufshcd-crypto/cqhci-crypto-qti, coresight byte-cntr/csr vs 5.10 coresight-core,
  sdhci-msm vs 5.10 sdhci, dwc3-msm vs auto-merged drd.c) — fix as compiler reports.
- coresight_disable_all_source_link/enable_all_source_link declared but the 5.10
  coresight-core.c doesn't implement them (CAF tmc-etr/etf call them).
- crypto-qti-common.h still includes removed linux/bio-crypt-ctx.h.
- mm/kasan/shadow.c lacks the 5.4 vendor __GFP_ZERO hotplug hunk (KASAN-only).
- Dropped (deliberate): QCOM_INITIAL_LOGBUF (incompatible with 5.10 printk ringbuffer),
  CAF energy_model debugfs (superseded), CAF arm32 IOMMU-DMA rework (arm64 device),
  wil6210 CAF fork (CONFIG_WIL6210 not set for star), vendor exfat 6.0 (5.10 GKI exfat used).
- Renumbered to avoid 5.10 collisions: VM_LOWMEM 0x400, FAULT_FLAG_PREFAULT_OLD 0x800,
  DMA_ATTR_FORCE_(NON_)COHERENT bits 18/19, IOMMU_USE_UPSTREAM_HINT/LLC_NWA bits 8/9,
  IO_PGTABLE quirk bits 6/7, BPF_SOCK_OPS_VOIP_CB appended after 5.10 callbacks.

## Safety (flashing)
- Building/editing source touches no phone. Worst case flashing = bootloop (soft-brick):
  `fastboot flash boot <stock_boot.img>` recovers. Kernel flash does NOT wipe data
  (unlocking the bootloader is what wipes). Keep stock boot.img. EDL (9008) is the
  last-resort recovery; true hard-brick from a kernel flash is very unlikely.
