# SPDX-License-Identifier: GPL-2.0-only
zram-y	:=	zcomp.o zram_drv.o
zram-$(CONFIG_ZRAM_DEDUP)	+=	zram_dedup.o

# lz4p includes "lz4defs.h", which lives in lib/lz4
ccflags-$(CONFIG_ZRAM_LZ4P) += -I$(srctree)/lib/lz4
# lz4p is imported third-party-style source written in C99 style; 5.10 makes
# -Wdeclaration-after-statement an error, so relax it for these files only.
CFLAGS_lz4p/lz4p.o += -Wno-declaration-after-statement
CFLAGS_lz4p/lz4p_compress.o += -Wno-declaration-after-statement
CFLAGS_lz4p/lz4p_decompress.o += -Wno-declaration-after-statement

zram-$(CONFIG_ZRAM_LZ4P)		+=	lz4p/lz4p.o
zram-$(CONFIG_ZRAM_LZ4P)		+=	lz4p/lz4p_compress.o
zram-$(CONFIG_ZRAM_LZ4P)		+=	lz4p/lz4p_decompress.o
zram-$(CONFIG_ZRAM_LZ4P)		+=	lz4p/lz4p_encode.o
zram-$(CONFIG_ZRAM_LZ4P)		+=	lz4p/lz4p_decode.o


obj-$(CONFIG_ZRAM)	+=	zram.o
