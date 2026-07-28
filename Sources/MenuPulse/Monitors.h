#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPCPUMonitor : NSObject
- (nullable NSNumber *)usagePercent;
- (void)reset;
@end

@interface MPMemoryMonitor : NSObject
+ (nullable NSNumber *)usagePercent;
@end

@interface MPDiskMonitor : NSObject
+ (nullable NSNumber *)usagePercent;
+ (nullable NSNumber *)usagePercentForPath:(NSString *)path;
+ (nullable NSNumber *)usagePercentForPath:(NSString *)path
                            availableBytes:(nullable uint64_t *)availableBytes;
@end

NS_ASSUME_NONNULL_END
