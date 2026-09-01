#import "MenuPulse.h"

#import "LoginItemManager.h"
#import "Monitors.h"
#import "RefreshScheduler.h"
#import "SettingsStore.h"
#import "SettingsWindowController.h"
#import "TemperatureReader.h"

#import <AppKit/AppKit.h>

@interface MPMenuPulse () <MPSettingsWindowControllerDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) MPLoginItemManager *loginItemManager;
@property(nonatomic, strong) MPSettingsStore *settingsStore;
@property(nonatomic, strong) MPRefreshScheduler *refreshScheduler;
@property(nonatomic, strong) MPCPUMonitor *cpuMonitor;
@property(nonatomic, strong, nullable) MPTemperatureReader *temperatureReader;
@property(nonatomic, strong, nullable) NSNumber *cachedCPU;
@property(nonatomic, strong, nullable) NSNumber *cachedRAM;
@property(nonatomic, strong, nullable) NSNumber *cachedTemperature;
@property(nonatomic, strong, nullable) NSNumber *cachedDisk;
@property(nonatomic, strong, nullable) NSNumber *cachedDiskAvailableBytes;
@property(nonatomic) BOOL temperatureReadInFlight;
@property(nonatomic) NSUInteger temperatureRequestGeneration;
@property(nonatomic) BOOL cachedLoginEnabled;
@property(nonatomic) NSUInteger loginRequestGeneration;
@property(nonatomic) BOOL loginRequestPending;
@property(nonatomic, copy) NSArray<NSString *> *lastRenderedRows;
@property(nonatomic, strong, nullable) MPSettingsWindowController *settingsWindowController;
@property(nonatomic, strong, nullable) id appActivationObserver;
@end

@implementation MPMenuPulse

- (instancetype)init {
    return [self initWithLoginItemMigrationEnabled:YES];
}

- (instancetype)initWithLoginItemMigrationEnabled:(BOOL)loginItemMigrationEnabled {
    self = [super init];
    if (self) {
        _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
        _loginItemManager = [[MPLoginItemManager alloc]
            initWithLegacyMigrationEnabled:loginItemMigrationEnabled];
        _settingsStore = [[MPSettingsStore alloc] init];
        _cpuMonitor = [[MPCPUMonitor alloc] init];
        _lastRenderedRows = @[];
    }
    return self;
}

- (void)start {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self observeApplicationActivation];

    self.cachedLoginEnabled = self.loginItemManager.isEnabled;
    [self syncLoginControl];

    NSStatusBarButton *button = self.statusItem.button;
    button.imagePosition = NSImageOnly;
    button.target = self;
    button.action = @selector(showSettings);
    button.toolTip = @"Menu Pulse Settings";

    __weak typeof(self) weakSelf = self;
    self.refreshScheduler = [[MPRefreshScheduler alloc] initWithDueHandler:^(MPRefreshMetric dueMetrics) {
        [weakSelf refreshMetrics:dueMetrics];
    }];
    [self syncRefreshSchedulerIntervals];
    self.refreshScheduler.activeMetrics = [self activeRefreshMetrics];
    [self.refreshScheduler start];
    [self updateStatusImage];

    if (self.cachedLoginEnabled) {
        self.settingsStore.hasCompletedOpenAtLoginPrompt = YES;
    } else if (!self.settingsStore.hasCompletedOpenAtLoginPrompt) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleOpenAtLoginPromptIfNeeded];
        });
    }
}

- (MPSettingsWindowController *)activeSettingsWindowController {
    if (!self.settingsWindowController) {
        self.settingsWindowController = [[MPSettingsWindowController alloc]
            initWithSettingsStore:self.settingsStore
                          delegate:self];
    }
    return self.settingsWindowController;
}

- (BOOL)showCPU {
    return self.settingsStore.showCPU;
}

- (BOOL)showTemperature {
    return self.settingsStore.showTemperature;
}

