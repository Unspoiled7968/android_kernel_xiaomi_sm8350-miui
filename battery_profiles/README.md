# Star Battery Profiles

This directory is the profile layer that sits above the kernel battery
compatibility engine for Xiaomi 11 Ultra (`star`).

The design goal is simple:

- keep the kernel generic;
- keep battery-specific values out of the kernel source;
- switch battery behavior by loading a profile;
- avoid recompiling the kernel for every battery swap.

## Why this exists

The stock Xiaomi 11 Ultra battery path was built for a normal
4900/5000 mAh pack. A modified battery setup can reuse the original
protection and gauge board while replacing only the cell.

That means:

- the board identity may still look "stock";
- the learned FCC / SOH / cycle data may still reflect the old board;
- different silicon-carbon cells may fit physically but need different
  display/accounting settings.

A profile system is cleaner than hardcoding one magic value into the
kernel.

## Layer split

1. Kernel layer

- exposes `capacity_compat_*` sysfs nodes under `/sys/class/qcom-battery`;
- applies a bounded compatibility model when enabled;
- keeps raw battery data available for diagnosis.

2. Profile layer

- stores per-battery presets as simple `.conf` files;
- lets us switch between stock, candidate, and experimental cells;
- can later be shipped as a KSU or Magisk companion module.

3. Evidence layer

- logs raw and adjusted values while charging and discharging;
- helps tune `full_uah`, `empty_uv`, and reserve behavior per cell.

## Profile rules

Each profile should describe:

- target phone and reused board;
- cell source and chemistry;
- design capacity;
- initial compatibility full capacity;
- low-voltage floor;
- reserve tail percentage;
- safety stage.

The important rule is:

- `design_uah` is the pack label / intended nominal design;
- `full_uah` is the practical Android-facing usable full target;
- `full_uah` must be tuned from logs, not guessed from marketing alone.

## Profile stages

- `baseline`: safe reference, no special behavior expected.
- `candidate`: reasonable first guess, but still needs logs.
- `experimental`: only for manual testing.

## Apply model

The Android-facing battery middleware should work like this:

1. pick one profile;
2. write its values to `/sys/class/qcom-battery/capacity_compat_*`;
3. keep the kernel profile disabled by default unless the file explicitly
   enables it;
4. read back `capacity_compat_status`;
5. log raw and adjusted values during real use.

## Why manual profile selection is better

Automatic cell detection is not trustworthy here because the reused Xiaomi
board may still report stock-like identifiers even when the cell is
completely different.

Manual profile selection is safer because:

- it matches the physical mod you actually installed;
- it avoids false detection;
- it works even when multiple cells reuse one board family.

## Future direction

The best long-term flow is:

- kernel battery compat engine in the boot image;
- KSU or Magisk profile module on top;
- one profile package with multiple battery presets;
- optional UI or shell command to switch active profile;
- later, optional SOH/FCC/cycle masking experiments as a separate toggle.

Do not mix capacity accounting and charge-power forcing in one profile.
Those are separate problems and should stay separately controllable.
