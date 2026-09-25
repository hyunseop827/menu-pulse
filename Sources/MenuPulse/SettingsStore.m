#import "SettingsStore.h"

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
const NSTimeInterval MPTemperatureRefreshIntervalDefault = 30.0;
const NSTimeInterval MPDiskRefreshIntervalDefault = 300.0;

NSString * const MPTemperatureUnitCelsius = @"C";
NSString * const MPTemperatureUnitFahrenheit = @"F";

NSString *MPIntervalDescription(NSTimeInterval interval) {
    NSInteger value = (NSInteger)llround(interval);
    NSString *unit = @"second";
    if (value >= 60 && value % 60 == 0) {
        value /= 60;
        unit = @"minute";
    }
    return [NSString stringWithFormat:@"%ld %@%@", (long)value, unit, value == 1 ? @"" : @"s"];
}

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
    return [unit isEqualToString:MPTemperatureUnitFahrenheit]
        ? MPTemperatureUnitFahrenheit
        : MPTemperatureUnitCelsius;
}

- (void)setTemperatureUnit:(NSString *)temperatureUnit {
    NSString *validatedUnit = [temperatureUnit isEqualToString:MPTemperatureUnitFahrenheit]
        ? MPTemperatureUnitFahrenheit
        : MPTemperatureUnitCelsius;
    [self.userDefaults setObject:validatedUnit forKey:MPSettingTemperatureUnit];
}

- (NSTimeInterval)cpuRAMRefreshIntervalSeconds {
    NSTimeInterval interval = [self.userDefaults doubleForKey:MPSettingCPURAMRefreshIntervalSeconds];
    return [self.class isValidCPURAMRefreshInterval:interval]
        ? interval
        : MPCPURAMRefreshIntervalDefault;
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
    return [self.class isValidTemperatureRefreshInterval:interval]
        ? interval
        : MPTemperatureRefreshIntervalDefault;
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
    return [self.class isValidDiskRefreshInterval:interval]
        ? interval
        : MPDiskRefreshIntervalDefault;
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
        if ([self.userDefaults objectForKey:key]) {
            [self.userDefaults removeObjectForKey:key];
        }
    }
}

+ (NSString *)defaultMetricSettingsSummary {
    NSDictionary<NSString *, id> *defaults = [self metricDefaults];
    NSString *(^state)(NSString *) = ^NSString *(NSString *key) {
        return [defaults[key] boolValue] ? @"On" : @"Off";
    };
    NSString *cpuRAM = [state(MPSettingShowCPU) isEqualToString:state(MPSettingShowRAM)]
        ? [NSString stringWithFormat:@"CPU/RAM: %@", state(MPSettingShowCPU)]
        : [NSString stringWithFormat:@"CPU: %@, RAM: %@",
                                     state(MPSettingShowCPU),
                                     state(MPSettingShowRAM)];
    BOOL fahrenheit =
        [defaults[MPSettingTemperatureUnit] isEqualToString:MPTemperatureUnitFahrenheit];
    return [@[
        [NSString stringWithFormat:@"%@, every %@",
                                   cpuRAM,
                                   MPIntervalDescription(MPCPURAMRefreshIntervalDefault)],
        [NSString stringWithFormat:@"Temperature: %@, every %@",
                                   state(MPSettingShowTemperature),
                                   MPIntervalDescription(MPTemperatureRefreshIntervalDefault)],
        [NSString stringWithFormat:@"Disk: %@, every %@",
                                   state(MPSettingShowDisk),
                                   MPIntervalDescription(MPDiskRefreshIntervalDefault)],
        [NSString stringWithFormat:@"Temperature unit: %@",
                                   fahrenheit ? @"Fahrenheit" : @"Celsius"],
    ] componentsJoinedByString:@"\n"];
}

- (void)resetMetricSettings {
    // Removing the keys lets the registered defaults apply again, including
    // defaults changed by a later release.
    for (NSString *key in [self.class metricDefaults]) {
        [self.userDefaults removeObjectForKey:key];
    }
    [self removeLegacyRefreshIntervalSettings];
}

@end
