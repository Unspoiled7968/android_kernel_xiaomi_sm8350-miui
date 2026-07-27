// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2020 - 2021, The Linux Foundation. All rights reserved.
 */

#include <linux/scmi_protocol.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/init.h>
#include <linux/err.h>
#include <linux/errno.h>
#include <linux/platform_device.h>

extern void rimps_plh_init(const struct scmi_plh_vendor_ops *ops,
			   const struct scmi_protocol_handle *ph);

static int scmi_plh_probe(struct scmi_device *sdev)
{
	const struct scmi_handle *handle = sdev->handle;
	const struct scmi_plh_vendor_ops *ops;
	struct scmi_protocol_handle *ph;

	if (!handle)
		return -ENODEV;

	ops = handle->devm_get_protocol(sdev, SCMI_PROTOCOL_PLH, &ph);
	if (IS_ERR(ops))
		return PTR_ERR(ops);

	rimps_plh_init(ops, ph);
	return 0;
}

static const struct scmi_device_id scmi_id_table[] = {
	{ SCMI_PROTOCOL_PLH },
	{ },
};
MODULE_DEVICE_TABLE(scmi, scmi_id_table);

static struct scmi_driver scmi_plh_drv = {
	.name		= "scmi-plh-driver",
	.probe		= scmi_plh_probe,
	.id_table	= scmi_id_table,
};
module_scmi_driver(scmi_plh_drv);

MODULE_DESCRIPTION("ARM SCMI PLH driver");
MODULE_LICENSE("GPL v2");
