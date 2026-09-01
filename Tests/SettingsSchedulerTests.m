#import "RefreshScheduler.h"
#import "SettingsStore.h"
#import "MemoryUserDefaults.h"

#import <Foundation/Foundation.h>
#import <math.h>

static NSUInteger MPFailureCount = 0;

static void MPAssert(BOOL condition, NSString *message) {
    if (condition) {
        return;
    }

    MPFailureCount += 1;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

static void MPAssertInterval(NSTimeInterval actual,
                             NSTimeInterval expected,
                             NSString *message) {
    MPAssert(fabs(actual - expected) < 0.0001, message);
}

@interface MPFakeMonotonicClock : NSObject <MPMonotonicClock>
@property(nonatomic) NSTimeInterval time;
@end

@implementation MPFakeMonotonicClock

- (NSTimeInterval)monotonicTime {
    return self.time;
}

@end

static NSUserDefaults *MPMakeIsolatedDefaults(void) {
    return [[MPMemoryUserDefaults alloc] init];
}

static void MPTestSettingsDefaultsAndPersistence(void) {
    NSUserDefaults *defaults = MPMakeIsolatedDefaults();
    [defaults setDouble:9.0 forKey:@"cpuRefreshInterval"];
    [defaults setDouble:9.0 forKey:@"ramRefreshInterval"];
    [defaults setDouble:9.0 forKey:@"temperatureRefreshInterval"];
    [defaults setDouble:9.0 forKey:@"diskRefreshInterval"];

    MPSettingsStore *store = [[MPSettingsStore alloc] initWithUserDefaults:defaults];
    MPAssert(store.showCPU, @"CPU should be enabled by default");
    MPAssert(store.showRAM, @"RAM should be enabled by default");
    MPAssert(!store.showTemperature, @"temperature should be disabled by default");
    MPAssert(!store.showDisk, @"disk should be disabled by default");
    MPAssert([store.temperatureUnit isEqualToString:MPTemperatureUnitCelsius],
             @"temperature should default to Celsius");
    MPAssertInterval(store.cpuRAMRefreshIntervalSeconds, 3.0,
                     @"CPU and RAM should default to a three-second refresh");

    NSArray<NSString *> *legacyKeys = @[
        @"cpuRefreshInterval",
        @"ramRefreshInterval",
        @"temperatureRefreshInterval",
        @"diskRefreshInterval",
    ];
    for (NSString *key in legacyKeys) {
        MPAssert([defaults objectForKey:key] == nil, @"legacy refresh keys should be removed");
    }

    store.showCPU = NO;
    store.showRAM = NO;
    store.showTemperature = YES;
    store.showDisk = YES;
    store.temperatureUnit = MPTemperatureUnitFahrenheit;
    store.cpuRAMRefreshIntervalSeconds = 1.0;

    MPSettingsStore *restored = [[MPSettingsStore alloc] initWithUserDefaults:defaults];
    MPAssert(!restored.showCPU && !restored.showRAM,
             @"disabled CPU and RAM settings should persist");
    MPAssert(restored.showTemperature && restored.showDisk,
             @"enabled temperature and disk settings should persist");
    MPAssert([restored.temperatureUnit isEqualToString:MPTemperatureUnitFahrenheit],
             @"Fahrenheit should persist");
    MPAssertInterval(restored.cpuRAMRefreshIntervalSeconds, 1.0,
                     @"one-second refresh should persist");

    restored.cpuRAMRefreshIntervalSeconds = 10.0;
    MPAssertInterval(restored.cpuRAMRefreshIntervalSeconds, 10.0,
                     @"ten-second refresh should be accepted");

}

static void MPTestSettingsValidationAndReset(void) {
    NSUserDefaults *defaults = MPMakeIsolatedDefaults();
    MPSettingsStore *store = [[MPSettingsStore alloc] initWithUserDefaults:defaults];

    [defaults setDouble:2.0 forKey:@"cpuRAMRefreshIntervalSeconds"];
    MPAssertInterval(store.cpuRAMRefreshIntervalSeconds, 3.0,
                     @"an unsupported stored refresh should fall back to three seconds");
    MPAssertInterval([defaults doubleForKey:@"cpuRAMRefreshIntervalSeconds"], 3.0,
                     @"an unsupported stored refresh should be repaired");

    store.cpuRAMRefreshIntervalSeconds = 99.0;
    MPAssertInterval(store.cpuRAMRefreshIntervalSeconds, 3.0,
                     @"an unsupported refresh setter value should use the default");

    [defaults setObject:@"Kelvin" forKey:@"temperatureUnit"];
    MPAssert([store.temperatureUnit isEqualToString:MPTemperatureUnitCelsius],
             @"an unsupported unit should fall back to Celsius");

    [defaults setBool:YES forKey:@"openAtLogin"];
    store.showCPU = NO;
    store.showRAM = NO;
    store.showTemperature = YES;
    store.showDisk = YES;
    store.temperatureUnit = MPTemperatureUnitFahrenheit;
    store.cpuRAMRefreshIntervalSeconds = 10.0;
    [store resetMetricSettings];

    MPAssert(store.showCPU && store.showRAM,
             @"reset should restore CPU and RAM visibility");
    MPAssert(!store.showTemperature && !store.showDisk,
             @"reset should restore temperature and disk visibility");
    MPAssert([store.temperatureUnit isEqualToString:MPTemperatureUnitCelsius],
             @"reset should restore Celsius");
    MPAssertInterval(store.cpuRAMRefreshIntervalSeconds, 3.0,
                     @"reset should restore the three-second refresh");
    MPAssert([defaults boolForKey:@"openAtLogin"],
             @"reset should not change login item preferences");

}

static MPRefreshScheduler *MPMakeScheduler(MPFakeMonotonicClock *clock,
                                           NSMutableArray<NSNumber *> *callbacks) {
    return [[MPRefreshScheduler alloc]
        initWithClock:clock
        callbackQueue:dispatch_get_main_queue()
        dueHandler:^(MPRefreshMetric metrics) {
            [callbacks addObject:@(metrics)];
        }];
}

static void MPTestSchedulerIntervals(void) {
    MPFakeMonotonicClock *clock = [[MPFakeMonotonicClock alloc] init];
    clock.time = 100.0;
    NSMutableArray<NSNumber *> *callbacks = [NSMutableArray array];
    MPRefreshScheduler *scheduler = MPMakeScheduler(clock, callbacks);
    scheduler.activeMetrics = MPRefreshMetricAll;
    [scheduler start];

    MPAssert(callbacks.count == 1 && callbacks.lastObject.unsignedIntegerValue == MPRefreshMetricAll,
             @"all newly active metrics should be due immediately");
    MPAssert(scheduler.isTimerArmed, @"an active scheduler should arm its timer");
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 3.0,
                     @"CPU and RAM should define the first deadline");

    clock.time = 102.9;
    MPAssert([scheduler processDueMetrics] == MPRefreshMetricNone,
             @"CPU and RAM should not run before three seconds");
    clock.time = 103.0;
    MPAssert([scheduler processDueMetrics] == (MPRefreshMetricCPU | MPRefreshMetricRAM),
             @"CPU and RAM should run every three seconds");

    clock.time = 130.0;
    MPRefreshMetric thirtySecondMetrics = [scheduler processDueMetrics];
    MPAssert((thirtySecondMetrics & MPRefreshMetricTemperature) != 0,
             @"temperature should run after thirty seconds");
    MPAssert((thirtySecondMetrics & MPRefreshMetricDisk) == 0,
             @"disk should not run after only thirty seconds");

    clock.time = 400.0;
    MPRefreshMetric threeHundredSecondMetrics = [scheduler processDueMetrics];
    MPAssert((threeHundredSecondMetrics & MPRefreshMetricDisk) != 0,
             @"disk should run after three hundred seconds");
    MPAssert((threeHundredSecondMetrics & MPRefreshMetricTemperature) != 0,
             @"temperature should remain on its fixed interval");

    scheduler.activeMetrics = MPRefreshMetricNone;
    MPAssert(!scheduler.isTimerArmed, @"all metrics off should disarm the timer");
    MPAssert(scheduler.nextDelayAtCurrentTime == MPRefreshSchedulerNoPendingDelay,
             @"all metrics off should have no pending deadline");
    [scheduler stop];
}

