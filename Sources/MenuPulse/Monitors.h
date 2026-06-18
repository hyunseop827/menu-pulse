#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPCPUMonitor : NSObject
- (nullable NSNumber *)usagePercent;
@end

@interface MPMemoryMonitor : NSObject
+ (nullable NSNumber *)usagePercent;
@end

@interface MPDiskMonitor : NSObject
+ (nullable NSNumber *)usagePercent;
+ (nullable NSNumber *)usagePercentForPath:(NSString *)path;
@end

NS_ASSUME_NONNULL_END
