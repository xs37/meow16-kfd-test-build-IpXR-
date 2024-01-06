//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <Foundation/Foundation.h>
#include "libgrabkernel.h"
#include "libkfd.h"
#include "libmeow.h"

uint64_t _kfd = 0;

uint64_t kpoen_bridge(uint64_t puaf_method) {
    uint64_t exploit_type = (1 << puaf_method);
    _kfd = kopen(exploit_type);
    if(_kfd != 0)
        return _kfd;
    
    return 0;
}

uint64_t meow_and_kclose(uint64_t _kfd) {
    if(!isarm64e())
        meow();
    kclose(_kfd);
    return 0;
}