static void MPTestSchedulerIntervalChanges(void) {
    MPFakeMonotonicClock *clock = [[MPFakeMonotonicClock alloc] init];
    NSMutableArray<NSNumber *> *callbacks = [NSMutableArray array];
    MPRefreshScheduler *scheduler = MPMakeScheduler(clock, callbacks);
    scheduler.activeMetrics = MPRefreshMetricCPU;
    [scheduler start];
    MPAssert(callbacks.count == 1, @"CPU should sample when the scheduler starts");

    clock.time = 2.0;
    scheduler.cpuRAMRefreshIntervalSeconds = 10.0;
    MPAssert(callbacks.count == 1, @"lengthening the interval should not sample early");
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 8.0,
                     @"lengthening should preserve the original sample time");

    scheduler.cpuRAMRefreshIntervalSeconds = 1.0;
    MPAssert(callbacks.count == 2, @"shortening an overdue interval should sample immediately");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricCPU], 2.0,
                     @"an immediate sample should update the CPU timestamp");

    scheduler.activeMetrics = MPRefreshMetricNone;
    clock.time = 20.0;
    scheduler.activeMetrics = MPRefreshMetricRAM;
    MPAssert(callbacks.lastObject.unsignedIntegerValue == MPRefreshMetricRAM,
             @"a newly enabled metric should sample immediately");

    [scheduler stop];
}