- (BOOL)showRAM {
    return self.settingsStore.showRAM;
}

- (BOOL)showDisk {
    return self.settingsStore.showDisk;
}

- (NSString *)temperatureUnit {
    return self.settingsStore.temperatureUnit;
}

- (NSTimeInterval)cpuRAMRefreshIntervalSeconds {
    return self.settingsStore.cpuRAMRefreshIntervalSeconds;
}

- (NSTimeInterval)temperatureRefreshIntervalSeconds {
    return self.settingsStore.temperatureRefreshIntervalSeconds;
}

- (NSTimeInterval)diskRefreshIntervalSeconds {
    return self.settingsStore.diskRefreshIntervalSeconds;
}

- (void)showSettings {
    self.cachedLoginEnabled = self.loginItemManager.isEnabled;
    MPSettingsWindowController *controller = [self activeSettingsWindowController];
    controller.loginEnabled = self.cachedLoginEnabled;
    [controller showSettingsWindow];
}

- (void)handleOpenAtLoginPromptIfNeeded {
    self.cachedLoginEnabled = self.loginItemManager.isEnabled;
    if (self.cachedLoginEnabled) {
        self.settingsStore.hasCompletedOpenAtLoginPrompt = YES;
        [self syncLoginControl];
        return;
    }
    if (self.settingsStore.hasCompletedOpenAtLoginPrompt) {
        return;
    }

    BOOL alreadyHadSettingsController = self.settingsWindowController != nil;
    MPSettingsWindowController *controller = [self activeSettingsWindowController];
    [NSApp activateIgnoringOtherApps:YES];
    BOOL shouldEnable = [controller runOpenAtLoginPrompt];
    self.settingsStore.hasCompletedOpenAtLoginPrompt = YES;
    if (shouldEnable) {
        [self requestLoginEnabled:YES showApproval:YES];
    } else {
        [self syncLoginControl];
    }
    if (!alreadyHadSettingsController && !controller.window.isVisible) {
        self.settingsWindowController = nil;
    }
}

- (void)settingsWindowControllerDidChangeMetrics:(MPSettingsWindowController *)controller {
    (void)controller;
    MPRefreshMetric previousMetrics = self.refreshScheduler.activeMetrics;
    MPRefreshMetric activeMetrics = [self activeRefreshMetrics];
    MPRefreshMetric changedMetrics = previousMetrics ^ activeMetrics;

    if ((changedMetrics & MPRefreshMetricCPU) != 0) {
        [self.cpuMonitor reset];
        self.cachedCPU = nil;
    }
    if ((activeMetrics & MPRefreshMetricRAM) == 0) {
        self.cachedRAM = nil;
    }
    if ((activeMetrics & MPRefreshMetricTemperature) == 0) {
        [self releaseTemperatureReaderIfDisabled];
    } else if ((changedMetrics & MPRefreshMetricTemperature) != 0) {
        self.cachedTemperature = nil;
    }
    if ((activeMetrics & MPRefreshMetricDisk) == 0) {
        self.cachedDisk = nil;
        self.cachedDiskAvailableBytes = nil;
    }

    self.refreshScheduler.activeMetrics = activeMetrics;
    [self updateStatusImage];
}

- (void)settingsWindowControllerDidChangeTemperatureUnit:(MPSettingsWindowController *)controller {
    (void)controller;
    [self updateStatusImage];
}

- (void)settingsWindowControllerDidChangeRefreshIntervals:(MPSettingsWindowController *)controller {
    (void)controller;
    [self syncRefreshSchedulerIntervals];
    [self updateStatusImage];
}

- (void)settingsWindowController:(MPSettingsWindowController *)controller
      didRequestLoginEnabled:(BOOL)enabled {
    (void)controller;
    [self requestLoginEnabled:enabled showApproval:YES];
}

- (void)settingsWindowControllerDidRequestOpenLoginItems:(MPSettingsWindowController *)controller {
    (void)controller;
    [self.loginItemManager openSystemSettings];
}

