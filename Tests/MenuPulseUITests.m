#import "LoginItemManager.h"
#import "MemoryUserDefaults.h"
#import "MenuPulse.h"
#import "SettingsStore.h"
#import "TemperatureReader.h"

#import <AppKit/AppKit.h>
#import <math.h>

extern BOOL MPTemperatureRetryAllowed(NSTimeInterval now, NSTimeInterval lastFailureTime);

static NSUInteger MPFailureCount = 0;
static NSUInteger MPLegacyMigrationCallCount = 0;

static void MPAssert(BOOL condition, NSString *message) {
    if (condition) {
        return;
    }

    MPFailureCount += 1;
    fprintf(stderr, "FAIL: %s\n", message.UTF8String);
}

@interface MPMenuPulse (UITesting)
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) MPSettingsStore *settingsStore;
@property(nonatomic, strong) MPLoginItemManager *loginItemManager;
@property(nonatomic, strong, nullable) NSNumber *cachedCPU;
@property(nonatomic, strong, nullable) NSNumber *cachedRAM;
@property(nonatomic, strong, nullable) NSNumber *cachedTemperature;
@property(nonatomic, strong, nullable) MPTemperatureReader *temperatureReader;
@property(nonatomic) BOOL temperatureReadInFlight;
@property(nonatomic) BOOL cachedLoginEnabled;
@property(nonatomic, copy) NSArray<NSString *> *lastRenderedRows;
- (NSArray<NSString *> *)statusRows;
- (NSString *)statusTooltip;
- (void)updateStatusImage;
- (NSPopUpButton *)makeCPURAMRefreshPopup;
- (NSWindow *)makeSettingsWindow;
- (void)requestTemperatureRead;
- (void)releaseTemperatureReaderIfDisabled;
@end

@interface MPFakeTemperatureReader : MPTemperatureReader
@property(nonatomic, strong) NSMutableArray<MPTemperatureCompletion> *completions;
@end

@implementation MPFakeTemperatureReader

- (instancetype)init {
    self = [super init];
    if (self) {
        _completions = [NSMutableArray array];
    }
    return self;
}

- (void)temperatureCelsiusAsync:(MPTemperatureCompletion)completion {
    [self.completions addObject:[completion copy]];
}

@end

@interface MPFakeLoginItemManager : MPLoginItemManager
@end

@implementation MPFakeLoginItemManager

- (instancetype)init {
    return [super initWithLegacyMigrationEnabled:NO];
}

- (BOOL)isEnabled {
    return NO;
}

- (BOOL)requiresApproval {
    return NO;
}

@end

@interface MPTrackingLoginItemManager : MPLoginItemManager
@end

@implementation MPTrackingLoginItemManager

- (void)migrateLegacyLoginItemIfPossible {
    MPLegacyMigrationCallCount += 1;
}

@end

static NSUserDefaults *MPMakeIsolatedDefaults(void) {
    return [[MPMemoryUserDefaults alloc] init];
}

static MPMenuPulse *MPMakePulse(NSUserDefaults *defaults) {
    MPMenuPulse *pulse = [[MPMenuPulse alloc] initWithLoginItemMigrationEnabled:NO];
    pulse.settingsStore = [[MPSettingsStore alloc] initWithUserDefaults:defaults];
    pulse.loginItemManager = [[MPFakeLoginItemManager alloc] init];
    pulse.cachedLoginEnabled = NO;
    pulse.lastRenderedRows = @[];
    return pulse;
}

static void MPTestLoginItemMigrationControl(void) {
    MPLegacyMigrationCallCount = 0;
    MPTrackingLoginItemManager *disabledManager = [[MPTrackingLoginItemManager alloc]
        initWithLegacyMigrationEnabled:NO];
    (void)disabledManager;
    MPAssert(MPLegacyMigrationCallCount == 0,
             @"the benchmark/test initializer should skip legacy login migration");

    MPTrackingLoginItemManager *enabledManager = [[MPTrackingLoginItemManager alloc]
        initWithLegacyMigrationEnabled:YES];
    (void)enabledManager;
    MPAssert(MPLegacyMigrationCallCount == 1,
             @"the production initializer should retain legacy login migration");
}

static void MPTestStatusRows(MPMenuPulse *pulse) {
    pulse.settingsStore.showCPU = YES;
    pulse.settingsStore.showRAM = NO;
    pulse.settingsStore.showTemperature = NO;
    pulse.settingsStore.showDisk = NO;
    pulse.cachedCPU = @12.4;

    NSArray<NSString *> *singleMetricRows = [pulse statusRows];
    MPAssert([singleMetricRows isEqualToArray:@[@"CPU: 12%"]],
             @"a single metric should produce one centered status row");

    pulse.settingsStore.showCPU = NO;
    NSArray<NSString *> *emptyRows = [pulse statusRows];
    MPAssert([emptyRows isEqualToArray:@[@"PULSE"]],
             @"all metrics off should display PULSE");
}