static void MPTestSchedulerCPUWarmUp(void) {
    MPFakeMonotonicClock *clock = [[MPFakeMonotonicClock alloc] init];
    clock.time = 100.0;
    NSMutableArray<NSNumber *> *callbacks = [NSMutableArray array];
    MPRefreshScheduler *scheduler = MPMakeScheduler(clock, callbacks);
    scheduler.activeMetrics = MPRefreshMetricCPU;
    [scheduler start];
    MPAssert(callbacks.count == 1, @"the first CPU event should establish its baseline");

    [scheduler prepareCPUWarmUp];
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 1.0,
                     @"CPU warm-up should schedule the first value one second later");
    clock.time = 100.9;
    MPAssert([scheduler processDueMetrics] == MPRefreshMetricNone,
             @"CPU warm-up should not finish before one second");
    clock.time = 101.0;
    MPAssert([scheduler processDueMetrics] == MPRefreshMetricCPU,
             @"CPU warm-up should finish after one second");

    scheduler.cpuRAMRefreshIntervalSeconds = 10.0;
    [scheduler prepareCPUWarmUp];
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 1.0,
                     @"CPU warm-up should stay one second with a slower normal interval");

    scheduler.cpuRAMRefreshIntervalSeconds = 3.0;
    [scheduler prepareCPUWarmUp];
    scheduler.cpuRAMRefreshIntervalSeconds = 10.0;
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 1.0,
                     @"changing the normal interval should not delay CPU warm-up");
    [scheduler stop];
}

