#import "SettingsStore.h"

#import <math.h>

static NSString * const MPSettingShowCPU = @"showCPU";
static NSString * const MPSettingShowRAM = @"showRAM";
static NSString * const MPSettingShowTemperature = @"showTemperature";
static NSString * const MPSettingShowDisk = @"showDisk";
static NSString * const MPSettingTemperatureUnit = @"temperatureUnit";
static NSString * const MPSettingCPURAMRefreshIntervalSeconds = @"cpuRAMRefreshIntervalSeconds";
static NSString * const MPSettingTemperatureRefreshIntervalSeconds =
    @"temperatureRefreshIntervalSeconds";
static NSString * const MPSettingDiskRefreshIntervalSeconds =
    @"diskRefreshIntervalSeconds";
static NSString * const MPSettingHasCompletedOpenAtLoginPrompt =
    @"hasCompletedOpenAtLoginPrompt";

static NSString * const MPLegacyCPURefreshInterval = @"cpuRefreshInterval";
static NSString * const MPLegacyRAMRefreshInterval = @"ramRefreshInterval";
static NSString * const MPLegacyTemperatureRefreshInterval = @"temperatureRefreshInterval";
static NSString * const MPLegacyDiskRefreshInterval = @"diskRefreshInterval";

const NSTimeInterval MPCPURAMRefreshIntervalDefault = 3.0;
const NSTimeInterval MPCPURAMRefreshIntervalFast = 1.0;
const NSTimeInterval MPCPURAMRefreshIntervalSlow = 10.0;
const NSTimeInterval MPTemperatureRefreshIntervalDefault = 30.0;
const NSTimeInterval MPDiskRefreshIntervalDefault = 300.0;

NSString * const MPTemperatureUnitCelsius = @"C";
NSString * const MPTemperatureUnitFahrenheit = @"F";

static BOOL MPIntervalIsIncludedIn(NSTimeInterval interval,
                                   NSArray<NSNumber *> *supportedIntervals) {
    if (!isfinite(interval)) {
        return NO;
    }

    for (NSNumber *supportedInterval in supportedIntervals) {
        if (interval == supportedInterval.doubleValue) {
            return YES;
        }
    }
    return NO;
}

@interface MPSettingsStore ()
@property(nonatomic, strong) NSUserDefaults *userDefaults;
@end

@implementation MPSettingsStore

- (instancetype)init {
    return [self initWithUserDefaults:NSUserDefaults.standardUserDefaults];
}

- (instancetype)initWithUserDefaults:(NSUserDefaults *)userDefaults {
    self = [super init];
    if (self) {
        _userDefaults = userDefaults;
        [_userDefaults registerDefaults:[self.class metricDefaults]];
        [self removeLegacyRefreshIntervalSettings];
    }
    return self;
}

+ (NSDictionary<NSString *, id> *)metricDefaults {
    return @{
        MPSettingShowCPU: @YES,
        MPSettingShowRAM: @YES,
        MPSettingShowTemperature: @NO,
        MPSettingShowDisk: @NO,
        MPSettingTemperatureUnit: MPTemperatureUnitCelsius,
        MPSettingCPURAMRefreshIntervalSeconds: @(MPCPURAMRefreshIntervalDefault),
        MPSettingTemperatureRefreshIntervalSeconds: @(MPTemperatureRefreshIntervalDefault),
        MPSettingDiskRefreshIntervalSeconds: @(MPDiskRefreshIntervalDefault),
    };
}

- (BOOL)showCPU {
    return [self.userDefaults boolForKey:MPSettingShowCPU];
}

- (void)setShowCPU:(BOOL)showCPU {
    [self.userDefaults setBool:showCPU forKey:MPSettingShowCPU];
}

- (BOOL)showRAM {
    return [self.userDefaults boolForKey:MPSettingShowRAM];
}

- (void)setShowRAM:(BOOL)showRAM {
    [self.userDefaults setBool:showRAM forKey:MPSettingShowRAM];
}

- (BOOL)showTemperature {
    return [self.userDefaults boolForKey:MPSettingShowTemperature];
}

- (void)setShowTemperature:(BOOL)showTemperature {
    [self.userDefaults setBool:showTemperature forKey:MPSettingShowTemperature];
}

- (BOOL)showDisk {
    return [self.userDefaults boolForKey:MPSettingShowDisk];
}

- (void)setShowDisk:(BOOL)showDisk {
    [self.userDefaults setBool:showDisk forKey:MPSettingShowDisk];
}

- (NSString *)temperatureUnit {
    NSString *unit = [self.userDefaults stringForKey:MPSettingTemperatureUnit];
    if ([unit isEqualToString:MPTemperatureUnitFahrenheit]) {
        return MPTemperatureUnitFahrenheit;
    }

    if (![unit isEqualToString:MPTemperatureUnitCelsius]) {
        [self.userDefaults setObject:MPTemperatureUnitCelsius forKey:MPSettingTemperatureUnit];
    }
    return MPTemperatureUnitCelsius;
}

- (void)setTemperatureUnit:(NSString *)temperatureUnit {
    NSString *validatedUnit = [temperatureUnit isEqualToString:MPTemperatureUnitFahrenheit]
        ? MPTemperatureUnitFahrenheit
        : MPTemperatureUnitCelsius;
    [self.userDefaults setObject:validatedUnit forKey:MPSettingTemperatureUnit];
}

