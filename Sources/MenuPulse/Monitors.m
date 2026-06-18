#import "Monitors.h"

#import <mach/mach.h>
#import <mach/mach_host.h>

typedef struct {
    uint32_t user;
    uint32_t system;
    uint32_t idle;
    uint32_t nice;
} MPTicks;

static uint64_t MPDiffTicks(uint32_t current, uint32_t previous) {
    return current >= previous ? (uint64_t)(current - previous) : 0;
}

@interface MPCPUMonitor ()
@property(nonatomic) BOOL hasPreviousTicks;
@property(nonatomic) MPTicks previousTicks;
@end

@implementation MPCPUMonitor

- (NSNumber *)usagePercent {
    host_cpu_load_info_data_t info;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    kern_return_t result = host_statistics(
        mach_host_self(),
        HOST_CPU_LOAD_INFO,
        (host_info_t)&info,
        &count
    );

    if (result != KERN_SUCCESS) {
        return nil;
    }

    MPTicks ticks = {
        .user = info.cpu_ticks[CPU_STATE_USER],
        .system = info.cpu_ticks[CPU_STATE_SYSTEM],
        .idle = info.cpu_ticks[CPU_STATE_IDLE],
        .nice = info.cpu_ticks[CPU_STATE_NICE],
    };

    if (!self.hasPreviousTicks) {
        self.previousTicks = ticks;
        self.hasPreviousTicks = YES;
        return nil;
    }

    uint64_t user = MPDiffTicks(ticks.user, self.previousTicks.user);
    uint64_t system = MPDiffTicks(ticks.system, self.previousTicks.system);
    uint64_t idle = MPDiffTicks(ticks.idle, self.previousTicks.idle);
    uint64_t nice = MPDiffTicks(ticks.nice, self.previousTicks.nice);
    uint64_t totalTicks = user + system + idle + nice;
    uint64_t activeTicks = totalTicks - idle;
    self.previousTicks = ticks;

    if (totalTicks == 0) {
        return nil;
    }

    return @(((double)activeTicks / (double)totalTicks) * 100.0);
}

@end

@implementation MPMemoryMonitor

+ (NSNumber *)usagePercent {
    vm_statistics64_data_t stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t result = host_statistics64(
        mach_host_self(),
        HOST_VM_INFO64,
        (host_info64_t)&stats,
        &count
    );

    if (result != KERN_SUCCESS) {
        return nil;
    }

    uint64_t pageSize = (uint64_t)vm_kernel_page_size;
    uint64_t total = [[NSProcessInfo processInfo] physicalMemory];
    uint64_t appPages = (uint64_t)stats.internal_page_count;
    uint64_t wiredPages = (uint64_t)stats.wire_count;
    uint64_t compressedPages = (uint64_t)stats.compressor_page_count;
    uint64_t used = (appPages + wiredPages + compressedPages) * pageSize;

    if (total == 0) {
        return nil;
    }

    double percent = (double)used / (double)total * 100.0;
    percent = fmax(0.0, fmin(100.0, percent));
    return @(percent);
}

@end

@implementation MPDiskMonitor

+ (NSNumber *)usagePercent {
    return [self usagePercentForPath:NSHomeDirectory()];
}

+ (NSNumber *)usagePercentForPath:(NSString *)path {
    NSError *error = nil;
    NSDictionary<NSFileAttributeKey, id> *attributes =
        [[NSFileManager defaultManager] attributesOfFileSystemForPath:path error:&error];

    NSNumber *totalNumber = attributes[NSFileSystemSize];
    NSNumber *freeNumber = attributes[NSFileSystemFreeSize];
    double total = totalNumber.doubleValue;
    double free = freeNumber.doubleValue;

    if (error || total <= 0) {
        return nil;
    }

    double percent = (total - free) / total * 100.0;
    percent = fmax(0.0, fmin(100.0, percent));
    return @(percent);
}

@end
