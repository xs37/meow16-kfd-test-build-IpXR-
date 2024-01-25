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

bool init_kcall(void);
uint64_t eary_kcall(uint64_t addr, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3, uint64_t x4, uint64_t x5, uint64_t x6);
uint64_t eary_kalloc(size_t ksize);

#endif /* kcall16_h */
