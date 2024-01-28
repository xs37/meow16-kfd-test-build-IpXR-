//
//  kcall16.h
//  meow
//
//  Created by mizole on 2023/12/21.
//

#ifndef kcall16_h
#define kcall16_h

#include <stdint.h>
#include <stdio.h>
#include <CoreFoundation/CoreFoundation.h>
#include "IOKit/IOKitLib.h"
#include "libmeow.h"
#include "libkfd.h"
#include "IOSurface_Primitives.h"

#define VM_KERN_MEMORY_BSD 2

bool init_kcall(void);
bool setup_client(void);
uint64_t eary_kcall(uint64_t addr, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3, uint64_t x4, uint64_t x5, uint64_t x6);
uint64_t kalloc(size_t size);

#endif /* kcall16_h */
