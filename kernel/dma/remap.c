// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (c) 2014 The Linux Foundation
 */
#include <linux/dma-map-ops.h>
#include <linux/err.h>
#include <linux/genalloc.h>
#include <linux/sizes.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>

struct page **dma_common_find_pages(void *cpu_addr)
{
	struct vm_struct *area = find_vm_area(cpu_addr);

	if (!area || area->flags != VM_DMA_COHERENT)
		return NULL;
	return area->pages;
}

/*
 * Remaps an array of PAGE_SIZE pages into another vm_area.
 * Cannot be used in non-sleeping contexts
 */
void *dma_common_pages_remap(struct page **pages, size_t size,
			 pgprot_t prot, const void *caller)
{
	void *vaddr;

	vaddr = vmap(pages, PAGE_ALIGN(size) >> PAGE_SHIFT,
		     VM_DMA_COHERENT, prot);
	if (vaddr)
		find_vm_area(vaddr)->pages = pages;
	return vaddr;
}

/*
 * Remaps an allocated contiguous region into another vm_area.
 * Cannot be used in non-sleeping contexts
 */
void *dma_common_contiguous_remap(struct page *page, size_t size,
			pgprot_t prot, const void *caller)
{
	int count = PAGE_ALIGN(size) >> PAGE_SHIFT;
	struct page **pages;
	void *vaddr;
	int i;

	pages = kvmalloc_array(count, sizeof(struct page *), GFP_KERNEL);
	if (!pages)
		return NULL;
	for (i = 0; i < count; i++)
		pages[i] = nth_page(page, i);
	vaddr = vmap(pages, count, VM_DMA_COHERENT, prot);
	kvfree(pages);

	return vaddr;
}

/*
 * Unmaps a range previously mapped by dma_common_*_remap
 */
void dma_common_free_remap(void *cpu_addr, size_t size)
{
	struct vm_struct *area = find_vm_area(cpu_addr);

	if (!area || area->flags != VM_DMA_COHERENT) {
		WARN(1, "trying to free invalid coherent area: %p\n", cpu_addr);
		return;
	}

	unmap_kernel_range((unsigned long)cpu_addr, PAGE_ALIGN(size));
	vunmap(cpu_addr);
}
#ifdef CONFIG_DMA_DIRECT_REMAP
#define DEFAULT_DMA_COHERENT_POOL_SIZE  SZ_256K

static gfp_t qcom_dma_atomic_pool_gfp(void)
{
	if (IS_ENABLED(CONFIG_ZONE_DMA))
		return GFP_DMA;
	if (IS_ENABLED(CONFIG_ZONE_DMA32))
		return GFP_DMA32;
	return GFP_KERNEL;
}

/*
 * CAF/QC compatibility: standalone atomic pool constructor used by
 * drivers/iommu/dma-mapping-fast.c. The generic atomic pools live in
 * kernel/dma/pool.c on 5.10; this only serves vendor fastmap users.
 */
struct gen_pool *__init __dma_atomic_pool_init(void)
{
	size_t pool_size = DEFAULT_DMA_COHERENT_POOL_SIZE;
	unsigned int pool_size_order = get_order(pool_size);
	unsigned long nr_pages = pool_size >> PAGE_SHIFT;
	struct page *page;
	struct gen_pool *pool;
	void *addr;
	int ret;

	if (dev_get_cma_area(NULL))
		page = dma_alloc_from_contiguous(NULL, nr_pages,
						 pool_size_order, false);
	else
		page = alloc_pages(qcom_dma_atomic_pool_gfp(), pool_size_order);
	if (!page)
		goto out;

	arch_dma_prep_coherent(page, pool_size);

	pool = gen_pool_create(PAGE_SHIFT, -1);
	if (!pool)
		goto free_page;

	addr = dma_common_contiguous_remap(page, pool_size,
					   pgprot_dmacoherent(PAGE_KERNEL),
					   __builtin_return_address(0));
	if (!addr)
		goto destroy_genpool;

	ret = gen_pool_add_virt(pool, (unsigned long)addr,
				page_to_phys(page), pool_size, -1);
	if (ret)
		goto remove_mapping;
	gen_pool_set_algo(pool, gen_pool_first_fit_order_align, NULL);

	pr_info("DMA: preallocated %zu KiB pool for atomic allocations\n",
		pool_size / 1024);
	return pool;

remove_mapping:
	dma_common_free_remap(addr, pool_size);
destroy_genpool:
	gen_pool_destroy(pool);
free_page:
	if (!dma_release_from_contiguous(NULL, page, nr_pages))
		__free_pages(page, pool_size_order);
out:
	pr_err("DMA: failed to allocate %zu KiB pool for atomic coherent allocation\n",
		pool_size / 1024);
	return ERR_PTR(-ENOMEM);
}
#endif /* CONFIG_DMA_DIRECT_REMAP */
