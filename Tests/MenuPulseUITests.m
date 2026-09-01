#import "LoginItemManager.h"
#import "MemoryUserDefaults.h"
#import "MenuPulse.h"
#import "RefreshScheduler.h"
#import "SettingsStore.h"
#import "SettingsWindowController.h"
#import "TemperatureReader.h"

#import <AppKit/AppKit.h>
#import <math.h>

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
@property(nonatomic, strong) MPRefreshScheduler *refreshScheduler;
@property(nonatomic, strong, nullable) MPSettingsWindowController *settingsWindowController;
@property(nonatomic, strong, nullable) NSNumber *cachedCPU;
@property(nonatomic, strong, nullable) NSNumber *cachedRAM;
@property(nonatomic, strong, nullable) NSNumber *cachedTemperature;
@property(nonatomic, strong, nullable) NSNumber *cachedDisk;
@property(nonatomic, strong, nullable) NSNumber *cachedDiskAvailableBytes;
@property(nonatomic, strong, nullable) MPTemperatureReader *temperatureReader;
@property(nonatomic) BOOL temperatureReadInFlight;
@property(nonatomic) BOOL cachedLoginEnabled;
@property(nonatomic, copy) NSArray<NSString *> *lastRenderedRows;
- (MPSettingsWindowController *)activeSettingsWindowController;
- (NSArray<NSString *> *)statusRows;
- (NSString *)statusTooltip;
- (void)updateStatusImage;
- (void)requestTemperatureRead;
- (void)releaseTemperatureReaderIfDisabled;
- (void)handleOpenAtLoginPromptIfNeeded;
- (void)refreshLoginStateFromSystem;
- (void)settingsWindowController:(MPSettingsWindowController *)controller
      didRequestLoginEnabled:(BOOL)enabled;
- (void)settingsWindowControllerDidRequestResetDefaults:
    (MPSettingsWindowController *)controller;
@end

@interface MPFakeClock : NSObject <MPMonotonicClock>
@property(nonatomic) NSTimeInterval now;
@end

@interface MPTemperatureReader (UITesting)
- (nullable NSNumber *)readTemperatureCelsius;
@end

@interface MPBlockingTemperatureReader : MPTemperatureReader
@property(nonatomic) dispatch_semaphore_t firstReadStarted;
@property(nonatomic) dispatch_semaphore_t allowFirstReadToFinish;
@property(nonatomic) NSUInteger readCount;
@end

@implementation MPBlockingTemperatureReader
- (instancetype)init {
    self = [super init];
    if (self) {
        _firstReadStarted = dispatch_semaphore_create(0);
        _allowFirstReadToFinish = dispatch_semaphore_create(0);
    }
    return self;
}
- (NSNumber *)readTemperatureCelsius {
    @synchronized (self) {
        self.readCount += 1;
        if (self.readCount == 1) {
            dispatch_semaphore_signal(self.firstReadStarted);
        }
    }
    if (self.readCount == 1) {
        dispatch_semaphore_wait(self.allowFirstReadToFinish, DISPATCH_TIME_FOREVER);
    }
    return @42.0;
}
@end

@implementation MPFakeClock
- (NSTimeInterval)monotonicTime {
    return self.now;
}
@end

@interface MPSettingsWindowController (UITesting)
@property(nonatomic, strong) NSButton *cpuCheckbox;
@property(nonatomic, strong) NSButton *temperatureCheckbox;
@property(nonatomic, strong) NSButton *ramCheckbox;
@property(nonatomic, strong) NSButton *diskCheckbox;
@property(nonatomic, strong) NSButton *loginCheckbox;
@property(nonatomic, strong) NSPopUpButton *cpuRAMRefreshPopup;
@property(nonatomic, strong) NSPopUpButton *temperatureRefreshPopup;
@property(nonatomic, strong) NSPopUpButton *diskRefreshPopup;
@property(nonatomic, strong) NSPopUpButton *temperatureUnitPopup;
- (void)metricsChanged:(id)sender;
- (void)refreshIntervalChanged:(id)sender;
- (void)loginChanged:(id)sender;
- (void)closePressed:(id)sender;
- (void)quitPressed:(id)sender;
- (void)resetDefaultsPressed:(id)sender;
@end

@interface MPFakeTemperatureReader : MPTemperatureReader
@property(nonatomic, strong) NSMutableArray<MPTemperatureCompletion> *completions;
@property(nonatomic) NSUInteger invalidateCount;
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
- (void)invalidateHardware {
    self.invalidateCount += 1;
}
@end

@interface MPFakeLoginItemManager : MPLoginItemManager
@property(nonatomic) BOOL fakeEnabled;
@property(nonatomic) BOOL fakeRequiresApproval;
@property(nonatomic) BOOL setSucceeds;
@property(nonatomic) NSUInteger setCallCount;
@property(nonatomic) BOOL lastRequestedState;
@property(nonatomic) NSUInteger openSettingsCount;
@property(nonatomic) BOOL autoCompletes;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *pendingStates;
@property(nonatomic, strong) NSMutableArray<MPLoginItemUpdateCompletion> *pendingCompletions;
- (void)completeRequestAtIndex:(NSUInteger)index success:(BOOL)success;
@end

