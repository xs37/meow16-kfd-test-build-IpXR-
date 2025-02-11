//
//  meowfinder.c
//  meow
//
//  Created by doraaa on 2023/10/15.
//

#include "meowfinder.h"
#include "kfd_meow-Swift.h"

static unsigned char header[0x4000];

static uint64_t find_prev_insn_kread(uint64_t vaddr, uint32_t num, uint32_t insn, uint32_t mask) {
    uint32_t from = 0;
    while(num) {
        from = kread32_kfd(vaddr);
        if((from & mask) == (insn & mask)) {
            return vaddr;
        }
        vaddr -= 4;
        num--;
    }
    return 0;
}

static unsigned char *
boyermoore_horspool_memmem(const unsigned char* haystack, size_t hlen,
                           const unsigned char* needle,   size_t nlen)
{
    size_t last, scan = 0;
    size_t bad_char_skip[UCHAR_MAX + 1]; /* Officially called:
                                          * bad character shift */

    /* Sanity checks on the parameters */
    if (nlen <= 0 || !haystack || !needle)
        return NULL;

    /* ---- Preprocess ---- */
    /* Initialize the table to default value */
    /* When a character is encountered that does not occur
     * in the needle, we can safely skip ahead for the whole
     * length of the needle.
     */
    for (scan = 0; scan <= UCHAR_MAX; scan = scan + 1)
        bad_char_skip[scan] = nlen;

    /* C arrays have the first byte at [0], therefore:
     * [nlen - 1] is the last byte of the array. */
    last = nlen - 1;

    /* Then populate it with the analysis of the needle */
    for (scan = 0; scan < last; scan = scan + 1)
        bad_char_skip[needle[scan]] = last - scan;

    /* ---- Do the matching ---- */

    /* Search the haystack, while the needle can still be within it. */
    while (hlen >= nlen)
    {
        /* scan from the end of the needle */
        for (scan = last; haystack[scan] == needle[scan]; scan = scan - 1)
            if (scan == 0) /* If the first byte matches, we've found it. */
                return (void *)haystack;

        /* otherwise, we need to skip some bytes and start again.
           Note that here we are getting the skip value based on the last byte
           of needle, no matter where we didn't match. So if needle is: "abcd"
           then we are skipping based on 'd' and that value will be 4, and
           for "abcdd" we again skip on 'd' but the value will be only 1.
           The alternative of pretending that the mismatched character was
           the last character is slower in the normal case (E.g. finding
           "abcd" in "...azcd..." gives 4 by using 'd' but only
           4-2==2 using 'z'. */
        hlen     -= bad_char_skip[haystack[last]];
        haystack += bad_char_skip[haystack[last]];
    }

    return NULL;
}

uint64_t bof64(uint64_t ptr) {
    for (; ptr >= 0; ptr -= 4) {
        uint32_t op;
        kreadbuf_kfd((uint64_t)ptr, &op, 4);
        if ((op & 0xffc003ff) == 0x910003FD) {
            unsigned delta = (op >> 10) & 0xfff;
            if ((delta & 0xf) == 0) {
                uint64_t prev = ptr - ((delta >> 4) + 1) * 4;
                uint32_t au;
                kreadbuf_kfd((uint64_t)prev, &au, 4);
                if ((au & 0xffc003e0) == 0xa98003e0) {
                    return prev;
                }
                while (ptr > 0) {
                    ptr -= 4;
                    kreadbuf_kfd((uint64_t)ptr, &au, 4);
                    if ((au & 0xffc003ff) == 0xD10003ff && ((au >> 10) & 0xfff) == delta + 0x10) {
                        return ptr;
                    }
                    if ((au & 0xffc003e0) != 0xa90003e0) {
                        ptr += 4;
                        break;
                    }
                }
            }
        }
    }
    return 0;
}

