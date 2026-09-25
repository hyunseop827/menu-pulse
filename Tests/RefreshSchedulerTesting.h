#import "RefreshScheduler.h"

NS_ASSUME_NONNULL_BEGIN

/// Scheduler state that only tests inspect.
@interface MPRefreshScheduler (Testing)
@property(nonatomic, readonly) MPRefreshMetric pausedMetrics;
@property(nonatomic, readonly, getter=isTimerArmed) BOOL timerArmed;
- (MPRefreshMetric)dueMetricsAtCurrentTime;
- (NSTimeInterval)nextDelayAtCurrentTime;
- (NSTimeInterval)lastSampleTimeForMetric:(MPRefreshMetric)metric;
+ (NSTimeInterval)leewayForDelay:(NSTimeInterval)delay;
@end

NS_ASSUME_NONNULL_END
