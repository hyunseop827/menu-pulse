#import "Monitors.h"

#import <mach/mach.h>

typedef struct {
    uint32_t user;
    uint32_t system;
    uint32_t idle;
    uint32_t nice;
} MPTicks;

uint64_t MPUnsignedTickDelta(uint32_t current, uint32_t previous) {
    // host_cpu_load_info exposes 32-bit counters. Unsigned subtraction keeps
    // the elapsed ticks correct when a counter wraps through UINT32_MAX.
    return (uint64_t)(uint32_t)(current - previous);
}

NSNumber *MPPercentOfTotal(double used, double total) {
    if (!isfinite(used) || !isfinite(total) || total <= 0.0) {
        return nil;
    }
    return @(fmax(0.0, fmin(100.0, used / total * 100.0)));
}

@interface MPCPUMonitor ()
@property(nonatomic) BOOL hasPreviousTicks;
@property(nonatomic) MPTicks previousTicks;
@end

@implementation MPCPUMonitor

- (BOOL)hasBaseline {
    return self.hasPreviousTicks;
}

- (NSNumber *)usagePercent {
    host_cpu_load_info_data_t info;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host = mach_host_self();
    if (host == MACH_PORT_NULL) {
        return nil;
    }

    kern_return_t result = host_statistics(
        host,
        HOST_CPU_LOAD_INFO,
        (host_info_t)&info,
        &count
    );
    mach_port_deallocate(mach_task_self(), host);

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

    uint64_t user = MPUnsignedTickDelta(ticks.user, self.previousTicks.user);
    uint64_t system = MPUnsignedTickDelta(ticks.system, self.previousTicks.system);
    uint64_t idle = MPUnsignedTickDelta(ticks.idle, self.previousTicks.idle);
    uint64_t nice = MPUnsignedTickDelta(ticks.nice, self.previousTicks.nice);
    uint64_t totalTicks = user + system + idle + nice;
    self.previousTicks = ticks;

    return MPPercentOfTotal((double)(totalTicks - idle), (double)totalTicks);
}

- (void)reset {
    self.hasPreviousTicks = NO;
}

@end

@implementation MPMemoryMonitor

+ (NSNumber *)usagePercent {
    vm_statistics64_data_t stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    if (host == MACH_PORT_NULL) {
        return nil;
    }

    kern_return_t result = host_statistics64(
        host,
        HOST_VM_INFO64,
        (host_info64_t)&stats,
        &count
    );
    mach_port_deallocate(mach_task_self(), host);

    if (result != KERN_SUCCESS) {
        return nil;
    }

    uint64_t pageSize = (uint64_t)vm_kernel_page_size;
    uint64_t total = [[NSProcessInfo processInfo] physicalMemory];
    uint64_t appPages = (uint64_t)stats.internal_page_count;
    uint64_t wiredPages = (uint64_t)stats.wire_count;
    uint64_t compressedPages = (uint64_t)stats.compressor_page_count;
    uint64_t used = (appPages + wiredPages + compressedPages) * pageSize;

    return MPPercentOfTotal((double)used, (double)total);
}

@end

@implementation MPDiskMonitor

+ (NSNumber *)usagePercentForPath:(NSString *)path availableBytes:(uint64_t *)availableBytes {
    if (availableBytes) {
        *availableBytes = 0;
    }

    // Important-usage capacity includes purgeable space, matching the
    // available space shown by Finder and System Settings. Some volumes, such
    // as nobrowse mounts, report it as 0, so the plain free space is a floor.
    NSURL *url = [NSURL fileURLWithPath:path];
    NSDictionary<NSURLResourceKey, id> *values = [url resourceValuesForKeys:@[
        NSURLVolumeTotalCapacityKey,
        NSURLVolumeAvailableCapacityKey,
        NSURLVolumeAvailableCapacityForImportantUsageKey,
    ] error:NULL];
    NSNumber *totalNumber = values[NSURLVolumeTotalCapacityKey];
    NSNumber *freeNumber = values[NSURLVolumeAvailableCapacityKey];
    NSNumber *importantNumber = values[NSURLVolumeAvailableCapacityForImportantUsageKey];
    if (!totalNumber || (!freeNumber && !importantNumber)) {
        return nil;
    }

    double total = totalNumber.doubleValue;
    double available = fmax(freeNumber.doubleValue, importantNumber.doubleValue);
    available = fmax(0.0, fmin(available, total));
    NSNumber *percent = MPPercentOfTotal(total - available, total);
    if (percent && availableBytes) {
        *availableBytes = (uint64_t)available;
    }
    return percent;
}

@end
