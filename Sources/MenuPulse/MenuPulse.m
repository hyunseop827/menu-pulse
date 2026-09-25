#import "MenuPulse.h"

#import "LoginItemManager.h"
#import "Monitors.h"
#import "RefreshScheduler.h"
#import "SettingsStore.h"
#import "SettingsWindowController.h"
#import "TemperatureReader.h"

#import <CoreGraphics/CoreGraphics.h>

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
@property(nonatomic) BOOL temperatureReadFailed;
@property(nonatomic) NSUInteger temperatureRequestGeneration;
@property(nonatomic) BOOL cachedLoginEnabled;
@property(nonatomic) BOOL cachedLoginRequiresApproval;
@property(nonatomic) NSUInteger loginRequestGeneration;
@property(nonatomic) BOOL loginRequestPending;
@property(nonatomic) BOOL requestedLoginEnabled;
@property(nonatomic, copy) NSArray<NSString *> *lastRenderedRows;
@property(nonatomic, strong, nullable) MPSettingsWindowController *settingsWindowController;
@property(nonatomic, strong, nullable) id appActivationObserver;
@property(nonatomic, copy) NSArray<id> *workspaceObservers;
@property(nonatomic) BOOL screensAsleep;
@property(nonatomic) BOOL sessionInactive;
@end

@implementation MPMenuPulse

- (instancetype)initWithLoginItemMigrationEnabled:(BOOL)loginItemMigrationEnabled {
    self = [super init];
    if (self) {
        _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
        _loginItemManager = [[MPLoginItemManager alloc]
            initWithLegacyMigrationEnabled:loginItemMigrationEnabled];
        _settingsStore = [[MPSettingsStore alloc] init];
        _cpuMonitor = [[MPCPUMonitor alloc] init];
        _lastRenderedRows = @[];
        [_statusItem.button setAccessibilityLabel:@"Menu Pulse"];
        [_statusItem.button setAccessibilityHelp:@"Opens Menu Pulse settings."];
    }
    return self;
}

- (void)start {
    if (self.refreshScheduler) {
        return;
    }
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self observeApplicationActivation];
    [self observeWorkspace];
    self.screensAsleep = [self areScreensAsleep];

    [self refreshLoginStateFromSystem];

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
    if (!self.isMonitoringPaused) {
        [self.refreshScheduler start];
    }
    [self updateStatusImage];

    if (self.cachedLoginEnabled) {
        self.settingsStore.hasCompletedOpenAtLoginPrompt = YES;
    } else if (!self.settingsStore.hasCompletedOpenAtLoginPrompt) {
        [self scheduleOpenAtLoginPrompt];
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

- (void)releaseSettingsWindowControllerIfHidden {
    if (!self.settingsWindowController.window.isVisible) {
        self.settingsWindowController = nil;
    }
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
    MPSettingsWindowController *controller = [self activeSettingsWindowController];
    [self refreshLoginStateFromSystem];
    [controller showSettingsWindow];
}

- (void)scheduleOpenAtLoginPrompt {
    // Run the modal prompt from the run loop rather than from a main-queue
    // block, which would stall the main-queue refresh timer while it is open.
    __weak typeof(self) weakSelf = self;
    CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(mainRunLoop, kCFRunLoopDefaultMode, ^{
        [weakSelf handleOpenAtLoginPromptIfNeeded];
    });
    CFRunLoopWakeUp(mainRunLoop);
}

- (void)handleOpenAtLoginPromptIfNeeded {
    if (self.isMonitoringPaused || self.settingsStore.hasCompletedOpenAtLoginPrompt) {
        return;
    }
    [self refreshLoginStateFromSystem];
    if (self.cachedLoginEnabled) {
        self.settingsStore.hasCompletedOpenAtLoginPrompt = YES;
        return;
    }

    MPSettingsWindowController *controller = [self activeSettingsWindowController];
    [NSApp activateIgnoringOtherApps:YES];
    BOOL shouldEnable = [controller runOpenAtLoginPrompt];
    self.settingsStore.hasCompletedOpenAtLoginPrompt = YES;
    if (shouldEnable) {
        [self requestLoginEnabled:YES];
    }
    [self releaseSettingsWindowControllerIfHidden];
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
    [self requestLoginEnabled:enabled];
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

    [self requestLoginEnabled:YES];
    [controller syncControls];
    [self updateStatusImage];
}

- (void)settingsWindowControllerDidRequestQuit:(MPSettingsWindowController *)controller {
    (void)controller;
    [self.refreshScheduler stop];
    [NSApp terminate:nil];
}

- (void)settingsWindowControllerDidCloseWindow:(MPSettingsWindowController *)controller {
    // Release the window once the close finishes, unless it was reopened.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        MPMenuPulse *strongSelf = weakSelf;
        if (strongSelf.settingsWindowController == controller && !controller.window.isVisible) {
            strongSelf.settingsWindowController = nil;
        }
    });
}

