#!/usr/bin/env bash
set -e

# ─────────────────────────────────────────────
#  build_local.sh — KernelSU Next + SuSFS
#  Usage: ./build_local.sh [device] [localversion]
#  Example: ./build_local.sh star -palaziks
# ─────────────────────────────────────────────

DEVICE="${1:-star}"
LOCALVERSION="${2:--palaziks}"
KERNEL_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$(dirname "$KERNEL_DIR")/out"
SUSFS_DIR="$(dirname "$KERNEL_DIR")/susfs4ksu"
KSU_DIR="$KERNEL_DIR/KernelSU"

echo "=============================="
echo " Device:       $DEVICE"
echo " LocalVersion: $LOCALVERSION"
echo " Kernel dir:   $KERNEL_DIR"
echo "=============================="

# ── 1. Dependencies ──────────────────────────
echo ""
echo "=== [1/7] Installing dependencies ==="
sudo apt update -qq
sudo apt install -y clang lld llvm git make gcc flex bison bc \
  libssl-dev ccache libncurses5-dev libncursesw5-dev cmake \
  python3 cpio curl patch zip unzip

# ── 2. KernelSU Next ─────────────────────────
echo ""
echo "=== [2/7] Integrating KernelSU Next ==="

if [ ! -d "$KSU_DIR" ]; then
  git clone --depth=1 https://github.com/rifsxd/KernelSU-Next.git "$KSU_DIR"
else
  echo "KernelSU already cloned, skipping"
fi

cd "$KERNEL_DIR"

ln -sf "$KSU_DIR/kernel" drivers/kernelsu
grep -q "kernelsu" drivers/Makefile || \
  echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
grep -q "kernelsu" drivers/Kconfig || \
  sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig

echo "Symlink: $(ls -la drivers/kernelsu/Kconfig)"

# ── 3. KSU Manual Hooks ──────────────────────
echo ""
echo "=== [3/7] Applying KSU manual hooks ==="

python3 << 'EOF'
import sys

def insert_after(filepath, search, insertion):
    with open(filepath, 'r') as f:
        content = f.read()
    if 'ksu_handle' in content:
        print(f'{filepath}: hook already present, skipping')
        return
    if search not in content:
        print(f'ERROR: anchor not found in {filepath}: {repr(search)}')
        sys.exit(1)
    content = content.replace(search, search + insertion, 1)
    with open(filepath, 'w') as f:
        f.write(content)
    print(f'{filepath}: hook applied')

insert_after(
    'fs/exec.c',
    '\tchar *pathbuf = NULL;\n',
    '#ifdef CONFIG_KSU\n'
    '\textern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n'
    '\t\t\t\t       void *argv, void *envp, int *flags);\n'
    '\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n'
    '#endif\n'
)

insert_after(
    'fs/open.c',
    '\tconst struct cred *old_cred;\n\tstruct cred *override_cred;\n',
    '#ifdef CONFIG_KSU\n'
    '\textern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n'
    '\t\t\t\t\tint *mode, int *flags);\n'
    '\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n'
    '#endif\n'
)

insert_after(
    'fs/read_write.c',
    'ssize_t vfs_read(struct file *file, char __user *buf, size_t count, loff_t *pos)\n{\n\tssize_t ret;\n',
    '#ifdef CONFIG_KSU\n'
    '\textern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,\n'
    '\t\t\t\t       size_t *count_ptr, loff_t **pos);\n'
    '\tksu_handle_vfs_read(&file, &buf, &count, &pos);\n'
    '#endif\n'
)

insert_after(
    'fs/stat.c',
    '\tint error = -EINVAL;\n',
    '#ifdef CONFIG_KSU\n'
    '\textern int ksu_handle_stat(int *dfd, const char __user **filename_user,\n'
    '\t\t\t\t   int *flags);\n'
    '\tksu_handle_stat(&dfd, &filename, &flags);\n'
    '#endif\n'
)
EOF

echo "Hooks:"
grep -n "ksu_handle" fs/exec.c fs/open.c fs/read_write.c fs/stat.c

# ── 4. SuSFS ─────────────────────────────────
echo ""
echo "=== [4/7] Integrating SuSFS ==="