static void MPTestSchedulerCPUWarmUpRejoinsRAMCadence(void) {
    MPFakeMonotonicClock *clock = [[MPFakeMonotonicClock alloc] init];
    clock.time = 100.0;
    NSMutableArray<NSNumber *> *callbacks = [NSMutableArray array];
    MPRefreshScheduler *scheduler = MPMakeScheduler(clock, callbacks);
    scheduler.activeMetrics = MPRefreshMetricCPU | MPRefreshMetricRAM;
    [scheduler start];
    [scheduler prepareCPUWarmUp];

    clock.time = 101.0;
    MPAssert([scheduler processDueMetrics] ==
                 (MPRefreshMetricCPU | MPRefreshMetricRAM),
             @"CPU warm-up should refresh RAM on the same timer wake-up");
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 3.0,
                     @"CPU and RAM should share one deadline after warm-up");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricCPU], 101.0,
                     @"CPU should retain its truthful warm-up sample time");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricRAM], 101.0,
                     @"RAM should be sampled at the shared warm-up deadline");

    clock.time = 104.0;
    MPAssert([scheduler processDueMetrics] ==
                 (MPRefreshMetricCPU | MPRefreshMetricRAM),
             @"CPU and RAM should remain aligned after CPU warm-up");
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 3.0,
                     @"aligned CPU and RAM should need one shared timer wake-up");

    clock.time = 104.1;
    scheduler.cpuRAMRefreshIntervalSeconds = 1.0;
    MPAssert(callbacks.count == 3,
             @"shortening the interval should not repeat a just-finished shared sample");
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 0.9,
                     @"shortening should use the truthful shared sample timestamp");
    [scheduler stop];
}

static void MPTestSchedulerLateRAMActivationRejoinsCPUCadence(void) {
    MPFakeMonotonicClock *clock = [[MPFakeMonotonicClock alloc] init];
    clock.time = 100.0;
    NSMutableArray<NSNumber *> *callbacks = [NSMutableArray array];
    MPRefreshScheduler *scheduler = MPMakeScheduler(clock, callbacks);
    scheduler.activeMetrics = MPRefreshMetricCPU;
    [scheduler start];

    clock.time = 101.0;
    scheduler.activeMetrics = MPRefreshMetricCPU | MPRefreshMetricRAM;
    MPAssert(callbacks.lastObject.unsignedIntegerValue ==
                 (MPRefreshMetricCPU | MPRefreshMetricRAM),
             @"enabling RAM later should refresh CPU on the same wake-up");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricCPU], 101.0,
                     @"late RAM activation should realign the CPU timestamp");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricRAM], 101.0,
                     @"late RAM activation should record a shared RAM timestamp");
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 3.0,
                     @"late RAM activation should leave one shared deadline");

    clock.time = 104.0;
    MPAssert([scheduler processDueMetrics] ==
                 (MPRefreshMetricCPU | MPRefreshMetricRAM),
             @"CPU and late-enabled RAM should remain aligned");
    [scheduler stop];
}

static void MPTestSchedulerLateRAMActivationPreservesCPUWarmUp(void) {
    MPFakeMonotonicClock *clock = [[MPFakeMonotonicClock alloc] init];
    clock.time = 100.0;
    NSMutableArray<NSNumber *> *callbacks = [NSMutableArray array];
    MPRefreshScheduler *scheduler = MPMakeScheduler(clock, callbacks);
    scheduler.activeMetrics = MPRefreshMetricCPU;
    [scheduler start];
    [scheduler prepareCPUWarmUp];

    clock.time = 100.2;
    scheduler.activeMetrics = MPRefreshMetricCPU | MPRefreshMetricRAM;
    MPAssert(callbacks.lastObject.unsignedIntegerValue == MPRefreshMetricRAM,
             @"enabling RAM should not finish an in-progress CPU warm-up early");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricCPU], 100.0,
                     @"late RAM activation should preserve the CPU baseline time");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricRAM], 100.2,
                     @"late RAM activation should still sample RAM immediately");
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 0.8,
                     @"the original CPU warm-up deadline should remain armed");

    clock.time = 101.0;
    MPAssert([scheduler processDueMetrics] ==
                 (MPRefreshMetricCPU | MPRefreshMetricRAM),
             @"CPU warm-up completion should realign late-enabled RAM");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricCPU], 101.0,
                     @"CPU should finish warm-up at its original deadline");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricRAM], 101.0,
                     @"RAM should rejoin CPU when warm-up finishes");
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 3.0,
                     @"CPU and RAM should share a normal deadline after warm-up");
    [scheduler stop];
}

