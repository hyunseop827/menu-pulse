#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MPTemperatureCompletion)(NSNumber *_Nullable temperatureCelsius);

FOUNDATION_EXPORT const NSTimeInterval MPTemperatureFailureRetryInterval;

FOUNDATION_EXPORT BOOL MPTemperatureRetryAllowed(
    NSTimeInterval now,
    NSTimeInterval lastFailureTime
);

/// Returns YES for HID sensors that do not report a live component
/// temperature and must not be considered for the hottest reading.
FOUNDATION_EXPORT BOOL MPTemperatureSensorIsExcluded(NSString *product);

@interface MPTemperatureReader : NSObject
- (void)temperatureCelsiusAsync:(MPTemperatureCompletion)completion;
- (void)invalidateHardware;
@end

NS_ASSUME_NONNULL_END
