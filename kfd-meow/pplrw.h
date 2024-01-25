//
//  pplrw.h
//  kfd-meow
//
//  Created by mizole on 2024/01/08.
//

#ifndef pplrw_h
#define pplrw_h

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#include "hexdump.h"
#include "IOSurface_Primitives.h"
#include "libkfd.h"

int test_pplrw(void);
int test_ktrr(void);

#endif /* pplrw_h */