static void MPTestSchedulerLateCPUActivationRejoinsRAMCadence(void) {
    MPFakeMonotonicClock *clock = [[MPFakeMonotonicClock alloc] init];
    clock.time = 200.0;
    NSMutableArray<NSNumber *> *callbacks = [NSMutableArray array];
    MPRefreshScheduler *scheduler = MPMakeScheduler(clock, callbacks);
    scheduler.activeMetrics = MPRefreshMetricRAM;
    [scheduler start];

    clock.time = 201.0;
    scheduler.activeMetrics = MPRefreshMetricCPU | MPRefreshMetricRAM;
    MPAssert(callbacks.lastObject.unsignedIntegerValue ==
                 (MPRefreshMetricCPU | MPRefreshMetricRAM),
             @"enabling CPU later should refresh RAM on the same wake-up");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricCPU], 201.0,
                     @"late CPU activation should record a shared CPU timestamp");
    MPAssertInterval([scheduler lastSampleTimeForMetric:MPRefreshMetricRAM], 201.0,
                     @"late CPU activation should realign the RAM timestamp");
    MPAssertInterval(scheduler.nextDelayAtCurrentTime, 3.0,
                     @"late CPU activation should leave one shared deadline");

    clock.time = 204.0;
    MPAssert([scheduler processDueMetrics] ==
                 (MPRefreshMetricCPU | MPRefreshMetricRAM),
             @"RAM and late-enabled CPU should remain aligned");
    [scheduler stop];
}

static void MPTestSchedulerLeewayAndExplicitSamples(void) {
    MPAssertInterval([MPRefreshScheduler leewayForDelay:0.5], 0.1,
                     @"short timer leeway should have a 0.1-second floor");
    MPAssertInterval([MPRefreshScheduler leewayForDelay:3.0], 0.3,
                     @"timer leeway should be ten percent of the delay");
    MPAssertInterval([MPRefreshScheduler leewayForDelay:100.0], 5.0,
                     @"long timer leeway should have a five-second ceiling");

    MPFakeMonotonicClock *clock = [[MPFakeMonotonicClock alloc] init];
    clock.time = 50.0;
    NSMutableArray<NSNumber *> *callbacks = [NSMutableArray array];
    MPRefreshScheduler *scheduler = MPMakeScheduler(clock, callbacks);
    scheduler.activeMetrics = MPRefreshMetricTemperature;
    [scheduler markMetricsSampled:MPRefreshMetricTemperature];
    MPAssert([scheduler dueMetricsAtCurrentTime] == MPRefreshMetricNone,
             @"an explicit sample should satisfy the current deadline");
    clock.time = 80.0;
    MPAssert([scheduler dueMetricsAtCurrentTime] == MPRefreshMetricTemperature,
             @"temperature should become due thirty seconds after an explicit sample");
    [scheduler invalidateLastSampleForMetrics:MPRefreshMetricTemperature];
    MPAssert(isnan([scheduler lastSampleTimeForMetric:MPRefreshMetricTemperature]),
             @"invalidating a sample should clear its timestamp");
}

int main(void) {
    @autoreleasepool {
        MPTestSettingsDefaultsAndPersistence();
        MPTestSettingsValidationAndReset();
        MPTestSchedulerIntervals();
        MPTestSchedulerIntervalChanges();
        MPTestSchedulerCPUWarmUp();
        MPTestSchedulerCPUWarmUpRejoinsRAMCadence();
        MPTestSchedulerLateRAMActivationRejoinsCPUCadence();
        MPTestSchedulerLateRAMActivationPreservesCPUWarmUp();
        MPTestSchedulerLateCPUActivationRejoinsRAMCadence();
        MPTestSchedulerLeewayAndExplicitSamples();

        if (MPFailureCount > 0) {
            fprintf(stderr, "%lu settings/scheduler test(s) failed\n",
                    (unsigned long)MPFailureCount);
            return 1;
        }

        puts("All settings and scheduler tests passed.");
    }
    return 0;
}