- (void)settingsWindowControllerDidRequestResetDefaults:(MPSettingsWindowController *)controller {
    BOOL wasRunning = self.refreshScheduler.isRunning;
    [self.refreshScheduler stop];
    [self.settingsStore resetMetricSettings];
    self.settingsStore.hasCompletedOpenAtLoginPrompt = YES;
    [self.cpuMonitor reset];
    self.cachedCPU = nil;
    self.cachedRAM = nil;
    self.cachedTemperature = nil;
    self.cachedDisk = nil;
    self.cachedDiskAvailableBytes = nil;
    [self releaseTemperatureReaderIfDisabled];

    [self syncRefreshSchedulerIntervals];
    self.refreshScheduler.activeMetrics = [self activeRefreshMetrics];
    [self.refreshScheduler invalidateLastSampleForMetrics:MPRefreshMetricAll];
    if (wasRunning) {
        [self.refreshScheduler start];
    }

    [self requestLoginEnabled:YES showApproval:YES];
    [controller syncControls];
    [self updateStatusImage];
}

- (void)settingsWindowControllerDidRequestQuit:(MPSettingsWindowController *)controller {
    (void)controller;
    [self.refreshScheduler stop];
    [NSApp terminate:nil];
}

- (void)requestLoginEnabled:(BOOL)enabled showApproval:(BOOL)showApproval {
    NSUInteger generation = ++self.loginRequestGeneration;
    self.loginRequestPending = YES;
    self.settingsWindowController.loginEnabled = enabled;

    __weak typeof(self) weakSelf = self;
    [self.loginItemManager setEnabled:enabled completion:^(BOOL success) {
        MPMenuPulse *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.loginRequestGeneration) {
            return;
        }

        strongSelf.loginRequestPending = NO;
        strongSelf.cachedLoginEnabled = strongSelf.loginItemManager.isEnabled;
        [strongSelf syncLoginControl];
        if (!success) {
            if (enabled && showApproval && strongSelf.loginItemManager.requiresApproval) {
                BOOL alreadyHadController = strongSelf.settingsWindowController != nil;
                MPSettingsWindowController *controller =
                    [strongSelf activeSettingsWindowController];
                [controller showLoginApprovalAlert];
                if (!alreadyHadController && !controller.window.isVisible) {
                    strongSelf.settingsWindowController = nil;
                }
            } else {
                NSBeep();
            }
        }
        [strongSelf updateStatusImage];
    }];
}

- (void)syncLoginControl {
    self.settingsWindowController.loginEnabled = self.cachedLoginEnabled;
}

- (void)observeApplicationActivation {
    if (self.appActivationObserver) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.appActivationObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSApplicationDidBecomeActiveNotification
                    object:NSApp
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *notification) {
        (void)notification;
        [weakSelf refreshLoginStateFromSystem];
    }];
}

- (void)refreshLoginStateFromSystem {
    self.cachedLoginEnabled = self.loginItemManager.isEnabled;
    if (!self.loginRequestPending) {
        [self syncLoginControl];
    }
    [self updateStatusImage];
}

- (void)syncRefreshSchedulerIntervals {
    self.refreshScheduler.cpuRAMRefreshIntervalSeconds = self.cpuRAMRefreshIntervalSeconds;
    self.refreshScheduler.temperatureRefreshIntervalSeconds = self.temperatureRefreshIntervalSeconds;
    self.refreshScheduler.diskRefreshIntervalSeconds = self.diskRefreshIntervalSeconds;
}

- (MPRefreshMetric)activeRefreshMetrics {
    MPRefreshMetric metrics = MPRefreshMetricNone;
    if (self.showCPU) {
        metrics |= MPRefreshMetricCPU;
    }
    if (self.showRAM) {
        metrics |= MPRefreshMetricRAM;
    }
    if (self.showTemperature) {
        metrics |= MPRefreshMetricTemperature;
    }
    if (self.showDisk) {
        metrics |= MPRefreshMetricDisk;
    }
    return metrics;
}

