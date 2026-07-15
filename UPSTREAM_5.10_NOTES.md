# Mi 11 Ultra (star / sm8350) — 5.4 → 5.10 merge experiment

**Status: EXPERIMENTAL / for testing only. This will NOT build cleanly or boot as-is.**

## What this branch is
- Base: `palazik/android_kernel_xiaomi_sm8350-miui` @ `ASB-2024-10-05` = **Linux 5.4.283**
- Merged: Google AOSP common kernel `android12-5.10` = **real Linux 5.10.257 (GKI)**
- Method: `git merge --allow-unrelated-histories` (the "just merge the latest LTS" approach)

## What happened
- The two trees share **no common ancestor**, so git produced **28,255 conflicts**
  (28,252 "add/add": same file path on both sides, entire file conflicting).
- Every subsystem conflicted at once (drivers/net 2557, drivers/gpu 2199,
  arch/arm 1558, include/linux 985, ...).
- Resolution applied: took **Google's real 5.10.257** for every conflicting file;
  kept **Xiaomi-only** files (star/mars device trees, vendor defconfig, `techpack/`).

## Why it will NOT build / boot
- Kernel **core is 5.10**, but Xiaomi's **vendor drivers are still 5.4-era**
  (`techpack/`, `drivers/staging/qcacld-3.0`, camera_star, display, etc.).
- Those drivers call kernel-internal APIs that were **changed/removed in 5.10**
  (dma-buf, sched, mm, iommu, KMI/GKI symbol changes, etc.).
- The build wiring (Kconfig/Makefile) at overlapping paths is now Google's, so the
  vendor drivers are also not correctly hooked into the 5.10 build.
- A real 5.10 port = **re-porting every vendor driver by hand**, not a merge.
  There is **no official Qualcomm 5.10 base for sm8350** (SD888 shipped on 5.4).

## Safety
- Editing this source does nothing to any phone.
- Flashing risk is on you later: **unlocking the bootloader wipes all data** (back up first).
- A bad kernel = **bootloop (soft-brick)**, fixed by `fastboot flash boot <stock_boot.img>`.
- Keep your stock `boot.img`. True hard-brick from a kernel is very unlikely (EDL 9008 recovery exists).
