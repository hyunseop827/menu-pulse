#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MPTemperatureCompletion)(NSNumber *_Nullable temperatureCelsius);

@interface MPTemperatureReader : NSObject
- (nullable NSNumber *)temperatureCelsius;
- (void)temperatureCelsiusAsync:(MPTemperatureCompletion)completion;
@end

NS_ASSUME_NONNULL_END
