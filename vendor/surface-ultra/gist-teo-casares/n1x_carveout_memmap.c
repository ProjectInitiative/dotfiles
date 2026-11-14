// Give the NVIDIA N1x GPU carveout a memmap on the Surface Laptop Ultra.
//
// The firmware leaves the GPU's carveouts (IORT RMR ranges) out of the EFI
// memory map, so Linux has no struct pages for them, and the NVIDIA driver's
// vmap() of allocations that mix them with RAM fails (vmalloc.c pfn_valid
// WARN, "Unable to allocate LUT memory"). On the Dell/ASUS N1x laptops the
// firmware lists the carveout as reserved memory, which gives it a memmap but
// no linear mapping. This reproduces that state: memremap_pages() with
// MEMORY_DEVICE_PRIVATE adds struct pages without mapping the range, so the
// CPU never touches the carveout unless a driver maps it. Load before nvidia.
#include <linux/module.h>
#include <linux/memremap.h>
#include <linux/mm.h>
#include <linux/pagemap.h>

/* Carveout ranges without a memmap (the rest of each RMR range has one). */
static struct range n1x_ranges[] = {
	{ .start = 0x200000000ULL, .end = 0x2ffffffffULL },	/* 4 GiB display block */
	{ .start = 0x0a1600000ULL, .end = 0x0b7ffffffULL },	/* RMR range 3, below the RAM section */
};

static struct dev_pagemap n1x_pgmaps[ARRAY_SIZE(n1x_ranges)];
static bool n1x_mapped[ARRAY_SIZE(n1x_ranges)];

static void n1x_folio_free(struct folio *folio)
{
	/* Nothing to free: the pages belong to the firmware carveout. */
}

static vm_fault_t n1x_migrate_to_ram(struct vm_fault *vmf)
{
	/* No user mappings ever point at these pages. */
	return VM_FAULT_SIGBUS;
}

static const struct dev_pagemap_ops n1x_ops = {
	.folio_free = n1x_folio_free,
	.migrate_to_ram = n1x_migrate_to_ram,
};

/*
 * Device-private pages start with refcount 0, so a get_page()/put_page() pair
 * from a driver would "free" them. Hold one reference on each, like the
 * reserved pages the Dell/ASUS firmware's memmap has, and drop it on unload.
 */
static void n1x_hold_pages(struct dev_pagemap *pgmap, bool hold)
{
	unsigned long pfn;

	for (pfn = PHYS_PFN(pgmap->range.start);
	     pfn <= PHYS_PFN(pgmap->range.end); pfn++) {
		struct page *page = pfn_to_page(pfn);

		if (hold) {
			zone_device_page_init(page, pgmap, 0);
			if (PageLocked(page))
				unlock_page(page);
		} else if (page_ref_count(page) == 1) {
			put_page(page);
		}
		if ((pfn & 0xffff) == 0)
			cond_resched();
	}
}

static void n1x_unmap_all(void)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(n1x_ranges); i++) {
		if (n1x_mapped[i]) {
			n1x_hold_pages(&n1x_pgmaps[i], false);
			memunmap_pages(&n1x_pgmaps[i]);
		}
		n1x_mapped[i] = false;
	}
}

static int __init n1x_init(void)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(n1x_ranges); i++) {
		struct range *r = &n1x_ranges[i];
		struct dev_pagemap *pgmap = &n1x_pgmaps[i];
		void *ret;

		if (pfn_valid(PHYS_PFN(r->start)) || pfn_valid(PHYS_PFN(r->end))) {
			pr_info("n1x_carveout: %#llx-%#llx already has a memmap, skipping\n",
				r->start, r->end);
			continue;
		}

		pgmap->type = MEMORY_DEVICE_PRIVATE;
		pgmap->range = *r;
		pgmap->nr_range = 1;
		pgmap->ops = &n1x_ops;
		pgmap->owner = &n1x_ranges;

		ret = memremap_pages(pgmap, NUMA_NO_NODE);
		if (IS_ERR(ret)) {
			pr_err("n1x_carveout: memremap_pages %#llx-%#llx failed: %ld\n",
			       r->start, r->end, PTR_ERR(ret));
			n1x_unmap_all();
			return PTR_ERR(ret);
		}
		n1x_mapped[i] = true;
		n1x_hold_pages(pgmap, true);
		pr_info("n1x_carveout: memmap for %#llx-%#llx (pfn_valid now %d, refcount %d)\n",
			r->start, r->end, pfn_valid(PHYS_PFN(r->start)),
			page_ref_count(pfn_to_page(PHYS_PFN(r->start))));
	}
	return 0;
}

static void __exit n1x_exit(void)
{
	n1x_unmap_all();
}

module_init(n1x_init);
module_exit(n1x_exit);
MODULE_DESCRIPTION("memmap for the NVIDIA N1x GPU carveout (Surface Laptop Ultra)");
MODULE_LICENSE("GPL");
