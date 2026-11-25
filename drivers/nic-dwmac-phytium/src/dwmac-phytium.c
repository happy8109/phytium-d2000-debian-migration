// SPDX-License-Identifier: GPL-2.0-only
/*
 * Phytium D2000 ACPI GMAC (DWMAC) platform glue driver
 *
 * Copyright (C) 2026
 */

#include <linux/acpi.h>
#include <linux/clk.h>
#include <linux/clk-provider.h>
#include <linux/dma-mapping.h>
#include <linux/etherdevice.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/property.h>
#include <linux/stmmac.h>

/*
 * Out-of-tree declarations matching Linux 6.12 stmmac / stmmac-platform
 * exported symbols (verified against kernel BTF and Module.symvers).
 */
struct stmmac_resources {
	void __iomem *addr;
	u8 mac[ETH_ALEN];
	int wol_irq;
	int irq;
	int sfty_irq;
	int sfty_ce_irq;
	int sfty_ue_irq;
	int rx_irq[MTL_MAX_RX_QUEUES];
	int tx_irq[MTL_MAX_TX_QUEUES];
};

extern int stmmac_get_platform_resources(struct platform_device *pdev,
					 struct stmmac_resources *stmmac_res);
extern int stmmac_pltfr_probe(struct platform_device *pdev,
			      struct plat_stmmacenet_data *plat,
			      struct stmmac_resources *res);
extern void stmmac_pltfr_remove(struct platform_device *pdev);
extern const struct dev_pm_ops stmmac_pltfr_pm_ops;

static void phytium_dwmac_clk_unregister(void *data)
{
	struct clk *clk = data;

	clk_disable_unprepare(clk);
	clk_unregister_fixed_rate(clk);
}

static void phytium_dwmac_parse_axi(struct device *dev,
				    struct plat_stmmacenet_data *plat)
{
	u32 burst_len = 0;
	int idx = 0;
	static const u32 blen_map[] = { 4, 8, 16, 32, 64, 128, 256 };
	int i;

	if (device_property_read_u32(dev, "snps,burst_len", &burst_len))
		return;

	plat->axi = devm_kzalloc(dev, sizeof(*plat->axi), GFP_KERNEL);
	if (!plat->axi)
		return;

	for (i = 0; i < ARRAY_SIZE(blen_map) && idx < AXI_BLEN; i++) {
		if (burst_len & BIT(i + 1))
			plat->axi->axi_blen[idx++] = blen_map[i];
	}
}

static int phytium_dwmac_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct plat_stmmacenet_data *plat;
	struct stmmac_resources stmmac_res;
	int phy_mode;
	u32 val;
	u32 clk_freq = 250000000;
	int ret;

	ret = stmmac_get_platform_resources(pdev, &stmmac_res);
	if (ret)
		return ret;

	plat = devm_kzalloc(dev, sizeof(*plat), GFP_KERNEL);
	if (!plat)
		return -ENOMEM;

	plat->dma_cfg = devm_kzalloc(dev, sizeof(*plat->dma_cfg), GFP_KERNEL);
	if (!plat->dma_cfg)
		return -ENOMEM;

	plat->mdio_bus_data = devm_kzalloc(dev, sizeof(*plat->mdio_bus_data),
					   GFP_KERNEL);
	if (!plat->mdio_bus_data)
		return -ENOMEM;

	phy_mode = device_get_phy_mode(dev);
	if (phy_mode < 0)
		phy_mode = PHY_INTERFACE_MODE_RGMII_RXID;

	plat->phy_interface = phy_mode;
	plat->mac_interface = phy_mode;
	plat->phy_addr = -1;
	plat->mdio_bus_data->needs_reset = true;

	if (!device_property_read_u32(dev, "bus_id", &val))
		plat->bus_id = val;
	else
		plat->bus_id = 1;

	if (!device_property_read_u32(dev, "mdc_clock_selection", &val))
		plat->clk_csr = val;
	else
		plat->clk_csr = STMMAC_CSR_250_300M;

	device_property_read_u32(dev, "clock-frequency", &clk_freq);
	plat->stmmac_clk = clk_register_fixed_rate(dev, "stmmaceth", NULL, 0,
						   clk_freq);
	if (IS_ERR(plat->stmmac_clk))
		return dev_err_probe(dev, PTR_ERR(plat->stmmac_clk),
				     "failed to register stmmaceth clock\n");

	ret = clk_prepare_enable(plat->stmmac_clk);
	if (ret) {
		clk_unregister_fixed_rate(plat->stmmac_clk);
		return dev_err_probe(dev, ret,
				     "failed to enable stmmaceth clock\n");
	}

	ret = devm_add_action_or_reset(dev, phytium_dwmac_clk_unregister,
				       plat->stmmac_clk);
	if (ret)
		return ret;

	/* Phytium D2000 GMAC core configuration */
	plat->has_gmac = 1;
	plat->enh_desc = 1;
	plat->tx_coe = 1;
	plat->rx_coe = STMMAC_RX_COE_TYPE2;
	plat->pmt = 1;
	plat->tx_queues_to_use = 1;
	plat->rx_queues_to_use = 1;
	plat->tx_queues_cfg[0].mode_to_use = MTL_QUEUE_DCB;
	plat->rx_queues_cfg[0].mode_to_use = MTL_QUEUE_DCB;

	if (!device_property_read_u32(dev, "snps,multicast-filter-bins", &val))
		plat->multicast_filter_bins = val;
	else
		plat->multicast_filter_bins = 64;

	if (!device_property_read_u32(dev, "snps,perfect-filter-entries", &val))
		plat->unicast_filter_entries = val;
	else
		plat->unicast_filter_entries = 65;

	if (!device_property_read_u32(dev, "max-frame-size", &val) &&
	    val > ETH_HLEN + ETH_FCS_LEN)
		plat->maxmtu = val - ETH_HLEN - ETH_FCS_LEN;

	if (!device_property_read_u32(dev, "snps,pbl", &val))
		plat->dma_cfg->pbl = val;
	else
		plat->dma_cfg->pbl = 16;

	plat->dma_cfg->txpbl = plat->dma_cfg->pbl;
	plat->dma_cfg->rxpbl = plat->dma_cfg->pbl;
	plat->dma_cfg->pblx8 = true;

	phytium_dwmac_parse_axi(dev, plat);

	return stmmac_pltfr_probe(pdev, plat, &stmmac_res);
}

static const struct acpi_device_id phytium_dwmac_acpi_match[] = {
	{ "PHYT0004", 0 },
	{ "FTGM0001", 0 },
	{ }
};
MODULE_DEVICE_TABLE(acpi, phytium_dwmac_acpi_match);

static struct platform_driver phytium_dwmac_driver = {
	.probe  = phytium_dwmac_probe,
	.remove = stmmac_pltfr_remove,
	.driver = {
		.name           = "phytium-dwmac",
		.pm             = &stmmac_pltfr_pm_ops,
		.acpi_match_table = ACPI_PTR(phytium_dwmac_acpi_match),
	},
};
module_platform_driver(phytium_dwmac_driver);

MODULE_DESCRIPTION("Phytium D2000 ACPI DWMAC platform driver");
MODULE_AUTHOR("Antigravity");
MODULE_LICENSE("GPL");
