#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT const NSTimeInterval MPCPURAMRefreshIntervalDefault;
FOUNDATION_EXPORT const NSTimeInterval MPCPURAMRefreshIntervalFast;
FOUNDATION_EXPORT const NSTimeInterval MPCPURAMRefreshIntervalSlow;

FOUNDATION_EXPORT NSString * const MPTemperatureUnitCelsius;
FOUNDATION_EXPORT NSString * const MPTemperatureUnitFahrenheit;

@interface MPSettingsStore : NSObject

- (instancetype)init;
- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults NS_DESIGNATED_INITIALIZER;

@property(nonatomic) BOOL showCPU;
@property(nonatomic) BOOL showRAM;
@property(nonatomic) BOOL showTemperature;
@property(nonatomic) BOOL showDisk;
@property(nonatomic, copy) NSString *temperatureUnit;
@property(nonatomic) NSTimeInterval cpuRAMRefreshIntervalSeconds;

+ (BOOL)isValidCPURAMRefreshInterval:(NSTimeInterval)interval;
- (void)removeLegacyRefreshIntervalSettings;
- (void)resetMetricSettings;

@end

NS_ASSUME_NONNULL_END