- (void)refreshMetrics:(MPRefreshMetric)metrics {
    if ((metrics & MPRefreshMetricCPU) != 0 && self.showCPU) {
        BOOL hadCPUBaseline = self.cpuMonitor.hasBaseline;
        self.cachedCPU = [self.cpuMonitor usagePercent];
        if (!self.cachedCPU && !hadCPUBaseline && self.cpuMonitor.hasBaseline) {
            [self.refreshScheduler prepareCPUWarmUp];
        }
    }

    if ((metrics & MPRefreshMetricRAM) != 0 && self.showRAM) {
        self.cachedRAM = [MPMemoryMonitor usagePercent];
    }

    if ((metrics & MPRefreshMetricTemperature) != 0 && self.showTemperature) {
        [self requestTemperatureRead];
    }

    if ((metrics & MPRefreshMetricDisk) != 0 && self.showDisk) {
        uint64_t availableBytes = 0;
        self.cachedDisk = [MPDiskMonitor usagePercentForPath:NSHomeDirectory()
                                             availableBytes:&availableBytes];
        self.cachedDiskAvailableBytes = self.cachedDisk ? @(availableBytes) : nil;
    }

    [self updateStatusImage];
}

- (MPTemperatureReader *)activeTemperatureReader {
    if (!self.temperatureReader) {
        self.temperatureReader = [[MPTemperatureReader alloc] init];
    }
    return self.temperatureReader;
}

- (void)releaseTemperatureReaderIfDisabled {
    if (self.showTemperature) {
        return;
    }

    self.temperatureRequestGeneration += 1;
    self.temperatureReadInFlight = NO;
    self.cachedTemperature = nil;
    [self.refreshScheduler setMetric:MPRefreshMetricTemperature paused:NO];
    [self.temperatureReader invalidateHardware];
}

- (void)requestTemperatureRead {
    if (self.temperatureReadInFlight || !self.showTemperature) {
        return;
    }

    self.temperatureReadInFlight = YES;
    [self.refreshScheduler setMetric:MPRefreshMetricTemperature paused:YES];
    NSUInteger generation = ++self.temperatureRequestGeneration;

    __weak typeof(self) weakSelf = self;
    [[self activeTemperatureReader] temperatureCelsiusAsync:^(NSNumber *temperatureCelsius) {
        MPMenuPulse *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (!temperatureCelsius) {
            [strongSelf.refreshScheduler deferMetric:MPRefreshMetricTemperature
                                         forInterval:MPTemperatureFailureRetryInterval];
        }
        if (generation != strongSelf.temperatureRequestGeneration) {
            return;
        }

        strongSelf.temperatureReadInFlight = NO;
        [strongSelf.refreshScheduler setMetric:MPRefreshMetricTemperature paused:NO];

        strongSelf.cachedTemperature = strongSelf.showTemperature ? temperatureCelsius : nil;
        [strongSelf updateStatusImage];
    }];
}

