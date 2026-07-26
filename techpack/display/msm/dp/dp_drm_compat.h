/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2012-2021, The Linux Foundation. All rights reserved.
 *
 * Compatibility shim for DRM DisplayPort helper APIs that were removed or
 * renamed in the core between Linux 5.4 (which this CAF driver was written
 * against) and Linux 5.10.
 *
 * Two independent changes upstream affect this driver:
 *
 * 1) v5.5 removed "struct drm_dp_link" together with
 *    drm_dp_link_probe()/_power_up()/_power_down()/_configure() from
 *    include/drm/drm_dp_helper.h and drivers/gpu/drm/drm_dp_helper.c
 *    (the API was deemed too Tegra-specific).  The one remaining in-tree
 *    user, Tegra, carries a private copy in drivers/gpu/drm/tegra/dp.c.
 *    We do exactly the same here: "struct dp_link_info" below is a verbatim
 *    copy of the old "struct drm_dp_link", and the three helpers are
 *    verbatim copies of the removed drm_dp_helper.c implementations.
 *    drm_dp_link_probe() is not reimplemented - this driver never used it,
 *    dp_panel_read_dpcd() parses the DPCD itself.
 *
 * 2) The DPCD 0x248 PHY test pattern definitions were renamed from
 *    DP_TEST_PHY_PATTERN* to DP_PHY_TEST_PATTERN*.  The renamed names are
 *    used directly in the driver; only the two CP2520 selections that core
 *    never defined (pattern 2 and pattern 3 / TPS4) are supplied here.
 *
 * Nothing in this header touches core DRM; it is private to
 * techpack/display/msm/dp.
 */

#ifndef _DP_DRM_COMPAT_H_
#define _DP_DRM_COMPAT_H_

#include <linux/types.h>
#include <linux/delay.h>
#include <drm/drm_dp_helper.h>

/*
 * DPCD 0x248 (DP_PHY_TEST_PATTERN) selection values.
 *
 * 5.10's drm_dp_helper.h defines NONE/D10_2/ERROR_COUNT/PRBS7/80BIT_CUSTOM
 * and CP2520 (== CP2520 pattern 1, the HBR2 compliance eye pattern) but
 * stops there.  Pattern 2 and pattern 3 (TPS4) exist in the DP spec and are
 * used by this driver, so define them locally.
 */
#ifndef DP_PHY_TEST_PATTERN_CP2520_PAT_1
#define DP_PHY_TEST_PATTERN_CP2520_PAT_1	DP_PHY_TEST_PATTERN_CP2520
#endif
#ifndef DP_PHY_TEST_PATTERN_CP2520_PAT_2
#define DP_PHY_TEST_PATTERN_CP2520_PAT_2	0x6
#endif
#ifndef DP_PHY_TEST_PATTERN_CP2520_PAT_3
#define DP_PHY_TEST_PATTERN_CP2520_PAT_3	0x7
#endif

/* was in include/drm/drm_dp_helper.h until v5.4 */
#ifndef DP_LINK_CAP_ENHANCED_FRAMING
#define DP_LINK_CAP_ENHANCED_FRAMING (1 << 0)
#endif

/**
 * struct dp_link_info - local replacement for the removed struct drm_dp_link
 * @revision: DPCD revision (DPCD 0x000)
 * @rate: link rate in kHz
 * @num_lanes: number of lanes
 * @capabilities: bitmask of DP_LINK_CAP_*
 */
struct dp_link_info {
	unsigned char revision;
	unsigned int rate;
	unsigned int num_lanes;
	unsigned long capabilities;
};

/**
 * dp_link_power_up() - power up a DisplayPort link
 * @aux: DisplayPort AUX channel
 * @link: pointer to a structure containing the link configuration
 *
 * Replacement for the removed drm_dp_link_power_up().
 *
 * Return: 0 on success or a negative error code on failure.
 */
static inline int dp_link_power_up(struct drm_dp_aux *aux,
		struct dp_link_info *link)
{
	u8 value;
	int err;

	/* DP_SET_POWER register is only available on DPCD v1.1 and later */
	if (link->revision < 0x11)
		return 0;

	err = drm_dp_dpcd_readb(aux, DP_SET_POWER, &value);
	if (err < 0)
		return err;

	value &= ~DP_SET_POWER_MASK;
	value |= DP_SET_POWER_D0;

	err = drm_dp_dpcd_writeb(aux, DP_SET_POWER, value);
	if (err < 0)
		return err;

	/*
	 * According to the DP 1.1 specification, a "Sink Device must exit the
	 * power saving state within 1 ms" (Section 2.5.3.1, Table 5-52, "Sink
	 * Control Field" (register 0x600).
	 */
	usleep_range(1000, 2000);

	return 0;
}

/**
 * dp_link_power_down() - power down a DisplayPort link
 * @aux: DisplayPort AUX channel
 * @link: pointer to a structure containing the link configuration
 *
 * Replacement for the removed drm_dp_link_power_down().
 *
 * Return: 0 on success or a negative error code on failure.
 */
static inline int dp_link_power_down(struct drm_dp_aux *aux,
		struct dp_link_info *link)
{
	u8 value;
	int err;

	/* DP_SET_POWER register is only available on DPCD v1.1 and later */
	if (link->revision < 0x11)
		return 0;

	err = drm_dp_dpcd_readb(aux, DP_SET_POWER, &value);
	if (err < 0)
		return err;

	value &= ~DP_SET_POWER_MASK;
	value |= DP_SET_POWER_D3;

	err = drm_dp_dpcd_writeb(aux, DP_SET_POWER, value);
	if (err < 0)
		return err;

	return 0;
}

/**
 * dp_link_configure() - configure a DisplayPort link
 * @aux: DisplayPort AUX channel
 * @link: pointer to a structure containing the link configuration
 *
 * Replacement for the removed drm_dp_link_configure().
 *
 * Return: 0 on success or a negative error code on failure.
 */
static inline int dp_link_configure(struct drm_dp_aux *aux,
		struct dp_link_info *link)
{
	u8 values[2];
	int err;

	values[0] = drm_dp_link_rate_to_bw_code(link->rate);
	values[1] = link->num_lanes;

	if (link->capabilities & DP_LINK_CAP_ENHANCED_FRAMING)
		values[1] |= DP_LANE_COUNT_ENHANCED_FRAME_EN;

	err = drm_dp_dpcd_write(aux, DP_LINK_BW_SET, values, sizeof(values));
	if (err < 0)
		return err;

	return 0;
}

#endif /* _DP_DRM_COMPAT_H_ */
