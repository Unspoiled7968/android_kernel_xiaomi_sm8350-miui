#!/bin/bash
set -e

# ==========================================
# Настройки сборки
# ==========================================
DEVICE_NAME="star"
LOCALVERSION="-palaziks"
# ==========================================

# ---------------------------------------------------------
# ЧАСТЬ 1: ЗАПУСК DOCKER (если мы на Mac/Хосте)
# ---------------------------------------------------------
if [ ! -f "/.dockerenv" ]; then
    echo "============================================"
    echo " Стартуем Docker-контейнер (Ubuntu 22.04)..."
    echo "============================================"
    
    if ! command -v docker &> /dev/null; then
        echo "Ошибка: Docker не установлен! Скачайте Docker Desktop."
        exit 1
    fi
    
    if ! docker info > /dev/null 2>&1; then
        echo "Ошибка: Docker установлен, но не запущен. Откройте приложение Docker Desktop!"
        exit 1
    fi

    # Запускаем контейнер, монтируем текущую папку в /workspace и вызываем этот же скрипт
    docker run --rm -it -v "$(pwd):/workspace" -w /workspace ubuntu:22.04 bash ./build_docker.sh
    exit 0
fi

# ---------------------------------------------------------
# ЧАСТЬ 2: ВЫПОЛНЕНИЕ ВНУТРИ DOCKER (Среда Ubuntu)
# ---------------------------------------------------------
echo "============================================"
echo " Внутри Docker: Начинаем сборку $DEVICE_NAME"
echo "============================================"

echo "=== 1. Установка Linux-зависимостей и компиляторов ==="
apt-get update
export DEBIAN_FRONTEND=noninteractive
apt-get install -y tzdata
apt-get install -y clang lld llvm git make gcc flex bison bc \
    libssl-dev ccache libncurses5-dev libncursesw5-dev cmake \
    python3 python-is-python3 cpio curl patch tar zip unzip sudo \
    crossbuild-essential-arm64

echo "=== 2. Интеграция KernelSU Next ==="
rm -rf KernelSU
git clone --depth=1 https://github.com/rifsxd/KernelSU-Next.git KernelSU
ln -sf "$(pwd)/KernelSU/kernel" drivers/kernelsu
grep -q "kernelsu" drivers/Makefile || echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
grep -q "kernelsu" drivers/Kconfig || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig

echo "=== 3. Применение KSU Manual Hooks (Python) ==="
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

insert_after('fs/exec.c', '\tchar *pathbuf = NULL;\n', '#ifdef CONFIG_KSU\n\textern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n\t\t\t\t       void *argv, void *envp, int *flags);\n\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n#endif\n')
insert_after('fs/open.c', '\tconst struct cred *old_cred;\n\tstruct cred *override_cred;\n', '#ifdef CONFIG_KSU\n\textern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n\t\t\t\t\tint *mode, int *flags);\n\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n#endif\n')
insert_after('fs/read_write.c', 'ssize_t vfs_read(struct file *file, char __user *buf, size_t count, loff_t *pos)\n{\n\tssize_t ret;\n', '#ifdef CONFIG_KSU\n\textern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,\n\t\t\t\t       size_t *count_ptr, loff_t **pos);\n\tksu_handle_vfs_read(&file, &buf, &count, &pos);\n#endif\n')
insert_after('fs/stat.c', '\tint error = -EINVAL;\n', '#ifdef CONFIG_KSU\n\textern int ksu_handle_stat(int *dfd, const char __user **filename_user,\n\t\t\t\t   int *flags);\n\tksu_handle_stat(&dfd, &filename, &flags);\n#endif\n')
EOF

echo "=== 4. Интеграция SuSFS ==="
rm -rf /tmp/susfs4ksu
git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b kernel-5.4 /tmp/susfs4ksu
SUSFS_DIR="/tmp/susfs4ksu"
# Флаг -f обязателен, чтобы патч не зависал на отсутствующих файлах
patch -p1 -f < "$SUSFS_DIR/kernel_patches/50_add_susfs_in_kernel-5.4.patch" || echo "Kernel susfs patch skipped some files"
cp -v "$SUSFS_DIR/kernel_patches/fs/susfs.c"               fs/
cp -v "$SUSFS_DIR/kernel_patches/include/linux/susfs.h"     include/linux/
cp -v "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" include/linux/
grep -q "susfs.o" fs/Makefile || echo "obj-y += susfs.o" >> fs/Makefile

echo "=== 5. Фиксы для MIUI 5.4 QGKI ==="
grep -q "susfs_mnt_id_backup" include/linux/mount.h || sed -i '/int mnt_flags;/a \ \ \ \ u64 susfs_mnt_id_backup;' include/linux/mount.h
grep -q "^struct kstat;" include/linux/susfs.h || sed -i '1s/^/struct kstat;\n/' include/linux/susfs.h
grep -q "linux/susfs.h" fs/proc/task_mmu.c || sed -i '1s/^/#include <linux\/susfs.h>\n/' fs/proc/task_mmu.c
grep -q "linux/susfs.h" fs/proc/fd.c || sed -i '1s/^/#include <linux\/susfs.h>\n/' fs/proc/fd.c
sed -i 's/TWA_RESUME/true/g' KernelSU/kernel/allowlist.c 2>/dev/null || true
grep -q "linux/sched/task.h" KernelSU/kernel/allowlist.c || sed -i '1s/^/#include <linux\/sched\/task.h>\n/' KernelSU/kernel/allowlist.c

find KernelSU/kernel -name "*.c" -o -name "*.h" | while read f; do
    grep -q "linux/pgtable.h" "$f" && sed -i 's|#include <linux/pgtable.h>|#include <asm/pgtable.h>|g' "$f"
    grep -q "strncpy_from_user_nofault" "$f" && sed -i 's/strncpy_from_user_nofault/strncpy_from_user/g' "$f"
done

sed -i '/seccomp\.filter_count/d' KernelSU/kernel/app_profile.c 2>/dev/null || true
sed -i 's/module_exit(ksu_kernelsu_exit);/\/\/module_exit(ksu_kernelsu_exit);/g' KernelSU/kernel/ksu.c 2>/dev/null || true

echo "=== 6. Конфигурация defconfig ==="
DEFCONFIG=$(find arch/arm64/configs -name "*${DEVICE_NAME}*defconfig" | head -n 1)
for FLAG in \
    "CONFIG_KSU=y" "CONFIG_KSU_DEBUG=n" "CONFIG_KSU_SUSFS=y" \
    "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" "CONFIG_KSU_SUSFS_SUS_MOUNT=y" \
    "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" "CONFIG_KSU_SUSFS_ENABLE_LOG=y" \
    "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y"; do
    KEY=$(echo "$FLAG" | cut -d= -f1)
    grep -q "^${KEY}[=\ ]" "$DEFCONFIG" || echo "$FLAG" >> "$DEFCONFIG"
done

echo "=== 7. Сборка ядра ==="
git config --global user.email "you@example.com" || true
git config --global user.name "wannq" || true
export LOCALVERSION="$LOCALVERSION"

chmod +x ./build.sh
./build.sh all $DEVICE_NAME 2>&1 | tee kbuild.log

if [ ! -f arch/arm64/boot/Image ] && [ ! -d out/anykernel ]; then
    echo "============================================"
    echo " BUILD FAILED — Check kbuild.log for errors"
    echo "============================================"
    exit 1
fi

echo "============================================"
echo " BUILD SUCCESSFUL!"
echo " Compiled files are ready in out/anykernel/"
echo "============================================"
