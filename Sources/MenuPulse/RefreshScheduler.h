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
@property(nonatomic) NSTimeInterval temperatureRefreshIntervalSeconds;
@property(nonatomic) NSTimeInterval diskRefreshIntervalSeconds;
@property(nonatomic, readonly, getter=isRunning) BOOL running;

- (void)start;
- (void)stop;

/// Evaluates deadlines immediately, updates the last-sampled timestamps for due metrics,
/// invokes the due handler, and rearms the one-shot timer when running.
- (MPRefreshMetric)processDueMetrics;

/// Moves the next CPU deadline to one second from now. Call this after the CPU
/// monitor consumes a due event only to establish its initial baseline.
- (void)prepareCPUWarmUp;

/// Makes the selected active metrics due on the next evaluation.
- (void)invalidateLastSampleForMetrics:(MPRefreshMetric)metrics;

/// Excludes an in-flight asynchronous metric from timer deadlines. Resuming a
/// metric records the completion time as its new cadence anchor, dropping any
/// deadlines missed while the metric was paused.
- (void)setMetric:(MPRefreshMetric)metric paused:(BOOL)paused;

/// Prevents temperature from becoming due before the supplied monotonic
/// interval elapses. The deferral survives metric disable/enable cycles.
- (void)deferTemperatureForInterval:(NSTimeInterval)interval;

@end

NS_ASSUME_NONNULL_END
