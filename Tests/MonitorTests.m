#import "Monitors.h"
#import "TemperatureReader.h"

#import <Foundation/Foundation.h>
#import <mach/mach.h>

extern uint64_t MPUnsignedTickDelta(uint32_t current, uint32_t previous);

static NSUInteger MPFailureCount = 0;

static void MPAssert(BOOL condition, NSString *message) {
    if (condition) {
        return;
    }

    MPFailureCount += 1;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static void MPTestHostPortReferences(void) {
    mach_port_t host = mach_host_self();
    MPAssert(host != MACH_PORT_NULL, @"mach_host_self should return a host port");
    if (host == MACH_PORT_NULL) {
        return;
    }

    mach_port_urefs_t before = 0;
    kern_return_t beforeResult =
        mach_port_get_refs(mach_task_self(), host, MACH_PORT_RIGHT_SEND, &before);
    MPAssert(beforeResult == KERN_SUCCESS, @"should read host port references before sampling");

    for (NSUInteger index = 0; index < 2000; index += 1) {
        [MPMemoryMonitor usagePercent];
    }

    MPCPUMonitor *cpuMonitor = [[MPCPUMonitor alloc] init];
    for (NSUInteger index = 0; index < 2000; index += 1) {
        [cpuMonitor usagePercent];
    }

    mach_port_urefs_t after = 0;
    kern_return_t afterResult =
        mach_port_get_refs(mach_task_self(), host, MACH_PORT_RIGHT_SEND, &after);
    MPAssert(afterResult == KERN_SUCCESS, @"should read host port references after sampling");
    MPAssert(after == before, @"CPU and memory sampling must not leak host port references");
    mach_port_deallocate(mach_task_self(), host);
}

static void MPTestCPUMonitorReset(void) {
    MPCPUMonitor *monitor = [[MPCPUMonitor alloc] init];
    MPAssert(!monitor.hasBaseline, @"a new CPU monitor should not have a baseline");
    MPAssert([monitor usagePercent] == nil, @"first CPU sample should establish a baseline");
    MPAssert(monitor.hasBaseline, @"a successful first CPU sample should establish a baseline");
    [monitor usagePercent];
    [monitor reset];
    MPAssert(!monitor.hasBaseline, @"reset should clear the CPU baseline");
    MPAssert([monitor usagePercent] == nil, @"first CPU sample after reset should establish a new baseline");
}

static void MPTestCPUTickDelta(void) {
    MPAssert(MPUnsignedTickDelta(125, 100) == 25,
             @"CPU tick delta should handle counters that have not wrapped");
    MPAssert(MPUnsignedTickDelta(3, UINT32_MAX - 1) == 5,
             @"CPU tick delta should preserve elapsed ticks across a 32-bit wrap");
    MPAssert(MPUnsignedTickDelta(0, UINT32_MAX) == 1,
             @"CPU tick delta should handle the UINT32_MAX to zero boundary");
}

static void MPTestMemoryRange(void) {
    NSNumber *usage = [MPMemoryMonitor usagePercent];
    MPAssert(usage != nil, @"memory usage should be available");
    MPAssert(usage.doubleValue >= 0.0 && usage.doubleValue <= 100.0,
             @"memory usage should be between zero and one hundred percent");
}

static void MPTestDiskSnapshot(void) {
    uint64_t availableBytes = 0;
    NSNumber *usage = [MPDiskMonitor usagePercentForPath:NSHomeDirectory()
                                          availableBytes:&availableBytes];
    MPAssert(usage != nil, @"disk usage should be available");
    MPAssert(usage.doubleValue >= 0.0 && usage.doubleValue <= 100.0,
             @"disk usage should be between zero and one hundred percent");
    MPAssert(availableBytes > 0, @"disk snapshot should include available bytes");

    availableBytes = UINT64_MAX;
    NSNumber *missingUsage = [MPDiskMonitor usagePercentForPath:@"/path/that/does/not/exist"
                                                 availableBytes:&availableBytes];
    MPAssert(missingUsage == nil, @"an unavailable disk path should not report usage");
    MPAssert(availableBytes == 0,
             @"a failed disk snapshot should clear its available byte result");
}

static void MPTestTemperatureCooldownCalculation(void) {
    MPAssert(MPTemperatureRetryAllowedForInterval(100.0, NAN, 300.0),
             @"temperature should retry when there is no prior failure");
    MPAssert(!MPTemperatureRetryAllowedForInterval(399.999, 100.0, 300.0),
             @"temperature should remain in cooldown before the boundary");
    MPAssert(MPTemperatureRetryAllowedForInterval(400.0, 100.0, 300.0),
             @"temperature should retry at the cooldown boundary");
    MPAssert(!MPTemperatureRetryAllowedForInterval(99.0, 100.0, 300.0),
             @"a regressed clock should not bypass the temperature cooldown");
}

int main(void) {
    @autoreleasepool {
        MPTestHostPortReferences();
        MPTestCPUMonitorReset();
        MPTestCPUTickDelta();
        MPTestMemoryRange();
        MPTestDiskSnapshot();
        MPTestTemperatureCooldownCalculation();

        if (MPFailureCount > 0) {
            fprintf(stderr, "%lu monitor test(s) failed\n", (unsigned long)MPFailureCount);
            return 1;
        }

        puts("All monitor tests passed.");
    }

    return 0;
}