if [ ! -d "$SUSFS_DIR" ]; then
  git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b kernel-5.4 "$SUSFS_DIR"
else
  echo "SuSFS already cloned, skipping"
fi

cd "$KERNEL_DIR"

echo "--- Applying SuSFS patch to kernel tree ---"
patch -p1 < "$SUSFS_DIR/kernel_patches/50_add_susfs_in_kernel-5.4.patch" \
  && echo "SuSFS kernel patch applied" \
  || echo "SuSFS kernel patch had errors (continuing)"

echo "--- Copying SuSFS source files ---"
cp -v "$SUSFS_DIR/kernel_patches/fs/susfs.c"               fs/
cp -v "$SUSFS_DIR/kernel_patches/include/linux/susfs.h"     include/linux/
cp -v "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" include/linux/

grep -q "susfs.o" fs/Makefile || echo "obj-y += susfs.o" >> fs/Makefile

# ── 5. Manual fixes ──────────────────────────
echo ""
echo "=== [5/7] Applying MIUI 5.4 QGKI fixes ==="

grep -q "susfs_mnt_id_backup" include/linux/mount.h || \
  sed -i '/struct vfsmount {/a \\tu64 susfs_mnt_id_backup;' include/linux/mount.h
echo "Fix 1: mount.h OK"

grep -q "^struct kstat;" include/linux/susfs.h || \
  sed -i '1s/^/struct kstat;\n/' include/linux/susfs.h
echo "Fix 2: susfs.h kstat OK"

grep -q "linux/susfs.h" fs/proc/task_mmu.c || \
  sed -i '1s/^/#include <linux\/susfs.h>\n/' fs/proc/task_mmu.c
grep -q "linux/susfs.h" fs/proc/fd.c || \
  sed -i '1s/^/#include <linux\/susfs.h>\n/' fs/proc/fd.c
echo "Fix 3: proc includes OK"

sed -i 's/TWA_RESUME/true/g' "$KSU_DIR/kernel/allowlist.c" 2>/dev/null || true
grep -q "linux/sched/task.h" "$KSU_DIR/kernel/allowlist.c" || \
  sed -i '1s/^/#include <linux\/sched\/task.h>\n/' "$KSU_DIR/kernel/allowlist.c"
echo "Fix 4: allowlist.c OK"

# ── 6. Defconfig ─────────────────────────────
echo ""
echo "=== [6/7] Patching defconfig ==="

DEFCONFIG=$(find arch/arm64/configs -name "*${DEVICE}*defconfig" | head -n 1)
if [ -z "$DEFCONFIG" ]; then
  echo "CRITICAL: defconfig not found for $DEVICE"
  exit 1
fi
echo "Using: $DEFCONFIG"

for FLAG in \
  "CONFIG_KSU=y" \
  "CONFIG_KSU_DEBUG=n" \
  "CONFIG_KSU_SUSFS=y" \
  "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" \
  "CONFIG_KSU_SUSFS_SUS_MOUNT=y" \
  "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" \
  "CONFIG_KSU_SUSFS_ENABLE_LOG=y" \
  "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y"; do
  KEY=$(echo "$FLAG" | cut -d= -f1)
  grep -q "^${KEY}[=\ ]" "$DEFCONFIG" || echo "$FLAG" >> "$DEFCONFIG"
done

echo "KSU flags:"
grep "KSU" "$DEFCONFIG"

# ── 7. Build ─────────────────────────────────
echo ""
echo "=== [7/7] Building kernel ==="

git config --global user.email "you@example.com"
git config --global user.name "wannq-github"

export LOCALVERSION="$LOCALVERSION"

chmod +x ./build.sh
./build.sh all "$DEVICE" 2>&1 | tee /tmp/kbuild.log

if [ ! -f arch/arm64/boot/Image ]; then
  echo ""
  echo "=== BUILD FAILED — last errors ==="
  grep -E "error:|undefined reference|FAILED" /tmp/kbuild.log | tail -50
  exit 1
fi

echo ""
echo "=============================="
echo " BUILD SUCCESS"
echo " Output: $OUT_DIR/anykernel/"
ls "$OUT_DIR/anykernel/"*.zip 2>/dev/null || true
echo "=============================="