- (void)dealloc {
    id observer = self.appActivationObserver;
    if (observer) {
        [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
}

- (void)updateStatusImage {
    NSArray<NSString *> *rows = [self statusRows];
    NSString *tooltip = [self statusTooltip];
    [self.statusItem.button setAccessibilityLabel:@"Menu Pulse"];
    [self.statusItem.button setAccessibilityValue:tooltip];
    [self.statusItem.button setAccessibilityHelp:@"Opens Menu Pulse settings."];
    if ([rows isEqualToArray:self.lastRenderedRows]) {
        self.statusItem.button.toolTip = tooltip;
        return;
    }

    NSImage *image = [self renderStatusImageWithRows:rows];
    self.lastRenderedRows = rows;
    self.statusItem.length = image.size.width;
    self.statusItem.button.title = @"";
    self.statusItem.button.image = image;
    self.statusItem.button.toolTip = tooltip;
}

- (NSArray<NSString *> *)statusRows {
    NSString *cpu = self.showCPU
        ? [NSString stringWithFormat:@"CPU:%@", [self formatPercent:self.cachedCPU]] : nil;
    NSString *ram = self.showRAM
        ? [NSString stringWithFormat:@"RAM:%@", [self formatPercent:self.cachedRAM]] : nil;
    NSString *temperature = self.showTemperature
        ? [NSString stringWithFormat:@"TEMP:%@", [self formatTemperature:self.cachedTemperature]] : nil;
    NSString *disk = self.showDisk
        ? [NSString stringWithFormat:@"DISK:%@", [self formatPercent:self.cachedDisk]] : nil;

    NSArray<NSString *> *leftColumn = [self compactValues:@[
        cpu ?: NSNull.null,
        ram ?: NSNull.null,
    ]];
    NSArray<NSString *> *rightColumn = [self compactValues:@[
        temperature ?: NSNull.null,
        disk ?: NSNull.null,
    ]];

    if (leftColumn.count == 0 && rightColumn.count == 0) {
        return @[@"PULSE"];
    }
    if (rightColumn.count == 0) {
        return [self twoRowsFromValues:leftColumn];
    }
    if (leftColumn.count == 0) {
        return [self twoRowsFromValues:rightColumn];
    }
    return @[
        [self joinStatusColumnLeft:[self valueAtIndex:0 inArray:leftColumn]
                             right:[self valueAtIndex:0 inArray:rightColumn]],
        [self joinStatusColumnLeft:[self valueAtIndex:1 inArray:leftColumn]
                             right:[self valueAtIndex:1 inArray:rightColumn]],
    ];
}

- (NSImage *)renderStatusImageWithRows:(NSArray<NSString *> *)rows {
    NSFont *font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightSemibold];
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: NSColor.labelColor,
    };

    CGFloat width = 42.0;
    for (NSString *row in rows) {
        width = MAX(width, [self textWidth:row attributes:attributes]);
    }
    width += 1.0;

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(ceil(width), 24)];
    [image lockFocus];
    [NSColor.clearColor set];
    NSRectFill(NSMakeRect(0, 0, image.size.width, image.size.height));

    NSUInteger count = MIN((NSUInteger)2, rows.count);
    for (NSUInteger index = 0; index < count; index += 1) {
        CGFloat y = count == 1
            ? floor((image.size.height - [rows[index] sizeWithAttributes:attributes].height) / 2.0)
            : (index == 0 ? 10.5 : -0.5);
        [rows[index] drawAtPoint:NSMakePoint(0, y) withAttributes:attributes];
    }

    [image unlockFocus];
    image.template = YES;
    return image;
}

- (CGFloat)textWidth:(NSString *)value
           attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes {
    return [value sizeWithAttributes:attributes].width;
}