@implementation MPFakeLoginItemManager
- (instancetype)init {
    self = [super initWithLegacyMigrationEnabled:NO];
    if (self) {
        _setSucceeds = YES;
        _autoCompletes = YES;
        _pendingStates = [NSMutableArray array];
        _pendingCompletions = [NSMutableArray array];
    }
    return self;
}
- (BOOL)isEnabled {
    return self.fakeEnabled;
}
- (BOOL)requiresApproval {
    return self.fakeRequiresApproval;
}
- (BOOL)setEnabled:(BOOL)enabled {
    self.setCallCount += 1;
    self.lastRequestedState = enabled;
    if (self.setSucceeds) {
        self.fakeEnabled = enabled;
    }
    return self.setSucceeds;
}
- (void)setEnabled:(BOOL)enabled completion:(MPLoginItemUpdateCompletion)completion {
    self.setCallCount += 1;
    self.lastRequestedState = enabled;
    if (!self.autoCompletes) {
        [self.pendingStates addObject:@(enabled)];
        [self.pendingCompletions addObject:[completion copy]];
        return;
    }
    if (self.setSucceeds) {
        self.fakeEnabled = enabled;
    }
    completion(self.setSucceeds);
}
- (void)completeRequestAtIndex:(NSUInteger)index success:(BOOL)success {
    if (index >= self.pendingCompletions.count) {
        return;
    }
    if (success) {
        self.fakeEnabled = self.pendingStates[index].boolValue;
    }
    self.pendingCompletions[index](success);
}
- (void)openSystemSettings {
    self.openSettingsCount += 1;
}
@end

@interface MPAsyncTrackingLoginItemManager : MPLoginItemManager
@property(nonatomic, strong) NSMutableArray<NSNumber *> *performedStates;
@property(nonatomic) BOOL allOperationsOffMainThread;
@end

@implementation MPAsyncTrackingLoginItemManager
- (instancetype)init {
    self = [super initWithLegacyMigrationEnabled:NO];
    if (self) {
        _performedStates = [NSMutableArray array];
        _allOperationsOffMainThread = YES;
    }
    return self;
}
- (BOOL)performSetEnabled:(BOOL)enabled {
    [NSThread sleepForTimeInterval:0.03];
    @synchronized (self) {
        self.allOperationsOffMainThread &= !NSThread.isMainThread;
        [self.performedStates addObject:@(enabled)];
    }
    return YES;
}
@end

@interface MPTrackingLoginItemManager : MPLoginItemManager
@end

@implementation MPTrackingLoginItemManager
- (void)migrateLegacyLoginItemIfPossible {
    MPLegacyMigrationCallCount += 1;
}
@end

@interface MPFakeSettingsDelegate : NSObject <MPSettingsWindowControllerDelegate>
@property(nonatomic) NSUInteger metricsChangeCount;
@property(nonatomic) NSUInteger unitChangeCount;
@property(nonatomic) NSUInteger intervalChangeCount;
@property(nonatomic) NSUInteger loginChangeCount;
@property(nonatomic) BOOL requestedLoginState;
@property(nonatomic) NSUInteger openLoginItemsCount;
@property(nonatomic) NSUInteger resetCount;
@property(nonatomic) NSUInteger quitCount;
@end

@implementation MPFakeSettingsDelegate
- (void)settingsWindowControllerDidChangeMetrics:(MPSettingsWindowController *)controller {
    (void)controller;
    self.metricsChangeCount += 1;
}
- (void)settingsWindowControllerDidChangeTemperatureUnit:(MPSettingsWindowController *)controller {
    (void)controller;
    self.unitChangeCount += 1;
}
- (void)settingsWindowControllerDidChangeRefreshIntervals:(MPSettingsWindowController *)controller {
    (void)controller;
    self.intervalChangeCount += 1;
}
- (void)settingsWindowController:(MPSettingsWindowController *)controller
      didRequestLoginEnabled:(BOOL)enabled {
    (void)controller;
    self.loginChangeCount += 1;
    self.requestedLoginState = enabled;
}
- (void)settingsWindowControllerDidRequestOpenLoginItems:(MPSettingsWindowController *)controller {
    (void)controller;
    self.openLoginItemsCount += 1;
}
- (void)settingsWindowControllerDidRequestResetDefaults:(MPSettingsWindowController *)controller {
    (void)controller;
    self.resetCount += 1;
}
- (void)settingsWindowControllerDidRequestQuit:(MPSettingsWindowController *)controller {
    (void)controller;
    self.quitCount += 1;
}
@end

static NSUserDefaults *MPMakeIsolatedDefaults(void) {
    return [[MPMemoryUserDefaults alloc] init];
}

