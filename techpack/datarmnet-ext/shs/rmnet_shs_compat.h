/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _RMNET_SHS_COMPAT_H_
#define _RMNET_SHS_COMPAT_H_

#include <linux/types.h>
#include <linux/time64.h>
#include <linux/ktime.h>
#include <net/netlink.h>

/*
 * 5.10 removed time_t, struct timespec and getnstimeofday() from the kernel
 * side. This module only stamps whole seconds with them, and its sources are
 * machine-generated, so give it the old shapes back locally through a forced
 * include rather than rewriting them.
 */
typedef __kernel_long_t time_t;

struct timespec {
	time_t	tv_sec;
	long	tv_nsec;
};

static inline void getnstimeofday(struct timespec *ts)
{
	struct timespec64 ts64;

	ktime_get_real_ts64(&ts64);
	ts->tv_sec = ts64.tv_sec;
	ts->tv_nsec = ts64.tv_nsec;
}

/*
 * NLA_EXACT_LEN is gone. NLA_UNSPEC with .len enforces the minimum length,
 * which is what the handler needs before reading a fixed-size struct out of
 * the attribute - and it is what qcacld's own compat picks.
 */
#ifndef NLA_EXACT_LEN
#define NLA_EXACT_LEN NLA_UNSPEC
#endif

#endif /* _RMNET_SHS_COMPAT_H_ */
