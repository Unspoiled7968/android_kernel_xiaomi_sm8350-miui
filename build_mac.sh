#!/bin/bash
set -e

# ==========================================
# Настройки сборки
# ==========================================
DEVICE_NAME="star"
LOCALVERSION="-palaziks"
# ==========================================

echo "============================================"
echo " Starting macOS Local Build for: $DEVICE_NAME"
echo "============================================"

# 1. Проверка зависимостей для macOS
echo "=== Checking macOS Dependencies ==="
if ! command -v brew &> /dev/null; then
    echo "Ошибка: Homebrew не установлен! Установите его: https://brew.sh/"
    exit 1
fi

# Устанавливаем GNU sed, так как стандартный macos sed не понимает линуксовый синтаксис
if ! command -v gsed &> /dev/null; then
    echo "Устанавливаю GNU sed (gsed)..."
    brew install gnu-sed
fi

# Установка базовых утилит компиляции (если их нет)
brew install cmake ccache wget coreutils llvm findutils grep

# 2. Интеграция KernelSU Next
echo "=== Cloning KernelSU Next ==="
if [ -d "KernelSU" ]; then
    echo "KernelSU directory already exists, cleaning up..."
    rm -rf KernelSU
fi
git clone --depth=1 https://github.com/rifsxd/KernelSU-Next.git KernelSU

echo "=== Symlink KernelSU into drivers ==="
ln -sf "$(pwd)/KernelSU/kernel" drivers/kernelsu

echo "=== Wire into drivers/Makefile ==="
grep -q "kernelsu" drivers/Makefile || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile

echo "=== Wire into drivers/Kconfig ==="
grep -q "kernelsu" drivers/Kconfig || gsed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig

echo "=== Verify symlink ==="
ls -la drivers/kernelsu/Kconfig

# 3. Применение ручных хуков через Python
echo "=== Applying KSU Manual Hooks ==="
python3 << 'EOF'
import sys

def insert_after(filepath, search, insertion):
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        if 'ksu_handle' in content:
            print(f'{filepath}: hook already present, skipping')
            return
        if search not in content:
            print(f'ERROR: anchor not found in {filepath}:', repr(search))
            sys.exit(1)
        content = content.replace(search, search + insertion, 1)
        with open(filepath, 'w') as f:
            f.write(content)
        print(f'{filepath}: hook applied')
    except Exception as e:
        print(f"Failed to patch {filepath}: {e}")
        sys.exit(1)

# fs/exec.c
insert_after(
    'fs/exec.c',
    '\tchar *pathbuf = NULL;\n',
    '#ifdef CONFIG_KSU\n'
    '\textern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n'
    '\t\t\t\t       void *argv, void *envp, int *flags);\n'
    '\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n'
    '#endif\n'
)

# fs/open.c
insert_after(
    'fs/open.c',
    '\tconst struct cred *old_cred;\n\tstruct cred *override_cred;\n',
    '#ifdef CONFIG_KSU\n'
    '\textern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n'
    '\t\t\t\t\tint *mode, int *flags);\n'
    '\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n'
    '#endif\n'
)

# fs/read_write.c
insert_after(
    'fs/read_write.c',
    'ssize_t vfs_read(struct file *file, char __user *buf, size_t count, loff_t *pos)\n{\n\tssize_t ret;\n',
    '#ifdef CONFIG_KSU\n'
    '\textern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,\n'
    '\t\t\t\t       size_t *count_ptr, loff_t **pos);\n'
    '\tksu_handle_vfs_read(&file, &buf, &count, &pos);\n'
    '#endif\n'
)

# fs/stat.c
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

echo "=== Verify hooks ==="
grep -n "ksu_handle" fs/exec.c fs/open.c fs/read_write.c fs/stat.c || true


# 4. Интеграция SuSFS
echo "=== Cloning SuSFS kernel-5.4 ==="
rm -rf ../susfs4ksu
git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b kernel-5.4 ../susfs4ksu
SUSFS_DIR="$(pwd)/../susfs4ksu"

echo "=== Apply SuSFS patch to kernel tree ==="
# Добавлен флаг -f чтобы patch не останавливался с вопросами на macOS
patch -p1 -f < "$SUSFS_DIR/kernel_patches/50_add_susfs_in_kernel-5.4.patch" || echo "Kernel susfs patch had errors (continuing)"

echo "=== Copy SuSFS source files ==="
cp -v "$SUSFS_DIR/kernel_patches/fs/susfs.c"               fs/
cp -v "$SUSFS_DIR/kernel_patches/include/linux/susfs.h"     include/linux/
cp -v "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" include/linux/