static void MPTestTooltipAndAccessibility(MPMenuPulse *pulse) {
    pulse.settingsStore.showCPU = YES;
    pulse.settingsStore.showRAM = YES;
    pulse.settingsStore.showTemperature = NO;
    pulse.settingsStore.showDisk = NO;
    pulse.settingsStore.cpuRAMRefreshIntervalSeconds = 3.0;
    pulse.cachedCPU = @12.4;
    pulse.cachedRAM = @47.6;

    NSString *tooltip = [pulse statusTooltip];
    MPAssert([tooltip containsString:@"CPU:  12% (every 3s)"],
             @"the CPU tooltip should show the configured three-second refresh");
    MPAssert([tooltip containsString:@"RAM:  48% (every 3s)"],
             @"the RAM tooltip should show the configured three-second refresh");

    [pulse updateStatusImage];
    NSStatusBarButton *button = pulse.statusItem.button;
    MPAssert([[button accessibilityLabel] isEqualToString:@"Menu Pulse"],
             @"the menu bar item should have an accessibility label");
    MPAssert([[button accessibilityValue] isEqual:tooltip],
             @"the menu bar accessibility value should match the tooltip");
    MPAssert([[button accessibilityHelp] isEqualToString:@"Opens Menu Pulse settings."],
             @"the menu bar item should explain its action to assistive technology");
}

static BOOL MPViewContainsLabel(NSView *view, NSString *expectedLabel) {
    if ([view isKindOfClass:[NSTextField class]]) {
        NSTextField *field = (NSTextField *)view;
        if ([field.stringValue isEqualToString:expectedLabel]) {
            return YES;
        }
    }

    for (NSView *subview in view.subviews) {
        if (MPViewContainsLabel(subview, expectedLabel)) {
            return YES;
        }
    }
    return NO;
}

static void MPTestRefreshPopup(MPMenuPulse *pulse) {
    NSPopUpButton *popup = [pulse makeCPURAMRefreshPopup];
    NSArray<NSString *> *expectedTitles = @[
        @"Every 1 second",
        @"Every 3 seconds",
        @"Every 10 seconds",
    ];
    MPAssert([popup.itemTitles isEqualToArray:expectedTitles],
             @"the refresh popup should offer only 1, 3, and 10 seconds");

    NSArray<NSNumber *> *expectedIntervals = @[@1, @3, @10];
    NSMutableArray<NSNumber *> *actualIntervals = [NSMutableArray array];
    for (NSMenuItem *item in popup.itemArray) {
        if ([item.representedObject isKindOfClass:[NSNumber class]]) {
            [actualIntervals addObject:@([item.representedObject integerValue])];
        }
    }
    MPAssert([actualIntervals isEqualToArray:expectedIntervals],
             @"each refresh popup item should carry its interval value");
    MPAssert([[popup accessibilityLabel] isEqualToString:@"CPU and RAM refresh interval"],
             @"the refresh popup should have an accessibility label");
    MPAssert([[popup accessibilityHelp]
        isEqualToString:@"Temperature and disk use slower fixed intervals."],
             @"the refresh popup should explain the slower fixed metrics");

    NSWindow *settingsWindow = [pulse makeSettingsWindow];
    MPAssert(MPViewContainsLabel(settingsWindow.contentView,
                                 @"Temperature and disk update less often to save energy."),
             @"the settings window should show the energy-saving refresh explanation");
    [settingsWindow orderOut:nil];
}

static void MPTestTemperatureGenerationAndCooldown(MPMenuPulse *pulse) {
    MPAssert(MPTemperatureRetryAllowed(100.0, NAN),
             @"temperature should retry when there is no prior failure");
    MPAssert(!MPTemperatureRetryAllowed(399.9, 100.0),
             @"temperature should keep its five-minute cooldown");
    MPAssert(MPTemperatureRetryAllowed(400.0, 100.0),
             @"temperature should retry after five minutes");

    MPFakeTemperatureReader *reader = [[MPFakeTemperatureReader alloc] init];
    pulse.temperatureReader = reader;
    pulse.settingsStore.showTemperature = YES;
    [pulse requestTemperatureRead];
    MPAssert(reader.completions.count == 1 && pulse.temperatureReadInFlight,
             @"an enabled temperature metric should start one request");

    pulse.settingsStore.showTemperature = NO;
    [pulse releaseTemperatureReaderIfDisabled];
    MPAssert(pulse.temperatureReader == reader,
             @"disabling temperature should preserve reader cooldown state");
    MPAssert(!pulse.temperatureReadInFlight,
             @"disabling temperature should clear the in-flight UI state");

    pulse.settingsStore.showTemperature = YES;
    [pulse requestTemperatureRead];
    MPAssert(reader.completions.count == 2 && pulse.temperatureReadInFlight,
             @"re-enabling temperature should start a new generation");

    reader.completions[0](@99.0);
    MPAssert(pulse.cachedTemperature == nil && pulse.temperatureReadInFlight,
             @"an older temperature completion should be discarded");
    reader.completions[1](@55.0);
    MPAssert([pulse.cachedTemperature isEqualToNumber:@55.0] && !pulse.temperatureReadInFlight,
             @"the current temperature completion should be applied");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSUserDefaults *defaults = MPMakeIsolatedDefaults();
        MPMenuPulse *pulse = MPMakePulse(defaults);

        MPTestStatusRows(pulse);
        MPTestTooltipAndAccessibility(pulse);
        MPTestRefreshPopup(pulse);
        MPTestTemperatureGenerationAndCooldown(pulse);
        MPTestLoginItemMigrationControl();

        if (MPFailureCount != 0) {
            fprintf(stderr, "%lu UI test(s) failed\n", (unsigned long)MPFailureCount);
            return 1;
        }

        fprintf(stdout, "Menu Pulse UI tests passed\n");
    }
    return 0;
}