- (void)requestLoginEnabled:(BOOL)enabled {
    NSUInteger generation = ++self.loginRequestGeneration;
    self.loginRequestPending = YES;
    self.requestedLoginEnabled = enabled;
    [self syncLoginControl];

    __weak typeof(self) weakSelf = self;
    [self.loginItemManager setEnabled:enabled completion:^(BOOL success) {
        MPMenuPulse *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.loginRequestGeneration) {
            return;
        }

        strongSelf.loginRequestPending = NO;
        [strongSelf refreshLoginStateFromSystem];
        if (success) {
            return;
        }
        if (enabled && strongSelf.cachedLoginRequiresApproval) {
            [[strongSelf activeSettingsWindowController] showLoginApprovalAlert];
            [strongSelf releaseSettingsWindowControllerIfHidden];
        } else {
            NSBeep();
        }
    }];
}

- (void)syncLoginControl {
    // While a request is running, keep showing the state the user asked for.
    self.settingsWindowController.loginEnabled = self.loginRequestPending
        ? self.requestedLoginEnabled
        : self.cachedLoginEnabled;
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
    MPLoginItemStatus status = self.loginItemManager.status;
    self.cachedLoginEnabled = status == MPLoginItemStatusEnabled;
    self.cachedLoginRequiresApproval = status == MPLoginItemStatusRequiresApproval;
    [self syncLoginControl];
    [self updateStatusImage];
}

- (BOOL)areScreensAsleep {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (screens.count == 0) {
        return NO;
    }
    for (NSScreen *screen in screens) {
        NSNumber *displayID = screen.deviceDescription[@"NSScreenNumber"];
        if (!displayID || !CGDisplayIsAsleep(displayID.unsignedIntValue)) {
            return NO;
        }
    }
    return YES;
}

- (void)observeWorkspace {
    NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
    __weak typeof(self) weakSelf = self;
    id (^observe)(NSNotificationName, void (^)(MPMenuPulse *)) =
        ^id(NSNotificationName name, void (^handler)(MPMenuPulse *)) {
        return [center addObserverForName:name
                                   object:nil
                                    queue:NSOperationQueue.mainQueue
                               usingBlock:^(NSNotification *notification) {
            (void)notification;
            MPMenuPulse *strongSelf = weakSelf;
            if (strongSelf) {
                handler(strongSelf);
            }
        }];
    };
    // Nothing is visible while displays sleep or another user's session is
    // active, so monitoring pauses in both cases.
    self.workspaceObservers = @[
        observe(NSWorkspaceScreensDidSleepNotification, ^(MPMenuPulse *pulse) {
            pulse.screensAsleep = YES;
        }),
        observe(NSWorkspaceScreensDidWakeNotification, ^(MPMenuPulse *pulse) {
            pulse.screensAsleep = NO;
        }),
        observe(NSWorkspaceSessionDidResignActiveNotification, ^(MPMenuPulse *pulse) {
            pulse.sessionInactive = YES;
        }),
        observe(NSWorkspaceSessionDidBecomeActiveNotification, ^(MPMenuPulse *pulse) {
            pulse.sessionInactive = NO;
        }),
    ];
}

- (BOOL)isMonitoringPaused {
    return self.screensAsleep || self.sessionInactive;
}

- (void)setScreensAsleep:(BOOL)screensAsleep {
    if (_screensAsleep == screensAsleep) {
        return;
    }
    BOOL wasPaused = self.isMonitoringPaused;
    _screensAsleep = screensAsleep;
    [self monitoringPauseDidChangeFrom:wasPaused];
}

- (void)setSessionInactive:(BOOL)sessionInactive {
    if (_sessionInactive == sessionInactive) {
        return;
    }
    BOOL wasPaused = self.isMonitoringPaused;
    _sessionInactive = sessionInactive;
    [self monitoringPauseDidChangeFrom:wasPaused];
}