static MPMenuPulse *MPMakePulse(NSUserDefaults *defaults,
                                MPFakeLoginItemManager **managerOut) {
    MPMenuPulse *pulse = [[MPMenuPulse alloc] initWithLoginItemMigrationEnabled:NO];
    pulse.settingsStore = [[MPSettingsStore alloc] initWithUserDefaults:defaults];
    MPFakeLoginItemManager *manager = [[MPFakeLoginItemManager alloc] init];
    pulse.loginItemManager = manager;
    pulse.cachedLoginEnabled = manager.isEnabled;
    pulse.lastRenderedRows = @[];
    if (managerOut) {
        *managerOut = manager;
    }
    return pulse;
}

static BOOL MPViewContainsText(NSView *view, NSString *expected) {
    if ([view isKindOfClass:[NSTextField class]] &&
        [[(NSTextField *)view stringValue] isEqualToString:expected]) {
        return YES;
    }
    if ([view isKindOfClass:[NSButton class]] &&
        [[(NSButton *)view title] isEqualToString:expected]) {
        return YES;
    }
    for (NSView *subview in view.subviews) {
        if (MPViewContainsText(subview, expected)) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSNumber *> *MPPopupIntervals(NSPopUpButton *popup) {
    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    for (NSMenuItem *item in popup.itemArray) {
        NSNumber *value = item.representedObject;
        if ([value isKindOfClass:[NSNumber class]]) {
            [values addObject:value];
        }
    }
    return values;
}

static void MPSelectInterval(NSPopUpButton *popup, NSTimeInterval interval) {
    for (NSMenuItem *item in popup.itemArray) {
        NSNumber *value = item.representedObject;
        if ([value isKindOfClass:[NSNumber class]] && value.doubleValue == interval) {
            [popup selectItem:item];
            return;
        }
    }
}

static void MPTestLoginItemMigrationControl(void) {
    MPLegacyMigrationCallCount = 0;
    (void)[[MPTrackingLoginItemManager alloc] initWithLegacyMigrationEnabled:NO];
    MPAssert(MPLegacyMigrationCallCount == 0,
             @"the benchmark/test initializer should skip legacy login migration");
    (void)[[MPTrackingLoginItemManager alloc] initWithLegacyMigrationEnabled:YES];
    MPAssert(MPLegacyMigrationCallCount == 1,
             @"the production initializer should retain legacy login migration");
}

static void MPTestAsyncLoginItemUpdates(void) {
    MPAsyncTrackingLoginItemManager *manager =
        [[MPAsyncTrackingLoginItemManager alloc] init];
    __block NSUInteger completionCount = 0;
    __block BOOL completionsWereOnMainThread = YES;

    CFAbsoluteTime startedAt = CFAbsoluteTimeGetCurrent();
    [manager setEnabled:NO completion:^(BOOL success) {
        MPAssert(success, @"the first asynchronous login update should succeed");
        completionsWereOnMainThread &= NSThread.isMainThread;
        completionCount += 1;
    }];
    [manager setEnabled:YES completion:^(BOOL success) {
        MPAssert(success, @"the second asynchronous login update should succeed");
        completionsWereOnMainThread &= NSThread.isMainThread;
        completionCount += 1;
    }];
    CFAbsoluteTime callDuration = CFAbsoluteTimeGetCurrent() - startedAt;
    MPAssert(callDuration < 0.02,
             @"asynchronous login updates should return without blocking the UI");

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (completionCount < 2 && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    MPAssert(completionCount == 2 && completionsWereOnMainThread,
             @"every async login completion should arrive on the main thread");
    MPAssert(manager.allOperationsOffMainThread,
             @"ServiceManagement polling should run away from the main thread");
    MPAssert([manager.performedStates isEqualToArray:@[@NO, @YES]],
             @"rapid login updates should execute in request order");
}

static void MPTestStatusRowsAndTooltip(MPMenuPulse *pulse) {
    pulse.settingsStore.showCPU = YES;
    pulse.settingsStore.showRAM = NO;
    pulse.settingsStore.showTemperature = NO;
    pulse.settingsStore.showDisk = NO;
    pulse.cachedCPU = @12.4;
    MPAssert([[pulse statusRows] isEqualToArray:@[@"CPU: 12%"]],
             @"a single metric should produce one centered status row");

    pulse.settingsStore.showCPU = NO;
    MPAssert([[pulse statusRows] isEqualToArray:@[@"PULSE"]],
             @"all metrics off should display PULSE");

    pulse.settingsStore.showCPU = YES;
    pulse.settingsStore.showRAM = YES;
    pulse.settingsStore.showTemperature = YES;
    pulse.settingsStore.showDisk = YES;
    pulse.settingsStore.cpuRAMRefreshIntervalSeconds = 3.0;
    pulse.settingsStore.temperatureRefreshIntervalSeconds = 60.0;
    pulse.settingsStore.diskRefreshIntervalSeconds = 180.0;
    pulse.cachedRAM = @47.6;
    pulse.cachedTemperature = @52.0;
    pulse.cachedDisk = @50.0;
    pulse.cachedDiskAvailableBytes = @(50LL * 1000LL * 1000LL * 1000LL);

    NSString *tooltip = [pulse statusTooltip];
    MPAssert([tooltip containsString:@"CPU:  12% (every 3 seconds)"],
             @"the CPU tooltip should show its configured interval");
    MPAssert([tooltip containsString:@"RAM:  48% (every 3 seconds)"],
             @"the RAM tooltip should show its configured interval");
    MPAssert([tooltip containsString:@"TEMP (hottest sensor):  52\u00B0C (every 1 minute)"],
             @"the TEMP tooltip should identify the hottest sensor and interval");
    MPAssert([tooltip containsString:@"Disk (home volume):  50%"],
             @"the disk tooltip should identify the home volume");
    MPAssert([tooltip containsString:@"(every 3 minutes)"],
             @"the disk tooltip should format intervals in minutes");

    [pulse updateStatusImage];
    NSStatusBarButton *button = pulse.statusItem.button;
    MPAssert([[button accessibilityLabel] isEqualToString:@"Menu Pulse"],
             @"the menu bar item should have an accessibility label");
    MPAssert([[button accessibilityValue] isEqual:tooltip],
             @"the menu bar accessibility value should match the tooltip");
    MPAssert([[button accessibilityHelp] isEqualToString:@"Opens Menu Pulse settings."],
             @"the menu bar item should explain its action");
}

static void MPTestSettingsWindowControls(void) {
    MPSettingsStore *store = [[MPSettingsStore alloc]
        initWithUserDefaults:MPMakeIsolatedDefaults()];
    MPFakeSettingsDelegate *delegate = [[MPFakeSettingsDelegate alloc] init];
    MPSettingsWindowController *controller = [[MPSettingsWindowController alloc]
        initWithSettingsStore:store
                      delegate:delegate];
    MPAssert(fabs(NSHeight(controller.window.contentView.bounds) - 420.0) < 0.5,
             @"settings window should fit its controls without excess bottom space");

    MPAssert([controller.cpuRAMRefreshPopup.itemTitles isEqualToArray:@[
        @"Every 1 second", @"Every 3 seconds", @"Every 10 seconds",
    ]], @"CPU and RAM should offer 1, 3, and 10 seconds");
    MPAssert([controller.temperatureRefreshPopup.itemTitles isEqualToArray:@[
        @"Every 1 second", @"Every 3 seconds", @"Every 10 seconds",
        @"Every 30 seconds", @"Every 1 minute",
    ]], @"temperature should offer five requested intervals");
    MPAssert([controller.diskRefreshPopup.itemTitles isEqualToArray:@[
        @"Every 1 minute", @"Every 3 minutes", @"Every 5 minutes", @"Every 10 minutes",
    ]], @"disk should offer four requested intervals");
    MPAssert([MPPopupIntervals(controller.cpuRAMRefreshPopup) isEqualToArray:@[@1, @3, @10]],
             @"CPU and RAM popup items should store their second values");
    MPAssert([MPPopupIntervals(controller.temperatureRefreshPopup)
        isEqualToArray:@[@1, @3, @10, @30, @60]],
             @"temperature popup items should store their second values");
    MPAssert([MPPopupIntervals(controller.diskRefreshPopup)
        isEqualToArray:@[@60, @180, @300, @600]],
             @"disk popup items should store their second values");
    MPAssert([controller.cpuRAMRefreshPopup.titleOfSelectedItem
        isEqualToString:@"Every 3 seconds"] &&
             [controller.temperatureRefreshPopup.titleOfSelectedItem
        isEqualToString:@"Every 30 seconds"] &&
             [controller.diskRefreshPopup.titleOfSelectedItem
        isEqualToString:@"Every 5 minutes"],
             @"all three refresh popups should select their defaults");

    NSView *content = controller.window.contentView;
    NSArray<NSString *> *requiredText = @[
        @"CPU & RAM refresh", @"Temperature refresh", @"Disk refresh",
        @"Faster temperature updates may use more energy.", @"Open at login",
        @"Reset Defaults", @"Close", @"Quit",
    ];
    for (NSString *text in requiredText) {
        MPAssert(MPViewContainsText(content, text),
                 [NSString stringWithFormat:@"settings should contain '%@'", text]);
    }

    MPAssert(controller.cpuRAMRefreshPopup.enabled,
             @"CPU/RAM refresh should be enabled when either metric is on");
    MPAssert(!controller.temperatureRefreshPopup.enabled &&
             !controller.temperatureUnitPopup.enabled,
             @"temperature controls should be disabled when temperature is off");
    MPAssert(!controller.diskRefreshPopup.enabled,
             @"disk refresh should be disabled when disk is off");

    controller.cpuCheckbox.state = NSControlStateValueOff;
    controller.ramCheckbox.state = NSControlStateValueOff;
    controller.temperatureCheckbox.state = NSControlStateValueOn;
    controller.diskCheckbox.state = NSControlStateValueOn;
    [controller metricsChanged:nil];
    MPAssert(delegate.metricsChangeCount == 1 && !controller.cpuRAMRefreshPopup.enabled,
             @"turning both CPU and RAM off should disable their popup");
    MPAssert(controller.temperatureRefreshPopup.enabled &&
             controller.temperatureUnitPopup.enabled &&
             controller.diskRefreshPopup.enabled,
             @"enabled metrics should enable their related controls");

    MPSelectInterval(controller.cpuRAMRefreshPopup, 10.0);
    MPSelectInterval(controller.temperatureRefreshPopup, 3.0);
    MPSelectInterval(controller.diskRefreshPopup, 600.0);
    [controller refreshIntervalChanged:controller.cpuRAMRefreshPopup];
    [controller refreshIntervalChanged:controller.temperatureRefreshPopup];
    [controller refreshIntervalChanged:controller.diskRefreshPopup];
    MPAssert(store.cpuRAMRefreshIntervalSeconds == 10.0 &&
             store.temperatureRefreshIntervalSeconds == 3.0 &&
             store.diskRefreshIntervalSeconds == 600.0,
             @"each popup should persist only its selected interval");
    MPAssert(delegate.intervalChangeCount == 3,
             @"each interval selection should notify orchestration");

    controller.loginCheckbox.state = NSControlStateValueOff;
    [controller loginChanged:nil];
    MPAssert(delegate.loginChangeCount == 1 && !delegate.requestedLoginState,
             @"turning Open at login off should be sent without an automatic re-enable");

    MPAssert([[controller.temperatureUnitPopup accessibilityLabel]
        isEqualToString:@"Temperature unit"],
             @"temperature unit should have an accessibility label");
    MPAssert([[controller.temperatureUnitPopup accessibilityHelp]
        isEqualToString:@"Choose Celsius or Fahrenheit for temperature."],
             @"temperature unit should have VoiceOver help");
    MPAssert([[controller.cpuRAMRefreshPopup accessibilityLabel]
        isEqualToString:@"CPU and RAM refresh interval"],
             @"CPU/RAM refresh should have an accessibility label");
    MPAssert([[controller.temperatureRefreshPopup accessibilityLabel]
        isEqualToString:@"Temperature refresh interval"],
             @"temperature refresh should have an accessibility label");
    MPAssert([[controller.diskRefreshPopup accessibilityLabel]
        isEqualToString:@"Disk refresh interval"],
             @"disk refresh should have an accessibility label");
    MPAssert([[controller.temperatureRefreshPopup accessibilityHelp]
        containsString:@"hottest temperature sensor"] &&
             [[controller.diskRefreshPopup accessibilityHelp]
        containsString:@"home volume"],
             @"metric popup help should identify what is measured");

    [controller showSettingsWindow];
    MPAssert(controller.window.isVisible, @"show should display the settings window");
    [controller closePressed:nil];
    MPAssert(!controller.window.isVisible, @"Close should hide only the settings window");
}

static void MPTestConfirmationAlerts(void) {
    MPSettingsStore *store = [[MPSettingsStore alloc]
        initWithUserDefaults:MPMakeIsolatedDefaults()];
    MPFakeSettingsDelegate *delegate = [[MPFakeSettingsDelegate alloc] init];
    MPSettingsWindowController *controller = [[MPSettingsWindowController alloc]
        initWithSettingsStore:store delegate:delegate];
    __block NSAlert *capturedAlert = nil;
    __block NSModalResponse response = NSAlertSecondButtonReturn;
    controller.alertRunner = ^NSModalResponse(NSAlert *alert) {
        capturedAlert = alert;
        return response;
    };

    [controller quitPressed:nil];
    MPAssert(delegate.quitCount == 0, @"Cancel should keep Menu Pulse running");
    MPAssert([capturedAlert.messageText isEqualToString:@"Quit Menu Pulse?"],
             @"Quit should use the requested confirmation title");
    MPAssert([capturedAlert.informativeText isEqualToString:
        @"Menu bar monitoring will stop.\nOpen at login will remain enabled."],
             @"Quit should explain both monitoring and login behavior");
    MPAssert([capturedAlert.buttons[0].title isEqualToString:@"Quit"] &&
             [capturedAlert.buttons[1].title isEqualToString:@"Cancel"],
             @"Quit action should be right/default and Cancel left");
    MPAssert([capturedAlert.buttons[0].keyEquivalent isEqualToString:@"\r"] &&
             [capturedAlert.buttons[1].keyEquivalent isEqualToString:@"\e"],
             @"Quit should map Return to action and Escape to Cancel");
    response = NSAlertFirstButtonReturn;
    [controller quitPressed:nil];
    MPAssert(delegate.quitCount == 1, @"confirmed Quit should notify orchestration");

    response = NSAlertSecondButtonReturn;
    [controller resetDefaultsPressed:nil];
    MPAssert(delegate.resetCount == 0, @"Cancel should preserve settings");
    MPAssert([capturedAlert.messageText isEqualToString:@"Reset all settings?"],
             @"Reset should use the requested confirmation title");
    MPAssert([capturedAlert.informativeText containsString:@"CPU/RAM: On, every 3 seconds"] &&
             [capturedAlert.informativeText containsString:@"Open at login: On"],
             @"Reset should list the settings it restores");
    MPAssert([capturedAlert.buttons[0].title isEqualToString:@"Reset"] &&
             [capturedAlert.buttons[1].title isEqualToString:@"Cancel"],
             @"Reset action should be right/default and Cancel left");
    MPAssert([capturedAlert.buttons[0].keyEquivalent isEqualToString:@"\r"] &&
             [capturedAlert.buttons[1].keyEquivalent isEqualToString:@"\e"],
             @"Reset should map Return to action and Escape to Cancel");
    response = NSAlertFirstButtonReturn;
    [controller resetDefaultsPressed:nil];
    MPAssert(delegate.resetCount == 1, @"confirmed Reset should notify orchestration");

    response = NSAlertSecondButtonReturn;
    BOOL enable = [controller runOpenAtLoginPrompt];
    MPAssert(!enable && [capturedAlert.messageText isEqualToString:@"Open Menu Pulse at Login?"],
             @"Not Now should decline the one-time login prompt");
    MPAssert([capturedAlert.buttons[0].title isEqualToString:@"Enable"] &&
             [capturedAlert.buttons[1].title isEqualToString:@"Not Now"],
             @"Enable should be right/default and Not Now left");
    MPAssert([capturedAlert.buttons[0].keyEquivalent isEqualToString:@"\r"] &&
             [capturedAlert.buttons[1].keyEquivalent isEqualToString:@"\e"],
             @"Enable should be the Return-key default and Not Now should handle Escape");
    response = NSAlertFirstButtonReturn;
    MPAssert([controller runOpenAtLoginPrompt], @"Enable should accept the login prompt");

    [controller showLoginApprovalAlert];
    MPAssert(delegate.openLoginItemsCount == 1,
             @"approval alert should connect to the System Settings action");
}

static void MPTestOpenAtLoginOnboarding(void) {
    MPFakeLoginItemManager *manager = nil;
    MPMenuPulse *notNowPulse = MPMakePulse(MPMakeIsolatedDefaults(), &manager);
    MPSettingsWindowController *notNowController = [notNowPulse activeSettingsWindowController];
    __block NSUInteger promptCount = 0;
    notNowController.alertRunner = ^NSModalResponse(NSAlert *alert) {
        (void)alert;
        promptCount += 1;
        return NSAlertSecondButtonReturn;
    };
    [notNowPulse handleOpenAtLoginPromptIfNeeded];
    [notNowPulse handleOpenAtLoginPromptIfNeeded];
    MPAssert(notNowPulse.settingsStore.hasCompletedOpenAtLoginPrompt && promptCount == 1,
             @"Not Now should be remembered and never prompt again");
    MPAssert(manager.setCallCount == 0,
             @"Not Now should not modify the system login item");

    MPFakeLoginItemManager *enableManager = nil;
    MPMenuPulse *enablePulse = MPMakePulse(MPMakeIsolatedDefaults(), &enableManager);
    MPSettingsWindowController *enableController = [enablePulse activeSettingsWindowController];
    enableController.alertRunner = ^NSModalResponse(NSAlert *alert) {
        (void)alert;
        return NSAlertFirstButtonReturn;
    };
    [enablePulse handleOpenAtLoginPromptIfNeeded];
    MPAssert(enablePulse.settingsStore.hasCompletedOpenAtLoginPrompt &&
             enableManager.setCallCount == 1 && enableManager.lastRequestedState &&
             enableManager.fakeEnabled,
             @"Enable should register login and remember the prompt");

    MPFakeLoginItemManager *existingManager = nil;
    MPMenuPulse *existingPulse = MPMakePulse(MPMakeIsolatedDefaults(), &existingManager);
    existingManager.fakeEnabled = YES;
    [existingPulse start];
    MPAssert(existingPulse.settingsStore.hasCompletedOpenAtLoginPrompt &&
             existingPulse.settingsWindowController == nil,
             @"startup with an existing login item should keep the settings UI lazy");

    MPFakeLoginItemManager *approvalManager = nil;
    MPMenuPulse *approvalPulse = MPMakePulse(MPMakeIsolatedDefaults(), &approvalManager);
    approvalManager.setSucceeds = NO;
    approvalManager.fakeRequiresApproval = YES;
    MPSettingsWindowController *approvalController = [approvalPulse activeSettingsWindowController];
    approvalController.alertRunner = ^NSModalResponse(NSAlert *alert) {
        (void)alert;
        return NSAlertFirstButtonReturn;
    };
    [approvalPulse handleOpenAtLoginPromptIfNeeded];
    MPAssert(approvalManager.openSettingsCount == 1,
             @"approval-required onboarding should offer System Settings");
}

static void MPTestRapidLoginChangesDiscardStaleCompletion(void) {
    MPFakeLoginItemManager *manager = nil;
    MPMenuPulse *pulse = MPMakePulse(MPMakeIsolatedDefaults(), &manager);
    manager.fakeEnabled = YES;
    manager.autoCompletes = NO;
    pulse.cachedLoginEnabled = YES;
    MPSettingsWindowController *controller = [pulse activeSettingsWindowController];
    controller.loginEnabled = YES;

    [pulse settingsWindowController:controller didRequestLoginEnabled:NO];
    [pulse settingsWindowController:controller didRequestLoginEnabled:YES];
    MPAssert(manager.pendingCompletions.count == 2 && controller.loginCheckbox.state,
             @"rapid OFF then ON should queue both operations and show the latest request");

    [manager completeRequestAtIndex:0 success:YES];
    MPAssert(controller.loginCheckbox.state == NSControlStateValueOn &&
             pulse.cachedLoginEnabled,
             @"an older OFF completion must not overwrite the latest ON state");
    [manager completeRequestAtIndex:1 success:YES];
    MPAssert(controller.loginCheckbox.state == NSControlStateValueOn &&
             pulse.cachedLoginEnabled && manager.fakeEnabled,
             @"the latest login completion should synchronize actual system state");
}

static void MPTestActivationRefreshesLoginState(void) {
    MPFakeLoginItemManager *manager = nil;
    MPMenuPulse *pulse = MPMakePulse(MPMakeIsolatedDefaults(), &manager);
    pulse.settingsStore.hasCompletedOpenAtLoginPrompt = YES;
    MPSettingsWindowController *controller = [pulse activeSettingsWindowController];
    [pulse start];
    manager.fakeEnabled = YES;

    [NSNotificationCenter.defaultCenter
        postNotificationName:NSApplicationDidBecomeActiveNotification
                      object:NSApp];
    MPAssert(pulse.cachedLoginEnabled &&
             controller.loginCheckbox.state == NSControlStateValueOn,
             @"app activation should refresh the open login checkbox from SMAppService");
    MPAssert([[pulse statusTooltip] containsString:@"Open at login: On"],
             @"app activation should refresh the cached tooltip login state");
    [pulse.refreshScheduler stop];
}

static void MPTestResetDefaults(void) {
    MPFakeLoginItemManager *manager = nil;
    MPMenuPulse *pulse = MPMakePulse(MPMakeIsolatedDefaults(), &manager);
    MPSettingsWindowController *controller = [pulse activeSettingsWindowController];
    pulse.settingsStore.showCPU = NO;
    pulse.settingsStore.showRAM = NO;
    pulse.settingsStore.showTemperature = YES;
    pulse.settingsStore.showDisk = YES;
    pulse.settingsStore.temperatureUnit = MPTemperatureUnitFahrenheit;
    pulse.settingsStore.cpuRAMRefreshIntervalSeconds = 10.0;
    pulse.settingsStore.temperatureRefreshIntervalSeconds = 1.0;
    pulse.settingsStore.diskRefreshIntervalSeconds = 60.0;

    [pulse settingsWindowControllerDidRequestResetDefaults:controller];
    MPAssert(pulse.settingsStore.showCPU && pulse.settingsStore.showRAM &&
             !pulse.settingsStore.showTemperature && !pulse.settingsStore.showDisk,
             @"Reset should restore the default metric visibility");
    MPAssert([pulse.settingsStore.temperatureUnit isEqualToString:MPTemperatureUnitCelsius] &&
             pulse.settingsStore.cpuRAMRefreshIntervalSeconds == 3.0 &&
             pulse.settingsStore.temperatureRefreshIntervalSeconds == 30.0 &&
             pulse.settingsStore.diskRefreshIntervalSeconds == 300.0,
             @"Reset should restore unit and all refresh intervals");
    MPAssert(manager.setCallCount == 1 && manager.lastRequestedState,
             @"Reset should turn Open at login on");
}

static void MPTestTemperatureLifecycle(MPMenuPulse *pulse) {
    MPAssert(MPTemperatureRetryAllowed(100.0, NAN),
             @"temperature should retry without a prior failure");
    MPAssert(!MPTemperatureRetryAllowed(399.9, 100.0) &&
             MPTemperatureRetryAllowed(400.0, 100.0),
             @"temperature should retain a five-minute failure cooldown");

    MPFakeTemperatureReader *reader = [[MPFakeTemperatureReader alloc] init];
    pulse.temperatureReader = reader;
    pulse.settingsStore.showTemperature = YES;
    pulse.refreshScheduler = [[MPRefreshScheduler alloc] initWithDueHandler:^(MPRefreshMetric metrics) {
        (void)metrics;
    }];
    pulse.refreshScheduler.activeMetrics = MPRefreshMetricTemperature;

    [pulse requestTemperatureRead];
    [pulse requestTemperatureRead];
    MPAssert(reader.completions.count == 1 && pulse.temperatureReadInFlight,
             @"a slow temperature read should not overlap another request");
    MPAssert((pulse.refreshScheduler.pausedMetrics & MPRefreshMetricTemperature) != 0,
             @"an in-flight temperature read should pause its scheduler deadline");

    pulse.settingsStore.showTemperature = NO;
    [pulse releaseTemperatureReaderIfDisabled];
    MPAssert(reader.invalidateCount == 1 && !pulse.temperatureReadInFlight,
             @"turning temperature off should cancel UI state and release hardware");
    MPAssert(pulse.temperatureReader == reader,
             @"turning temperature off should preserve the reader cooldown state");
    MPAssert((pulse.refreshScheduler.pausedMetrics & MPRefreshMetricTemperature) == 0,
             @"turning temperature off should clear an in-flight pause");

    pulse.settingsStore.showTemperature = YES;
    pulse.refreshScheduler.activeMetrics = MPRefreshMetricTemperature;
    [pulse requestTemperatureRead];
    reader.completions[0](@99.0);
    MPAssert(pulse.cachedTemperature == nil && pulse.temperatureReadInFlight,
             @"an older completion should be discarded");
    reader.completions[1](@55.0);
    MPAssert([pulse.cachedTemperature isEqualToNumber:@55.0] &&
             !pulse.temperatureReadInFlight &&
             (pulse.refreshScheduler.pausedMetrics & MPRefreshMetricTemperature) == 0,
             @"the current completion should apply and resume from completion time");

    [pulse requestTemperatureRead];
    reader.completions[2](nil);
    NSTimeInterval delay = pulse.refreshScheduler.nextDelayAtCurrentTime;
    MPAssert(delay > 299.0 && delay <= MPTemperatureFailureRetryInterval,
             @"a failed read should defer the scheduler for five minutes");
}

static void MPTestStaleTemperatureFailurePreservesCooldown(void) {
    MPFakeLoginItemManager *manager = nil;
    MPMenuPulse *pulse = MPMakePulse(MPMakeIsolatedDefaults(), &manager);
    (void)manager;
    MPFakeTemperatureReader *reader = [[MPFakeTemperatureReader alloc] init];
    pulse.temperatureReader = reader;
    pulse.settingsStore.showTemperature = YES;

    MPFakeClock *clock = [[MPFakeClock alloc] init];
    clock.now = 100.0;
    pulse.refreshScheduler = [[MPRefreshScheduler alloc]
        initWithClock:clock
        callbackQueue:dispatch_get_main_queue()
        dueHandler:^(MPRefreshMetric metrics) {
            (void)metrics;
        }];
    pulse.refreshScheduler.activeMetrics = MPRefreshMetricTemperature;
    [pulse requestTemperatureRead];

    pulse.settingsStore.showTemperature = NO;
    [pulse releaseTemperatureReaderIfDisabled];
    pulse.refreshScheduler.activeMetrics = MPRefreshMetricNone;
    reader.completions[0](nil);

    clock.now = 399.0;
    pulse.settingsStore.showTemperature = YES;
    pulse.refreshScheduler.activeMetrics = MPRefreshMetricTemperature;
    NSTimeInterval delay = pulse.refreshScheduler.nextDelayAtCurrentTime;
    MPAssert(fabs(delay - 1.0) < 0.001,
             @"a stale failed completion should preserve cooldown across OFF/ON");
    MPAssert(!pulse.temperatureReadInFlight,
             @"a stale completion should not restore the canceled in-flight UI state");
}

static void MPTestQueuedTemperatureCancellation(void) {
    MPBlockingTemperatureReader *reader = [[MPBlockingTemperatureReader alloc] init];
    __block NSUInteger firstCompletionCount = 0;
    __block NSUInteger canceledCompletionCount = 0;
    __block NSUInteger finalCompletionCount = 0;

    [reader temperatureCelsiusAsync:^(NSNumber *temperature) {
        (void)temperature;
        firstCompletionCount += 1;
    }];
    long didStart = dispatch_semaphore_wait(
        reader.firstReadStarted,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)NSEC_PER_SEC)
    );
    MPAssert(didStart == 0, @"the first fake temperature read should start");

    [reader temperatureCelsiusAsync:^(NSNumber *temperature) {
        (void)temperature;
        canceledCompletionCount += 1;
    }];
    [reader invalidateHardware];
    [reader temperatureCelsiusAsync:^(NSNumber *temperature) {
        (void)temperature;
        finalCompletionCount += 1;
    }];
    dispatch_semaphore_signal(reader.allowFirstReadToFinish);

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (firstCompletionCount + finalCompletionCount < 2 &&
           deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    MPAssert(reader.readCount == 2,
             @"only the active and post-invalidation temperature reads should touch sensors");
    MPAssert(firstCompletionCount == 1 && finalCompletionCount == 1 &&
             canceledCompletionCount == 0,
             @"a queued pre-invalidation temperature request should be canceled silently");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        MPFakeLoginItemManager *manager = nil;
        MPMenuPulse *pulse = MPMakePulse(MPMakeIsolatedDefaults(), &manager);
        (void)manager;
        MPTestStatusRowsAndTooltip(pulse);
        MPTestSettingsWindowControls();
        MPTestConfirmationAlerts();
        MPTestOpenAtLoginOnboarding();
        MPTestRapidLoginChangesDiscardStaleCompletion();
        MPTestActivationRefreshesLoginState();
        MPTestResetDefaults();
        MPTestTemperatureLifecycle(pulse);
        MPTestStaleTemperatureFailurePreservesCooldown();
        MPTestQueuedTemperatureCancellation();
        MPTestAsyncLoginItemUpdates();
        MPTestLoginItemMigrationControl();

        if (MPFailureCount != 0) {
            fprintf(stderr, "%lu UI test(s) failed\n", (unsigned long)MPFailureCount);
            return 1;
        }
        fprintf(stdout, "Menu Pulse UI tests passed\n");
    }
    return 0;
}
