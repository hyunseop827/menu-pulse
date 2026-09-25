#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns elapsed ticks between two 32-bit CPU counters, including wraps.
FOUNDATION_EXPORT uint64_t MPUnsignedTickDelta(uint32_t current, uint32_t previous);

/// Returns used / total as a percentage clamped to 0-100, or nil when total
/// is not a positive finite value.
FOUNDATION_EXPORT NSNumber *_Nullable MPPercentOfTotal(double used, double total);

@interface MPCPUMonitor : NSObject
@property(nonatomic, readonly) BOOL hasBaseline;
- (nullable NSNumber *)usagePercent;
- (void)reset;
@end

@interface MPMemoryMonitor : NSObject
+ (nullable NSNumber *)usagePercent;
@end

@interface MPDiskMonitor : NSObject
/// Reports usage the way Finder does: purgeable space counts as available.
+ (nullable NSNumber *)usagePercentForPath:(NSString *)path
                            availableBytes:(nullable uint64_t *)availableBytes;
@end

NS_ASSUME_NONNULL_END