- (NSTimeInterval)cpuRAMRefreshIntervalSeconds {
    NSTimeInterval interval = [self.userDefaults doubleForKey:MPSettingCPURAMRefreshIntervalSeconds];
    if (![self.class isValidCPURAMRefreshInterval:interval]) {
        interval = MPCPURAMRefreshIntervalDefault;
        [self.userDefaults setDouble:interval forKey:MPSettingCPURAMRefreshIntervalSeconds];
    }
    return interval;
}

- (void)setCpuRAMRefreshIntervalSeconds:(NSTimeInterval)cpuRAMRefreshIntervalSeconds {
    NSTimeInterval interval = [self.class isValidCPURAMRefreshInterval:cpuRAMRefreshIntervalSeconds]
        ? cpuRAMRefreshIntervalSeconds
        : MPCPURAMRefreshIntervalDefault;
    [self.userDefaults setDouble:interval forKey:MPSettingCPURAMRefreshIntervalSeconds];
}

+ (NSArray<NSNumber *> *)supportedCPURAMRefreshIntervals {
    static NSArray<NSNumber *> *intervals;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        intervals = @[@1.0, @3.0, @10.0];
    });
    return intervals;
}

+ (NSArray<NSNumber *> *)supportedTemperatureRefreshIntervals {
    static NSArray<NSNumber *> *intervals;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        intervals = @[@1.0, @3.0, @10.0, @30.0, @60.0];
    });
    return intervals;
}

+ (NSArray<NSNumber *> *)supportedDiskRefreshIntervals {
    static NSArray<NSNumber *> *intervals;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        intervals = @[@60.0, @180.0, @300.0, @600.0];
    });
    return intervals;
}

+ (BOOL)isValidCPURAMRefreshInterval:(NSTimeInterval)interval {
    return MPIntervalIsIncludedIn(interval, self.supportedCPURAMRefreshIntervals);
}

+ (BOOL)isValidTemperatureRefreshInterval:(NSTimeInterval)interval {
    return MPIntervalIsIncludedIn(interval, self.supportedTemperatureRefreshIntervals);
}

+ (BOOL)isValidDiskRefreshInterval:(NSTimeInterval)interval {
    return MPIntervalIsIncludedIn(interval, self.supportedDiskRefreshIntervals);
}

- (NSTimeInterval)temperatureRefreshIntervalSeconds {
    NSTimeInterval interval =
        [self.userDefaults doubleForKey:MPSettingTemperatureRefreshIntervalSeconds];
    if (![self.class isValidTemperatureRefreshInterval:interval]) {
        interval = MPTemperatureRefreshIntervalDefault;
        [self.userDefaults setDouble:interval
                              forKey:MPSettingTemperatureRefreshIntervalSeconds];
    }
    return interval;
}

- (void)setTemperatureRefreshIntervalSeconds:(NSTimeInterval)interval {
    NSTimeInterval validatedInterval =
        [self.class isValidTemperatureRefreshInterval:interval]
        ? interval
        : MPTemperatureRefreshIntervalDefault;
    [self.userDefaults setDouble:validatedInterval
                          forKey:MPSettingTemperatureRefreshIntervalSeconds];
}

- (NSTimeInterval)diskRefreshIntervalSeconds {
    NSTimeInterval interval =
        [self.userDefaults doubleForKey:MPSettingDiskRefreshIntervalSeconds];
    if (![self.class isValidDiskRefreshInterval:interval]) {
        interval = MPDiskRefreshIntervalDefault;
        [self.userDefaults setDouble:interval forKey:MPSettingDiskRefreshIntervalSeconds];
    }
    return interval;
}

- (void)setDiskRefreshIntervalSeconds:(NSTimeInterval)interval {
    NSTimeInterval validatedInterval =
        [self.class isValidDiskRefreshInterval:interval]
        ? interval
        : MPDiskRefreshIntervalDefault;
    [self.userDefaults setDouble:validatedInterval
                          forKey:MPSettingDiskRefreshIntervalSeconds];
}

- (BOOL)hasCompletedOpenAtLoginPrompt {
    return [self.userDefaults boolForKey:MPSettingHasCompletedOpenAtLoginPrompt];
}

- (void)setHasCompletedOpenAtLoginPrompt:(BOOL)hasCompletedOpenAtLoginPrompt {
    [self.userDefaults setBool:hasCompletedOpenAtLoginPrompt
                        forKey:MPSettingHasCompletedOpenAtLoginPrompt];
}

- (void)removeLegacyRefreshIntervalSettings {
    NSArray<NSString *> *legacyKeys = @[
        MPLegacyCPURefreshInterval,
        MPLegacyRAMRefreshInterval,
        MPLegacyTemperatureRefreshInterval,
        MPLegacyDiskRefreshInterval,
    ];
    for (NSString *key in legacyKeys) {
        [self.userDefaults removeObjectForKey:key];
    }
}

- (void)resetMetricSettings {
    NSDictionary<NSString *, id> *defaults = [self.class metricDefaults];
    [defaults enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        (void)stop;
        [self.userDefaults setObject:value forKey:key];
    }];
    [self removeLegacyRefreshIntervalSettings];
}

@end
