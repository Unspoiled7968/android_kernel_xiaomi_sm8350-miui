/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _CAM_COMPAT_TIME_H_
#define _CAM_COMPAT_TIME_H_

#include <linux/types.h>

/*
 * 5.10 removed struct timeval from the kernel side. This tree's camera_star
 * keeps its timestamps in microseconds in ~90 places, so give the driver its
 * own definition rather than convert every site to nanoseconds and risk a
 * factor-of-1000 slipping in. The struct is internal to the ISP hardware
 * layer - nothing here reaches userspace.
 */
struct timeval {
	__kernel_long_t	tv_sec;
	__kernel_long_t	tv_usec;
};

#endif /* _CAM_COMPAT_TIME_H_ */