- (void)monitoringPauseDidChangeFrom:(BOOL)wasPaused {
    BOOL paused = self.isMonitoringPaused;
    if (paused != wasPaused) {
        [self.refreshScheduler stop];
        [self.cpuMonitor reset];
        self.cachedCPU = nil;
        self.cachedRAM = nil;
        self.cachedDisk = nil;
        self.cachedDiskAvailableBytes = nil;
        [self cancelTemperatureRead];

        if (!paused && self.refreshScheduler) {
            // Fresh baselines avoid including the invisible interval in CPU usage.
            // The scheduler keeps any outstanding sensor failure cooldown.
            [self.refreshScheduler invalidateLastSampleForMetrics:MPRefreshMetricAll];
            [self.refreshScheduler start];
            [self refreshLoginStateFromSystem];
            if (!self.settingsStore.hasCompletedOpenAtLoginPrompt) {
                [self scheduleOpenAtLoginPrompt];
            }
        }
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
    if (self.isMonitoringPaused) {
        return;
    }
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

    [self cancelTemperatureRead];
}

- (void)cancelTemperatureRead {
    self.temperatureRequestGeneration += 1;
    self.temperatureReadInFlight = NO;
    self.cachedTemperature = nil;
    [self.refreshScheduler setMetric:MPRefreshMetricTemperature paused:NO];
    [self.temperatureReader invalidateHardware];
}

- (void)requestTemperatureRead {
    if (self.isMonitoringPaused || self.temperatureReadInFlight || !self.showTemperature) {
        return;
    }

    self.temperatureReadInFlight = YES;
    self.temperatureReadFailed = NO;
    [self.refreshScheduler setMetric:MPRefreshMetricTemperature paused:YES];
    NSUInteger generation = ++self.temperatureRequestGeneration;

    __weak typeof(self) weakSelf = self;
    [[self activeTemperatureReader] temperatureCelsiusAsync:^(NSNumber *temperatureCelsius) {
        MPMenuPulse *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (!temperatureCelsius) {
            // Even a canceled request keeps the failure cooldown, so a quick
            // OFF/ON toggle cannot retry a failing sensor immediately.
            [strongSelf.refreshScheduler
                deferTemperatureForInterval:MPTemperatureFailureRetryInterval];
        }
        if (generation != strongSelf.temperatureRequestGeneration) {
            // The tooltip still explains a cooldown kept by a canceled request.
            if (!temperatureCelsius && !strongSelf.cachedTemperature) {
                strongSelf.temperatureReadFailed = YES;
            }
            return;
        }

        strongSelf.temperatureReadInFlight = NO;
        strongSelf.temperatureReadFailed = temperatureCelsius == nil;
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
    for (id workspaceObserver in self.workspaceObservers) {
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:workspaceObserver];
    }
}

- (void)updateStatusImage {
    NSArray<NSString *> *rows = [self statusRows];
    NSString *tooltip = [self statusTooltip];
    if (![self.statusItem.button.toolTip isEqualToString:tooltip]) {
        self.statusItem.button.toolTip = tooltip;
        [self.statusItem.button setAccessibilityValue:tooltip];
    }
    if ([rows isEqualToArray:self.lastRenderedRows]) {
        return;
    }

    NSImage *image = [self renderStatusImageWithRows:rows];
    self.lastRenderedRows = rows;
    self.statusItem.length = image.size.width;
    self.statusItem.button.title = @"";
    self.statusItem.button.image = image;
}

- (NSArray<NSString *> *)statusRows {
    NSMutableArray<NSString *> *leftColumn = [NSMutableArray array];
    NSMutableArray<NSString *> *rightColumn = [NSMutableArray array];
    if (self.showCPU) {
        [leftColumn addObject:[@"CPU:" stringByAppendingString:[self formatPercent:self.cachedCPU]]];
    }
    if (self.showRAM) {
        [leftColumn addObject:[@"RAM:" stringByAppendingString:[self formatPercent:self.cachedRAM]]];
    }
    if (self.showTemperature) {
        [rightColumn addObject:[@"TEMP:" stringByAppendingString:
            [self formatTemperature:self.cachedTemperature]]];
    }
    if (self.showDisk) {
        [rightColumn addObject:[@"DISK:" stringByAppendingString:[self formatPercent:self.cachedDisk]]];
    }

    if (leftColumn.count == 0 && rightColumn.count == 0) {
        return @[@"PULSE"];
    }
    // One or two metrics get a row each; three or four share two columns.
    if (leftColumn.count + rightColumn.count <= 2) {
        return [leftColumn arrayByAddingObjectsFromArray:rightColumn];
    }

    // With both columns shown, the menu bar always draws two rows. The font
    // is monospaced, so a blank left cell keeps a lone right cell in its column.
    NSString *blankLeftCell = [@"" stringByPaddingToLength:leftColumn.firstObject.length
                                                withString:@" "
                                           startingAtIndex:0];
    NSMutableArray<NSString *> *rows = [NSMutableArray arrayWithCapacity:2];
    for (NSUInteger index = 0; index < 2; index += 1) {
        NSString *left = index < leftColumn.count ? leftColumn[index] : blankLeftCell;
        [rows addObject:index < rightColumn.count
            ? [NSString stringWithFormat:@"%@  %@", left, rightColumn[index]]
            : left];
    }
    return rows;
}

- (NSImage *)renderStatusImageWithRows:(NSArray<NSString *> *)rows {
    NSFont *font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightSemibold];
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: NSColor.labelColor,
    };

    CGFloat width = 42.0;
    for (NSString *row in rows) {
        width = MAX(width, [row sizeWithAttributes:attributes].width);
    }
    NSSize size = NSMakeSize(ceil(width + 1.0), 24);

    // The drawing handler renders at each display's backing scale, so the
    // text stays sharp when menu bars span Retina and non-Retina displays.
    NSArray<NSString *> *drawnRows = [rows copy];
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSUInteger count = MIN((NSUInteger)2, drawnRows.count);
        for (NSUInteger index = 0; index < count; index += 1) {
            CGFloat y = count == 1
                ? floor((NSHeight(rect) - [drawnRows[index] sizeWithAttributes:attributes].height) / 2.0)
                : (index == 0 ? 10.5 : -0.5);
            [drawnRows[index] drawAtPoint:NSMakePoint(0, y) withAttributes:attributes];
        }
        return YES;
    }];
    image.template = YES;
    return image;
}

