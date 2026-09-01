#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSUInteger, MPRefreshMetric) {
    MPRefreshMetricNone = 0,
    MPRefreshMetricCPU = 1 << 0,
    MPRefreshMetricRAM = 1 << 1,
    MPRefreshMetricTemperature = 1 << 2,
    MPRefreshMetricDisk = 1 << 3,
    MPRefreshMetricAll = MPRefreshMetricCPU | MPRefreshMetricRAM |
        MPRefreshMetricTemperature | MPRefreshMetricDisk,
};

FOUNDATION_EXPORT const NSTimeInterval MPTemperatureRefreshInterval;
FOUNDATION_EXPORT const NSTimeInterval MPDiskRefreshInterval;
FOUNDATION_EXPORT const NSTimeInterval MPRefreshSchedulerNoPendingDelay;

@protocol MPMonotonicClock <NSObject>
- (NSTimeInterval)monotonicTime;
@end

@interface MPSystemMonotonicClock : NSObject <MPMonotonicClock>
@end

typedef void (^MPRefreshDueHandler)(MPRefreshMetric dueMetrics);

@interface MPRefreshScheduler : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDueHandler:(MPRefreshDueHandler)dueHandler;
- (instancetype)initWithClock:(id<MPMonotonicClock>)clock
                 callbackQueue:(dispatch_queue_t)callbackQueue
                    dueHandler:(MPRefreshDueHandler)dueHandler NS_DESIGNATED_INITIALIZER;

@property(nonatomic) MPRefreshMetric activeMetrics;
@property(nonatomic) NSTimeInterval cpuRAMRefreshIntervalSeconds;
@property(nonatomic, readonly, getter=isRunning) BOOL running;
@property(nonatomic, readonly, getter=isTimerArmed) BOOL timerArmed;

- (void)start;
- (void)stop;

/// Evaluates deadlines immediately, updates the last-sampled timestamps for due metrics,
/// invokes the due handler, and rearms the one-shot timer when running.
- (MPRefreshMetric)processDueMetrics;

/// Records an explicit sample outside the normal due callback.
- (void)markMetricsSampled:(MPRefreshMetric)metrics;

/// Moves the next CPU deadline to one second from now. Call this after the CPU
/// monitor consumes a due event only to establish its initial baseline.
- (void)prepareCPUWarmUp;

/// Makes the selected active metrics due on the next evaluation.
- (void)invalidateLastSampleForMetrics:(MPRefreshMetric)metrics;

- (MPRefreshMetric)dueMetricsAtCurrentTime;
- (NSTimeInterval)nextDelayAtCurrentTime;
- (NSTimeInterval)lastSampleTimeForMetric:(MPRefreshMetric)metric;

+ (NSTimeInterval)leewayForDelay:(NSTimeInterval)delay;

@end

NS_ASSUME_NONNULL_END