- (NSString *)statusTooltip {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:@"Menu Pulse"];
    if (self.showCPU) {
        [lines addObject:[NSString stringWithFormat:@"CPU: %@ (every %@)",
                          [self formatPercent:self.cachedCPU],
                          [self formatInterval:self.cpuRAMRefreshIntervalSeconds]]];
    }
    if (self.showRAM) {
        [lines addObject:[NSString stringWithFormat:@"RAM: %@ (every %@)",
                          [self formatPercent:self.cachedRAM],
                          [self formatInterval:self.cpuRAMRefreshIntervalSeconds]]];
    }
    if (self.showTemperature) {
        NSString *temperature = self.temperatureReadInFlight && !self.cachedTemperature
            ? @"warming up" : [self formatTemperature:self.cachedTemperature];
        [lines addObject:[NSString stringWithFormat:@"TEMP (hottest sensor): %@ (every %@)",
                          temperature,
                          [self formatInterval:self.temperatureRefreshIntervalSeconds]]];
    }
    if (self.showDisk) {
        [lines addObject:[NSString stringWithFormat:@"Disk (home volume): %@, %@ (every %@)",
                          [self formatPercent:self.cachedDisk],
                          [self formatAvailableBytes:self.cachedDiskAvailableBytes],
                          [self formatInterval:self.diskRefreshIntervalSeconds]]];
    }
    if (!self.showCPU && !self.showRAM && !self.showTemperature && !self.showDisk) {
        [lines addObject:@"No metrics enabled"];
    }

    NSString *loginState = self.loginItemManager.requiresApproval
        ? @"Needs approval" : (self.cachedLoginEnabled ? @"On" : @"Off");
    [lines addObject:[NSString stringWithFormat:@"Open at login: %@", loginState]];
    [lines addObject:@"Click to open settings"];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)formatInterval:(NSTimeInterval)value {
    NSInteger seconds = (NSInteger)llround(value);
    if (seconds >= 60 && seconds % 60 == 0) {
        NSInteger minutes = seconds / 60;
        return [NSString stringWithFormat:@"%ld minute%@",
                                          (long)minutes,
                                          minutes == 1 ? @"" : @"s"];
    }
    return [NSString stringWithFormat:@"%ld second%@",
                                      (long)seconds,
                                      seconds == 1 ? @"" : @"s"];
}

- (NSString *)formatAvailableBytes:(NSNumber *)value {
    if (!value) {
        return @"-- free";
    }
    NSString *size = [NSByteCountFormatter stringFromByteCount:value.longLongValue
                                                    countStyle:NSByteCountFormatterCountStyleFile];
    return [NSString stringWithFormat:@"%@ free", size];
}

- (NSString *)formatPercent:(NSNumber *)value {
    if (!value) {
        return @"--%";
    }
    return [NSString stringWithFormat:@"%3d%%", (int)llround(value.doubleValue)];
}

- (NSString *)formatTemperature:(NSNumber *)value {
    BOOL useFahrenheit = [self.temperatureUnit isEqualToString:MPTemperatureUnitFahrenheit];
    NSString *symbol = useFahrenheit ? @"\u00B0F" : @"\u00B0C";
    if (!value) {
        return [self paddedTemperature:[NSString stringWithFormat:@"--%@", symbol]];
    }

    double number = value.doubleValue;
    if (useFahrenheit) {
        number = number * 9.0 / 5.0 + 32.0;
    }
    return [self paddedTemperature:[NSString stringWithFormat:@"%d%@",
                                                               (int)llround(number),
                                                               symbol]];
}

- (NSString *)paddedTemperature:(NSString *)value {
    NSInteger width = 5;
    NSInteger padding = MAX(0, width - (NSInteger)value.length);
    if (padding == 0) {
        return value;
    }
    NSString *prefix = [@"" stringByPaddingToLength:(NSUInteger)padding
                                          withString:@" "
                                     startingAtIndex:0];
    return [prefix stringByAppendingString:value];
}

- (NSArray<NSString *> *)twoRowsFromValues:(NSArray<NSString *> *)values {
    if (values.count == 1) {
        return @[values[0]];
    }
    return [values subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)2, values.count))];
}

- (NSString *)joinStatusColumnLeft:(nullable NSString *)left
                              right:(nullable NSString *)right {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    NSString *presentLeft = left;
    if (presentLeft) {
        [values addObject:presentLeft];
    }
    NSString *presentRight = right;
    if (presentRight) {
        [values addObject:presentRight];
    }
    return [values componentsJoinedByString:@"  "];
}

- (NSArray<NSString *> *)compactValues:(NSArray *)values {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (id value in values) {
        if ([value isKindOfClass:[NSString class]]) {
            [result addObject:value];
        }
    }
    return result;
}

- (nullable NSString *)valueAtIndex:(NSUInteger)index
                            inArray:(NSArray<NSString *> *)array {
    return index < array.count ? array[index] : nil;
}

@end