- (NSString *)statusTooltip {
    BOOL showCPU = self.showCPU;
    BOOL showRAM = self.showRAM;
    BOOL showTemperature = self.showTemperature;
    BOOL showDisk = self.showDisk;

    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:@"Menu Pulse"];
    if (showCPU || showRAM) {
        NSString *interval = MPIntervalDescription(self.cpuRAMRefreshIntervalSeconds);
        if (showCPU) {
            [lines addObject:[NSString stringWithFormat:@"CPU: %@ (every %@)",
                              [self formatPercent:self.cachedCPU], interval]];
        }
        if (showRAM) {
            [lines addObject:[NSString stringWithFormat:@"RAM: %@ (every %@)",
                              [self formatPercent:self.cachedRAM], interval]];
        }
    }
    if (showTemperature) {
        NSString *temperature = [self formatTemperature:self.cachedTemperature];
        if (!self.cachedTemperature) {
            if (self.temperatureReadInFlight) {
                temperature = @"warming up";
            } else if (self.temperatureReadFailed) {
                temperature = [NSString stringWithFormat:@"unavailable (retrying every %@)",
                               MPIntervalDescription(MPTemperatureFailureRetryInterval)];
            }
        }
        [lines addObject:[NSString stringWithFormat:@"TEMP (hottest sensor): %@ (every %@)",
                          temperature,
                          MPIntervalDescription(self.temperatureRefreshIntervalSeconds)]];
    }
    if (showDisk) {
        [lines addObject:[NSString stringWithFormat:@"Disk (home volume): %@, %@ (every %@)",
                          [self formatPercent:self.cachedDisk],
                          [self formatAvailableBytes:self.cachedDiskAvailableBytes],
                          MPIntervalDescription(self.diskRefreshIntervalSeconds)]];
    }
    if (!showCPU && !showRAM && !showTemperature && !showDisk) {
        [lines addObject:@"No metrics enabled"];
    }

    if (self.screensAsleep) {
        [lines addObject:@"Monitoring paused while displays are asleep"];
    }
    NSString *loginState = self.cachedLoginRequiresApproval
        ? @"Needs approval" : (self.cachedLoginEnabled ? @"On" : @"Off");
    [lines addObject:[NSString stringWithFormat:@"Open at login: %@", loginState]];
    [lines addObject:@"Click to open settings"];
    return [lines componentsJoinedByString:@"\n"];
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
    // The placeholder matches the %3d width so the menu bar item keeps its size.
    if (!value) {
        return @" --%";
    }
    return [NSString stringWithFormat:@"%3d%%", (int)llround(value.doubleValue)];
}

- (NSString *)formatTemperature:(NSNumber *)value {
    BOOL useFahrenheit = [self.temperatureUnit isEqualToString:MPTemperatureUnitFahrenheit];
    NSString *symbol = useFahrenheit ? @"°F" : @"°C";
    if (!value) {
        return [@" --" stringByAppendingString:symbol];
    }

    double number = value.doubleValue;
    if (useFahrenheit) {
        number = number * 9.0 / 5.0 + 32.0;
    }
    return [NSString stringWithFormat:@"%3d%@", (int)llround(number), symbol];
}

@end
