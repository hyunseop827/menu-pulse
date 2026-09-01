#import <Foundation/Foundation.h>
#import <math.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MPTemperatureCompletion)(NSNumber *_Nullable temperatureCelsius);

FOUNDATION_EXPORT const NSTimeInterval MPTemperatureFailureRetryInterval;

NS_INLINE BOOL MPTemperatureRetryAllowedForInterval(
    NSTimeInterval now,
    NSTimeInterval lastFailureTime,
    NSTimeInterval retryInterval
) {
    return isnan(lastFailureTime) || now - lastFailureTime >= retryInterval;
}

FOUNDATION_EXPORT BOOL MPTemperatureRetryAllowed(
    NSTimeInterval now,
    NSTimeInterval lastFailureTime
);

@interface MPTemperatureReader : NSObject
- (void)temperatureCelsiusAsync:(MPTemperatureCompletion)completion;
- (void)invalidateHardware;
@end

NS_ASSUME_NONNULL_END
