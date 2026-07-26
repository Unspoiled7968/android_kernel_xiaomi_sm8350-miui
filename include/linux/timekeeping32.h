#ifndef _LINUX_TIMEKEEPING32_H
#define _LINUX_TIMEKEEPING32_H
/*
 * These interfaces are all based on the old timespec type
 * and should get replaced with the timespec64 based versions
 * over time so we can remove the file here.
 */

static inline unsigned long get_seconds(void)
{
	return ktime_get_real_seconds();
}

/*
 * do_gettimeofday() and ktime_get_ts() were removed upstream in 5.6/5.8.
 * Downstream QC/Xiaomi drivers (touchscreen, techpack audio/video, cnss
 * wifi, uwb) still use them for logging timestamps; keep thin wrappers on
 * top of the timespec64 interfaces rather than patching every caller.
 */
static inline void do_gettimeofday(struct timeval *tv)
{
	struct timespec64 now;

	ktime_get_real_ts64(&now);
	tv->tv_sec = now.tv_sec;
	tv->tv_usec = now.tv_nsec / 1000;
}

static inline void ktime_get_ts(struct timespec *ts)
{
	struct timespec64 now;

	ktime_get_ts64(&now);
	ts->tv_sec = now.tv_sec;
	ts->tv_nsec = now.tv_nsec;
}

#endif