static uint64_t search_proc_set_ucred_kread16(uint64_t vaddr, uint64_t size) {
    vaddr += 0x400000; // maybe
    
    for(uint64_t i = 0; i < (size - 0x400000); i += 4) {
        if(kread32_kfd(vaddr + i + 0) == 0x910023e3) { // add x3, sp, #0x8
            if(kread32_kfd(vaddr + i + 4) == 0x528000a0) { // mov w0, #0x5
                if(kread32_kfd(vaddr + i + 8) == 0x52800402) { // mov w2, #0x20
                    if(kread32_kfd(vaddr + i + 12) == 0x52800104) { // mov w4, #0x8
                        if((kread32_kfd(vaddr + i + 16) & 0xfc000000) == 0x94000000) { // bl _xxx
                            // pongoOS
                            // Most reliable marker of a stack frame seems to be "add x29, sp, 0x...".
                            uint64_t frame = find_prev_insn_kread(vaddr + i, 2000, 0x910003fd, 0xff8003ff);
                            if(frame) {
                                // Now find the insn that decrements sp. This can be either
                                // "stp ..., ..., [sp, -0x...]!" or "sub sp, sp, 0x...".
                                // Match top bit of imm on purpose, since we only want negative offsets.
                                uint64_t start = find_prev_insn_kread(frame, 10, 0xa9a003e0, 0xffe003e0);
                                if(start) {
                                    return start;
                                }
                                else {
                                    start = find_prev_insn_kread(frame, 10, 0xd10003ff, 0xff8003ff);
                                    if(start) {
                                        return start;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}

static uint64_t search_proc_set_ucred_kread15(uint64_t vaddr, uint64_t size) {
    vaddr += 0x300000;
    const uint8_t data[16] = { 0xa0, 0x00, 0x80, 0x52, 0xe1, 0x03, 0x02, 0xaa, 0x02, 0x04, 0x80, 0x52, 0x04, 0x01, 0x80, 0x52 };
    int current_offset = 0;
    while (current_offset < size) {
        uint8_t* buffer = malloc(0x1000);
        kreadbuf_kfd(vaddr + current_offset, buffer, 0x1000);
        uint8_t *str;
        str = boyermoore_horspool_memmem(buffer, 0x1000, data, sizeof(data));
        if (str) {
            uint64_t bof = bof64(str - buffer + vaddr + current_offset);
            return bof;
        }
        current_offset += 0x1000;
    }
    return 0;
}

static uint64_t search_search_add_x0_x0_0x40_kread(uint64_t vaddr, uint64_t size) {
    vaddr += 0x20000;
    for(uint64_t i = 0; i < (size - 0x400000); i += 4)
    {
        if(kread32_kfd(vaddr + i + 0) == 0x91010000)
        {
            if(kread32_kfd(vaddr + i + 4) == 0xd65f03c0)
            {
                return vaddr + i;
            }
        }
    }
    return 0;
}

static uint64_t search_search_container_init_kread(uint64_t vaddr, uint64_t size) {
    vaddr += 0x500000; // maybe
    
    //0x000140B2 [0x82408252] 0x8200A072 0x030080D2
    for(uint64_t i = 0; i < (size - 0x400000); i += 4) {
        if(kread32_kfd(vaddr + i + 0) == 0xB2400100) { //orr  x0, x8, #0x1
            if(kread32_kfd(vaddr + i + 8) == 0x72A00082) { //movk  w2, #0x4, lsl #16
                if(kread32_kfd(vaddr + i + 12) == 0xD2800003) { //mov  x3, #0x0
                    return vaddr + i - 0x30;
                }
            }
        }
    }
    return 0;
}

static uint64_t search_search_iosurface_trapforindex_kread(uint64_t vaddr, uint64_t size) {
    vaddr += 0x500000; // maybe
    
    // 0xF44FBEA9 0xFD7B01A9 0xFD430091 0xF30301AA
    // 0x080040F9 0x08E142F9 0xE10302AA 0x00013FD6
    
    // 0xA9BE4FF4 0xA9017BFD 0x910043FD 0xAA0103F3
    // 0xF9400008 0xF942E108 0xAA0203E1 0xD63F0100
    
    for(uint64_t i = 0; i < (size - 0x400000); i += 4) {
        if(kread32_kfd(vaddr + i + 0) == 0xA9BE4FF4) { //
            if(kread32_kfd(vaddr + i + 4) == 0xA9017BFD) { //
                if(kread32_kfd(vaddr + i + 8) == 0x910043FD) { //
                    if(kread32_kfd(vaddr + i + 12) == 0xAA0103F3) { //
                        if(kread32_kfd(vaddr + i + 16) == 0xF9400008) { //
                            if(kread32_kfd(vaddr + i + 20) == 0xF942E108) { //
                                if(kread32_kfd(vaddr + i + 24) == 0xAA0203E1) { //
                                    if(kread32_kfd(vaddr + i + 28) == 0xD63F0100) { //
                                        return vaddr + i;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return 0;
}

void offsetfinder64_kread(void)
{
    if(!kernel_base) return;
    
    memset(&header, 0, 0x4000);
    kreadbuf_kfd(kernel_base, &header, 0x4000);
    
    const struct mach_header_64 *hdr = (struct mach_header_64 *)header;
    const uint8_t *q = NULL;
    
    uint64_t text_exec_addr = 0;
    uint64_t text_exec_size = 0;
    
    uint64_t plk_text_exec_addr = 0;
    uint64_t plk_text_exec_size = 0;
    
    uint64_t data_data_size = 0;
    uint64_t data_data_addr = 0;
    
    q = header + sizeof(struct mach_header_64);
    for (int i = 0; i < hdr->ncmds; i++) {
        const struct load_command *cmd = (struct load_command *)q;
        if (cmd->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (struct segment_command_64 *)q;
            if (!strcmp(seg->segname, "__TEXT_EXEC")) {
                const struct section_64 *sec = (struct section_64 *)(seg + 1);
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    if (!strcmp(sec[j].sectname, "__text")) {
                        text_exec_addr = sec[j].addr;
                        text_exec_size = sec[j].size;
                        printf("--------------------------------\n");
                        printf("%s.%s\n", seg->segname, sec[j].sectname);
                        printf("    addr: %016llx\n", text_exec_addr);
                        printf("    size: %016llx\n", text_exec_size);
                    }
                }
            }
            
            if (!strcmp(seg->segname, "__PLK_TEXT_EXEC")) {
                const struct section_64 *sec = (struct section_64 *)(seg + 1);
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    if (!strcmp(sec[j].sectname, "__text")) {
                        plk_text_exec_addr = sec[j].addr;
                        plk_text_exec_size = sec[j].size;
                        printf("--------------------------------\n");
                        printf("%s.%s\n", seg->segname, sec[j].sectname);
                        printf("    addr: %016llx\n", plk_text_exec_addr);
                        printf("    size: %016llx\n", plk_text_exec_size);
                    }
                }
            }
            
            if (!strcmp(seg->segname, "__DATA")) {
                const struct section_64 *sec = (struct section_64 *)(seg + 1);
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    if (!strcmp(sec[j].sectname, "__data")) {
                        data_data_addr = sec[j].addr;
                        data_data_size = sec[j].size;
                        printf("--------------------------------\n");
                        printf("%s.%s\n", seg->segname, sec[j].sectname);
                        printf("    addr: %016llx\n", data_data_addr);
                        printf("    size: %016llx\n", data_data_size);
                    }
                }
            }
        }
        q = q + cmd->cmdsize;
    }
    
    if(plk_text_exec_size)
    {
        add_x0_x0_0x40 = search_search_add_x0_x0_0x40_kread(plk_text_exec_addr, plk_text_exec_size);
    }
    if(!add_x0_x0_0x40)
    {
        add_x0_x0_0x40 = search_search_add_x0_x0_0x40_kread(text_exec_addr, text_exec_size);
    }
    if(isAvailable() >= 8) {
        proc_set_ucred = search_proc_set_ucred_kread16(text_exec_addr, text_exec_size);
        container_init = search_search_container_init_kread(text_exec_addr, text_exec_size);
        iogettargetand = search_search_iosurface_trapforindex_kread(text_exec_addr, text_exec_size);
        printf("container_init : %016llx\n", container_init);
        printf("iogettargetand : %016llx\n", iogettargetand);
    } else if(isAvailable() >= 4) {
        proc_set_ucred = search_proc_set_ucred_kread15(text_exec_addr, text_exec_size);
        printf("proc_set_ucred : %016llx\n", proc_set_ucred);
    }
    
    empty_kdata    = data_data_addr + 0x1600;
    //empty_kdata     = 0xFFFFFFF007841000 + 0x200;
    
    printf("add_x0_x0_0x40 : %016llx\n", add_x0_x0_0x40);
    printf("empty_kdata    : %016llx\n", empty_kdata);
}

void Fugu15KPF(void) {
    objcbridge *obj = [[objcbridge alloc] init];
    mach_vm_alloc = [obj find_mach_vm_allocate];
}