echo "=== Register susfs.o in fs/Makefile ==="
grep -q "susfs.o" fs/Makefile || echo "obj-y += susfs.o" >> fs/Makefile


# 5. Применение фиксов для MIUI 5.4 QGKI (Везде используем gsed!)
echo "=== Apply Manual Fixes for MIUI 5.4 QGKI ==="

echo "=== Fix 1: susfs_mnt_id_backup in mount.h ==="
grep -q "susfs_mnt_id_backup" include/linux/mount.h || \
  gsed -i '/int mnt_flags;/a \ \ \ \ u64 susfs_mnt_id_backup;' include/linux/mount.h

echo "=== Fix 2: forward-declare struct kstat in susfs.h ==="
grep -q "^struct kstat;" include/linux/susfs.h || \
  gsed -i '1s/^/struct kstat;\n/' include/linux/susfs.h

echo "=== Fix 3: add missing susfs.h includes ==="
grep -q "linux/susfs.h" fs/proc/task_mmu.c || \
  gsed -i '1s/^/#include <linux\/susfs.h>\n/' fs/proc/task_mmu.c
grep -q "linux/susfs.h" fs/proc/fd.c || \
  gsed -i '1s/^/#include <linux\/susfs.h>\n/' fs/proc/fd.c

echo "=== Fix 4: TWA_RESUME compat + put_task_struct header ==="
gsed -i 's/TWA_RESUME/true/g' KernelSU/kernel/allowlist.c 2>/dev/null || true
grep -q "linux/sched/task.h" KernelSU/kernel/allowlist.c || \
  gsed -i '1s/^/#include <linux\/sched\/task.h>\n/' KernelSU/kernel/allowlist.c

echo "=== Fix 5: pgtable.h compat for 5.4 (linux/pgtable.h -> asm/pgtable.h) ==="
find KernelSU/kernel -name "*.c" -o -name "*.h" | while read f; do
  if grep -q "linux/pgtable.h" "$f"; then
      gsed -i 's|#include <linux/pgtable.h>|#include <asm/pgtable.h>|g' "$f"
      echo "Fixed pgtable.h in $f"
  fi
done

echo "=== Fix 6: strncpy_from_user_nofault compat for 5.4 ==="
find KernelSU/kernel -name "*.c" -o -name "*.h" | while read f; do
  if grep -q "strncpy_from_user_nofault" "$f"; then
      gsed -i 's/strncpy_from_user_nofault/strncpy_from_user/g' "$f"
      echo "Fixed strncpy_from_user_nofault in $f"
  fi
done

echo "=== Fix 7: Remove filter_count error ==="
gsed -i '/seccomp\.filter_count/d' KernelSU/kernel/app_profile.c 2>/dev/null || true

echo "=== Fix 8: Fix module_exit error in ksu.c ==="
gsed -i 's/module_exit(ksu_kernelsu_exit);/\/\/module_exit(ksu_kernelsu_exit);/g' KernelSU/kernel/ksu.c 2>/dev/null || true


# 6. Конфигурация ядра
echo "=== Appending KSU + SuSFS flags to defconfig ==="
DEFCONFIG=$(find arch/arm64/configs -name "*${DEVICE_NAME}*defconfig" | head -n 1)
if [ -z "$DEFCONFIG" ]; then
    echo "CRITICAL: defconfig not found for ${DEVICE_NAME}"
    exit 1
fi
echo "Using defconfig: $DEFCONFIG"

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

echo "=== KSU flags in defconfig ==="
grep "KSU" "$DEFCONFIG" || true


# 7. Сборка проекта
echo "=== Starting Build ==="
git config --global user.email "you@example.com" || true
git config --global user.name "wannq-github" || true

export LOCALVERSION="$LOCALVERSION"

chmod +x ./build.sh

# Запуск скрипта сборки ядра (с логированием)
./build.sh all $DEVICE_NAME 2>&1 | tee kbuild.log

# 8. Проверка результата
if [ ! -f arch/arm64/boot/Image ] && [ ! -d ../out/anykernel ]; then
    echo ""
    echo "============================================"
    echo " BUILD FAILED — Check kbuild.log for errors"
    echo "============================================"
    tail -n 50 kbuild.log
    exit 1
fi

echo "============================================"
echo " BUILD SUCCESSFUL!"
echo " Compiled files should be in ../out/anykernel/"
echo "============================================"
