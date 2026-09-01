#import "SettingsStore.h"

static NSString * const MPSettingShowCPU = @"showCPU";
static NSString * const MPSettingShowRAM = @"showRAM";
static NSString * const MPSettingShowTemperature = @"showTemperature";
static NSString * const MPSettingShowDisk = @"showDisk";
static NSString * const MPSettingTemperatureUnit = @"temperatureUnit";
static NSString * const MPSettingCPURAMRefreshIntervalSeconds = @"cpuRAMRefreshIntervalSeconds";

static NSString * const MPLegacyCPURefreshInterval = @"cpuRefreshInterval";
static NSString * const MPLegacyRAMRefreshInterval = @"ramRefreshInterval";
static NSString * const MPLegacyTemperatureRefreshInterval = @"temperatureRefreshInterval";
static NSString * const MPLegacyDiskRefreshInterval = @"diskRefreshInterval";

const NSTimeInterval MPCPURAMRefreshIntervalDefault = 3.0;
const NSTimeInterval MPCPURAMRefreshIntervalFast = 1.0;
const NSTimeInterval MPCPURAMRefreshIntervalSlow = 10.0;

NSString * const MPTemperatureUnitCelsius = @"C";
NSString * const MPTemperatureUnitFahrenheit = @"F";

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

+ (BOOL)isValidCPURAMRefreshInterval:(NSTimeInterval)interval {
    return interval == MPCPURAMRefreshIntervalFast ||
        interval == MPCPURAMRefreshIntervalDefault ||
        interval == MPCPURAMRefreshIntervalSlow;
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
