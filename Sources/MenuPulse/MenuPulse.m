#import "MenuPulse.h"

#import "LoginItemManager.h"
#import "Monitors.h"
#import "TemperatureReader.h"

#import <AppKit/AppKit.h>

static const NSTimeInterval MPDefaultCPURefreshInterval = 10.0;
static const NSTimeInterval MPDefaultRAMRefreshInterval = 10.0;
static const NSTimeInterval MPDefaultTemperatureRefreshInterval = 30.0;
static const NSTimeInterval MPDefaultDiskRefreshInterval = 300.0;
static const NSTimeInterval MPStartupWarmUpDelay = 1.0;

static NSString * const MPSettingShowCPU = @"showCPU";
static NSString * const MPSettingShowTemperature = @"showTemperature";
static NSString * const MPSettingShowRAM = @"showRAM";
static NSString * const MPSettingShowDisk = @"showDisk";
static NSString * const MPSettingCPURefreshInterval = @"cpuRefreshInterval";
static NSString * const MPSettingRAMRefreshInterval = @"ramRefreshInterval";
static NSString * const MPSettingTemperatureRefreshInterval = @"temperatureRefreshInterval";
static NSString * const MPSettingDiskRefreshInterval = @"diskRefreshInterval";
static NSString * const MPSettingTemperatureUnit = @"temperatureUnit";
static NSString * const MPTemperatureUnitCelsius = @"C";
static NSString * const MPTemperatureUnitFahrenheit = @"F";

static NSArray<NSNumber *> *MPRefreshChoices(void) {
    static NSArray<NSNumber *> *choices;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        choices = @[@5, @10, @15, @30, @60, @120, @300];
    });
    return choices;
}

@interface MPMenuPulse () <NSWindowDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) MPLoginItemManager *loginItemManager;
@property(nonatomic, strong) MPCPUMonitor *cpuMonitor;
@property(nonatomic, strong, nullable) MPTemperatureReader *temperatureReader;
@property(nonatomic, strong, nullable) NSTimer *timer;
@property(nonatomic, strong, nullable) NSNumber *cachedCPU;
@property(nonatomic, strong, nullable) NSNumber *cachedRAM;
@property(nonatomic, strong, nullable) NSNumber *cachedTemperature;
@property(nonatomic, strong, nullable) NSNumber *cachedDisk;
@property(nonatomic, strong) NSDate *lastCPURead;
@property(nonatomic, strong) NSDate *lastRAMRead;
@property(nonatomic, strong) NSDate *lastTemperatureRead;
@property(nonatomic, strong) NSDate *lastDiskRead;
@property(nonatomic) BOOL temperatureReadInFlight;
@property(nonatomic) BOOL cachedLoginEnabled;
@property(nonatomic, copy) NSArray<NSString *> *lastRenderedRows;
@property(nonatomic, strong, nullable) NSWindow *settingsWindow;
@property(nonatomic, weak, nullable) NSButton *cpuCheckbox;
@property(nonatomic, weak, nullable) NSButton *temperatureCheckbox;
@property(nonatomic, weak, nullable) NSButton *ramCheckbox;
@property(nonatomic, weak, nullable) NSButton *diskCheckbox;
@property(nonatomic, weak, nullable) NSButton *loginCheckbox;
@property(nonatomic, weak, nullable) NSPopUpButton *cpuRefreshPopup;
@property(nonatomic, weak, nullable) NSPopUpButton *temperatureRefreshPopup;
@property(nonatomic, weak, nullable) NSPopUpButton *ramRefreshPopup;
@property(nonatomic, weak, nullable) NSPopUpButton *diskRefreshPopup;
@property(nonatomic, weak, nullable) NSPopUpButton *temperatureUnitPopup;
@end

@implementation MPMenuPulse

- (instancetype)init {
    self = [super init];
    if (self) {
        _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
        _loginItemManager = [[MPLoginItemManager alloc] init];
        _cpuMonitor = [[MPCPUMonitor alloc] init];
        _lastCPURead = [NSDate distantPast];
        _lastRAMRead = [NSDate distantPast];
        _lastTemperatureRead = [NSDate distantPast];
        _lastDiskRead = [NSDate distantPast];
        _lastRenderedRows = @[];
    }
    return self;
}

- (void)start {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        MPSettingShowCPU: @YES,
        MPSettingShowTemperature: @NO,
        MPSettingShowRAM: @YES,
        MPSettingShowDisk: @NO,
        MPSettingCPURefreshInterval: @(MPDefaultCPURefreshInterval),
        MPSettingRAMRefreshInterval: @(MPDefaultRAMRefreshInterval),
        MPSettingTemperatureRefreshInterval: @(MPDefaultTemperatureRefreshInterval),
        MPSettingDiskRefreshInterval: @(MPDefaultDiskRefreshInterval),
        MPSettingTemperatureUnit: MPTemperatureUnitCelsius,
    }];

    self.cachedLoginEnabled = self.loginItemManager.isEnabled;

    NSStatusBarButton *button = self.statusItem.button;
    button.imagePosition = NSImageOnly;
    button.target = self;
    button.action = @selector(showSettings);
    button.toolTip = @"Menu Pulse Settings";

    [self refreshWithForce:YES];
    [self prepareStartupWarmUp];
    [self scheduleNextRefresh];
}

- (BOOL)showCPU {
    return [NSUserDefaults.standardUserDefaults boolForKey:MPSettingShowCPU];
}

- (void)setShowCPU:(BOOL)value {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:MPSettingShowCPU];
}

- (BOOL)showTemperature {
    return [NSUserDefaults.standardUserDefaults boolForKey:MPSettingShowTemperature];
}

- (void)setShowTemperature:(BOOL)value {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:MPSettingShowTemperature];
}

- (BOOL)showRAM {
    return [NSUserDefaults.standardUserDefaults boolForKey:MPSettingShowRAM];
}

- (void)setShowRAM:(BOOL)value {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:MPSettingShowRAM];
}

- (BOOL)showDisk {
    return [NSUserDefaults.standardUserDefaults boolForKey:MPSettingShowDisk];
}

- (void)setShowDisk:(BOOL)value {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:MPSettingShowDisk];
}

- (NSTimeInterval)cpuRefreshInterval {
    return [self intervalForKey:MPSettingCPURefreshInterval defaultValue:MPDefaultCPURefreshInterval];
}

- (void)setCpuRefreshInterval:(NSTimeInterval)value {
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:MPSettingCPURefreshInterval];
}

- (NSTimeInterval)ramRefreshInterval {
    return [self intervalForKey:MPSettingRAMRefreshInterval defaultValue:MPDefaultRAMRefreshInterval];
}

- (void)setRamRefreshInterval:(NSTimeInterval)value {
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:MPSettingRAMRefreshInterval];
}

- (NSTimeInterval)temperatureRefreshInterval {
    return [self intervalForKey:MPSettingTemperatureRefreshInterval defaultValue:MPDefaultTemperatureRefreshInterval];
}

- (void)setTemperatureRefreshInterval:(NSTimeInterval)value {
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:MPSettingTemperatureRefreshInterval];
}

- (NSTimeInterval)diskRefreshInterval {
    return [self intervalForKey:MPSettingDiskRefreshInterval defaultValue:MPDefaultDiskRefreshInterval];
}

- (void)setDiskRefreshInterval:(NSTimeInterval)value {
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:MPSettingDiskRefreshInterval];
}

- (NSString *)temperatureUnit {
    NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:MPSettingTemperatureUnit];
    if ([value isEqualToString:MPTemperatureUnitFahrenheit]) {
        return MPTemperatureUnitFahrenheit;
    }

    return MPTemperatureUnitCelsius;
}

- (void)setTemperatureUnit:(NSString *)value {
    [NSUserDefaults.standardUserDefaults setObject:value forKey:MPSettingTemperatureUnit];
}

- (void)showSettings {
    if (!self.settingsWindow) {
        self.settingsWindow = [self makeSettingsWindow];
    }

    [self syncSettingsControls];
    [self.settingsWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSWindow *)makeSettingsWindow {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 360, 344)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Menu Pulse Settings";
    window.releasedWhenClosed = NO;
    window.delegate = self;
    [window center];

    NSView *contentView = [[NSView alloc] init];
    window.contentView = contentView;

    NSStackView *root = [[NSStackView alloc] init];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 14;
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *header = [NSTextField labelWithString:@"Show in menu bar"];
    header.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];

    NSButton *cpu = [NSButton checkboxWithTitle:@"CPU usage" target:self action:@selector(settingsChanged)];
    NSButton *ram = [NSButton checkboxWithTitle:@"RAM usage" target:self action:@selector(settingsChanged)];
    NSButton *temperature = [NSButton checkboxWithTitle:@"Temperature" target:self action:@selector(settingsChanged)];
    NSButton *disk = [NSButton checkboxWithTitle:@"Disk usage" target:self action:@selector(settingsChanged)];
    NSButton *login = [NSButton checkboxWithTitle:@"Open at login" target:self action:@selector(loginChanged)];
    NSPopUpButton *cpuPopup = [self makeRefreshPopup];
    NSPopUpButton *ramPopup = [self makeRefreshPopup];
    NSPopUpButton *temperaturePopup = [self makeRefreshPopup];
    NSPopUpButton *diskPopup = [self makeRefreshPopup];
    NSPopUpButton *temperatureUnitPopup = [self makeTemperatureUnitPopup];

    self.cpuCheckbox = cpu;
    self.ramCheckbox = ram;
    self.temperatureCheckbox = temperature;
    self.diskCheckbox = disk;
    self.loginCheckbox = login;
    self.cpuRefreshPopup = cpuPopup;
    self.ramRefreshPopup = ramPopup;
    self.temperatureRefreshPopup = temperaturePopup;
    self.diskRefreshPopup = diskPopup;
    self.temperatureUnitPopup = temperatureUnitPopup;

    [root addArrangedSubview:header];
    [root addArrangedSubview:[self makeSettingsRowWithLeft:[self makeMetricViewWithCheckbox:cpu popup:cpuPopup unitPopup:nil]
                                                     right:[self makeMetricViewWithCheckbox:ram popup:ramPopup unitPopup:nil]]];
    [root addArrangedSubview:[self makeSettingsRowWithLeft:[self makeMetricViewWithCheckbox:temperature popup:temperaturePopup unitPopup:temperatureUnitPopup]
                                                     right:[self makeMetricViewWithCheckbox:disk popup:diskPopup unitPopup:nil]]];
    [root addArrangedSubview:[self makeActionsViewWithLogin:login]];
    [contentView addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:18],
        [root.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-18],
        [root.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:18],
    ]];

    return window;
}

- (NSStackView *)makeMetricViewWithCheckbox:(NSButton *)checkbox
                                      popup:(NSPopUpButton *)popup
                                  unitPopup:(NSPopUpButton *)unitPopup {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack.widthAnchor constraintEqualToConstant:150].active = YES;

    NSTextField *label = [NSTextField labelWithString:@"Refresh"];
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = NSColor.secondaryLabelColor;

    [stack addArrangedSubview:checkbox];
    [stack addArrangedSubview:label];
    [stack addArrangedSubview:popup];

    if (unitPopup) {
        NSTextField *unitLabel = [NSTextField labelWithString:@"Unit"];
        unitLabel.font = [NSFont systemFontOfSize:11];
        unitLabel.textColor = NSColor.secondaryLabelColor;
        [stack addArrangedSubview:unitLabel];
        [stack addArrangedSubview:unitPopup];
    }

    return stack;
}

- (NSStackView *)makeActionsViewWithLogin:(NSButton *)login {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack.widthAnchor constraintEqualToConstant:320].active = YES;

    NSStackView *buttonRow = [[NSStackView alloc] init];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.alignment = NSLayoutAttributeCenterY;
    buttonRow.spacing = 8;

    NSButton *resetButton = [NSButton buttonWithTitle:@"Reset Defaults" target:self action:@selector(resetDefaults)];
    NSButton *closeButton = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeSettings)];
    NSButton *quitButton = [NSButton buttonWithTitle:@"Quit" target:self action:@selector(quit)];
    resetButton.bezelStyle = NSBezelStyleRounded;
    closeButton.bezelStyle = NSBezelStyleRounded;
    quitButton.bezelStyle = NSBezelStyleRounded;

    [stack addArrangedSubview:login];
    [buttonRow addArrangedSubview:resetButton];
    [buttonRow addArrangedSubview:closeButton];
    [buttonRow addArrangedSubview:quitButton];
    [stack addArrangedSubview:buttonRow];
    return stack;
}

- (NSStackView *)makeSettingsRowWithLeft:(NSView *)left right:(NSView *)right {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeTop;
    row.spacing = 20;
    [row addArrangedSubview:left];
    [row addArrangedSubview:right];
    return row;
}

- (NSPopUpButton *)makeRefreshPopup {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.target = self;
    popup.action = @selector(refreshIntervalChanged);
    [popup.widthAnchor constraintEqualToConstant:92].active = YES;

    for (NSNumber *choice in MPRefreshChoices()) {
        [popup addItemWithTitle:[NSString stringWithFormat:@"%d sec", choice.intValue]];
        popup.lastItem.representedObject = choice;
    }

    return popup;
}

- (NSPopUpButton *)makeTemperatureUnitPopup {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.target = self;
    popup.action = @selector(temperatureUnitChanged);
    [popup.widthAnchor constraintEqualToConstant:116].active = YES;

    [popup addItemWithTitle:@"Celsius (\u00B0C)"];
    popup.lastItem.representedObject = MPTemperatureUnitCelsius;
    [popup addItemWithTitle:@"Fahrenheit (\u00B0F)"];
    popup.lastItem.representedObject = MPTemperatureUnitFahrenheit;

    return popup;
}

- (void)syncSettingsControls {
    self.cpuCheckbox.state = self.showCPU ? NSControlStateValueOn : NSControlStateValueOff;
    self.temperatureCheckbox.state = self.showTemperature ? NSControlStateValueOn : NSControlStateValueOff;
    self.ramCheckbox.state = self.showRAM ? NSControlStateValueOn : NSControlStateValueOff;
    self.diskCheckbox.state = self.showDisk ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginCheckbox.state = self.cachedLoginEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self selectRefreshInterval:self.cpuRefreshInterval inPopup:self.cpuRefreshPopup];
    [self selectRefreshInterval:self.ramRefreshInterval inPopup:self.ramRefreshPopup];
    [self selectRefreshInterval:self.temperatureRefreshInterval inPopup:self.temperatureRefreshPopup];
    [self selectRefreshInterval:self.diskRefreshInterval inPopup:self.diskRefreshPopup];
    [self selectTemperatureUnit:self.temperatureUnit inPopup:self.temperatureUnitPopup];
    [self updateSettingsControlState];
}

- (void)settingsChanged {
    self.showCPU = self.cpuCheckbox.state == NSControlStateValueOn;
    self.showTemperature = self.temperatureCheckbox.state == NSControlStateValueOn;
    self.showRAM = self.ramCheckbox.state == NSControlStateValueOn;
    self.showDisk = self.diskCheckbox.state == NSControlStateValueOn;
    [self releaseTemperatureReaderIfDisabled];
    [self updateSettingsControlState];
    [self refreshWithForce:YES];
    [self scheduleNextRefresh];
}

- (void)temperatureUnitChanged {
    self.temperatureUnit = [self selectedTemperatureUnitFromPopup:self.temperatureUnitPopup];
    [self updateStatusImage];
}

- (void)refreshIntervalChanged {
    self.cpuRefreshInterval = [self selectedRefreshIntervalFromPopup:self.cpuRefreshPopup defaultValue:MPDefaultCPURefreshInterval];
    self.ramRefreshInterval = [self selectedRefreshIntervalFromPopup:self.ramRefreshPopup defaultValue:MPDefaultRAMRefreshInterval];
    self.temperatureRefreshInterval =
        [self selectedRefreshIntervalFromPopup:self.temperatureRefreshPopup defaultValue:MPDefaultTemperatureRefreshInterval];
    self.diskRefreshInterval = [self selectedRefreshIntervalFromPopup:self.diskRefreshPopup defaultValue:MPDefaultDiskRefreshInterval];
    [self refreshWithForce:YES];
    [self scheduleNextRefresh];
}

- (void)loginChanged {
    BOOL shouldEnable = self.loginCheckbox.state == NSControlStateValueOn;
    if (![self.loginItemManager setEnabled:shouldEnable]) {
        NSBeep();
        self.cachedLoginEnabled = self.loginItemManager.isEnabled;
        self.loginCheckbox.state = self.cachedLoginEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        return;
    }

    self.cachedLoginEnabled = shouldEnable;
    [self updateStatusImage];
}

- (void)closeSettings {
    [self.settingsWindow close];
}

- (void)resetDefaults {
    self.showCPU = YES;
    self.showRAM = YES;
    self.showTemperature = NO;
    self.showDisk = NO;
    self.cpuRefreshInterval = MPDefaultCPURefreshInterval;
    self.ramRefreshInterval = MPDefaultRAMRefreshInterval;
    self.temperatureRefreshInterval = MPDefaultTemperatureRefreshInterval;
    self.diskRefreshInterval = MPDefaultDiskRefreshInterval;
    self.temperatureUnit = MPTemperatureUnitCelsius;
    [self releaseTemperatureReaderIfDisabled];
    [self syncSettingsControls];
    [self refreshWithForce:YES];
    [self scheduleNextRefresh];
}

- (void)quit {
    [NSApp terminate:nil];
}

- (void)refreshWithForce:(BOOL)force {
    NSDate *now = [NSDate date];

    if (self.showCPU && (force || [now timeIntervalSinceDate:self.lastCPURead] >= self.cpuRefreshInterval)) {
        self.cachedCPU = [self.cpuMonitor usagePercent];
        self.lastCPURead = now;
    }

    if (self.showRAM && (force || [now timeIntervalSinceDate:self.lastRAMRead] >= self.ramRefreshInterval)) {
        self.cachedRAM = [MPMemoryMonitor usagePercent];
        self.lastRAMRead = now;
    }

    if (self.showTemperature &&
        (force || [now timeIntervalSinceDate:self.lastTemperatureRead] >= self.temperatureRefreshInterval)) {
        [self requestTemperatureReadStartedAt:now];
    }

    if (self.showDisk && (force || [now timeIntervalSinceDate:self.lastDiskRead] >= self.diskRefreshInterval)) {
        self.cachedDisk = [MPDiskMonitor usagePercent];
        self.lastDiskRead = now;
    }

    [self updateStatusImage];
}

- (void)prepareStartupWarmUp {
    if (!self.showCPU || self.cachedCPU) {
        return;
    }

    NSTimeInterval offset = -MAX(0.0, self.cpuRefreshInterval - MPStartupWarmUpDelay);
    self.lastCPURead = [[NSDate date] dateByAddingTimeInterval:offset];
}

- (MPTemperatureReader *)activeTemperatureReader {
    if (self.temperatureReader) {
        return self.temperatureReader;
    }

    MPTemperatureReader *reader = [[MPTemperatureReader alloc] init];
    self.temperatureReader = reader;
    return reader;
}

- (void)releaseTemperatureReaderIfDisabled {
    if (self.showTemperature) {
        return;
    }

    self.temperatureReadInFlight = NO;
    self.cachedTemperature = nil;
    self.lastTemperatureRead = [NSDate distantPast];
    self.temperatureReader = nil;
}

- (void)requestTemperatureReadStartedAt:(NSDate *)date {
    if (self.temperatureReadInFlight) {
        return;
    }

    self.temperatureReadInFlight = YES;
    self.lastTemperatureRead = date;

    __weak typeof(self) weakSelf = self;
    [[self activeTemperatureReader] temperatureCelsiusAsync:^(NSNumber *temperatureCelsius) {
        MPMenuPulse *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        strongSelf.temperatureReadInFlight = NO;
        if (!strongSelf.showTemperature) {
            strongSelf.cachedTemperature = nil;
            [strongSelf updateStatusImage];
            [strongSelf scheduleNextRefresh];
            return;
        }

        strongSelf.cachedTemperature = temperatureCelsius;
        [strongSelf updateStatusImage];
        [strongSelf scheduleNextRefresh];
    }];
}

- (void)scheduleNextRefresh {
    [self.timer invalidate];
    self.timer = nil;

    NSNumber *delayNumber = [self nextRefreshDelay];
    if (!delayNumber) {
        return;
    }

    NSTimeInterval delay = delayNumber.doubleValue;
    NSTimer *nextTimer = [NSTimer scheduledTimerWithTimeInterval:delay
                                                          target:self
                                                        selector:@selector(timerFired:)
                                                        userInfo:nil
                                                         repeats:NO];
    nextTimer.tolerance = MIN(MAX(delay * 0.1, 0.5), 5.0);
    self.timer = nextTimer;
}

- (void)timerFired:(NSTimer *)timer {
    [self refreshWithForce:NO];
    [self scheduleNextRefresh];
}

- (NSNumber *)nextRefreshDelay {
    NSDate *now = [NSDate date];
    NSMutableArray<NSNumber *> *delays = [NSMutableArray array];

    if (self.showCPU) {
        [delays addObject:@(MAX(1.0, self.cpuRefreshInterval - [now timeIntervalSinceDate:self.lastCPURead]))];
    }

    if (self.showRAM) {
        [delays addObject:@(MAX(1.0, self.ramRefreshInterval - [now timeIntervalSinceDate:self.lastRAMRead]))];
    }

    if (self.showTemperature && !self.temperatureReadInFlight) {
        [delays addObject:@(MAX(1.0, self.temperatureRefreshInterval - [now timeIntervalSinceDate:self.lastTemperatureRead]))];
    }

    if (self.showDisk) {
        [delays addObject:@(MAX(1.0, self.diskRefreshInterval - [now timeIntervalSinceDate:self.lastDiskRead]))];
    }

    NSNumber *minimum = nil;
    for (NSNumber *delay in delays) {
        if (!minimum || delay.doubleValue < minimum.doubleValue) {
            minimum = delay;
        }
    }

    return minimum;
}

- (void)updateStatusImage {
    NSArray<NSString *> *rows = [self statusRows];
    NSString *tooltip = [self statusTooltip];
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
    NSString *cpu = self.showCPU ? [NSString stringWithFormat:@"CPU:%@", [self formatPercent:self.cachedCPU]] : nil;
    NSString *ram = self.showRAM ? [NSString stringWithFormat:@"RAM:%@", [self formatPercent:self.cachedRAM]] : nil;
    NSString *temperature = self.showTemperature ?
        [NSString stringWithFormat:@"TEMP:%@", [self formatTemperature:self.cachedTemperature]] : nil;
    NSString *disk = self.showDisk ? [NSString stringWithFormat:@"DISK:%@", [self formatPercent:self.cachedDisk]] : nil;

    NSArray<NSString *> *leftColumn = [self compactValues:@[cpu ?: NSNull.null, ram ?: NSNull.null]];
    NSArray<NSString *> *rightColumn = [self compactValues:@[temperature ?: NSNull.null, disk ?: NSNull.null]];

    if (leftColumn.count == 0 && rightColumn.count == 0) {
        return @[@"menu:", @"pulse"];
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
        CGFloat y = index == 0 ? 12.0 : 1.0;
        [rows[index] drawAtPoint:NSMakePoint(0, y) withAttributes:attributes];
    }

    [image unlockFocus];
    image.template = NO;
    return image;
}

- (CGFloat)textWidth:(NSString *)value attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes {
    return [value sizeWithAttributes:attributes].width;
}

- (NSTimeInterval)intervalForKey:(NSString *)key defaultValue:(NSTimeInterval)defaultValue {
    double value = [NSUserDefaults.standardUserDefaults doubleForKey:key];
    for (NSNumber *choice in MPRefreshChoices()) {
        if (fabs(choice.doubleValue - value) < 0.001) {
            return value;
        }
    }

    return defaultValue;
}

- (void)selectRefreshInterval:(NSTimeInterval)interval inPopup:(NSPopUpButton *)popup {
    if (!popup) {
        return;
    }

    for (NSMenuItem *item in popup.itemArray) {
        NSNumber *value = item.representedObject;
        if ([value isKindOfClass:[NSNumber class]] && fabs(value.doubleValue - interval) < 0.001) {
            [popup selectItem:item];
            return;
        }
    }
}

- (NSTimeInterval)selectedRefreshIntervalFromPopup:(NSPopUpButton *)popup defaultValue:(NSTimeInterval)defaultValue {
    NSNumber *value = popup.selectedItem.representedObject;
    return [value isKindOfClass:[NSNumber class]] ? value.doubleValue : defaultValue;
}

- (void)selectTemperatureUnit:(NSString *)unit inPopup:(NSPopUpButton *)popup {
    if (!popup) {
        return;
    }

    for (NSMenuItem *item in popup.itemArray) {
        NSString *value = item.representedObject;
        if ([value isKindOfClass:[NSString class]] && [value isEqualToString:unit]) {
            [popup selectItem:item];
            return;
        }
    }
}

- (NSString *)selectedTemperatureUnitFromPopup:(NSPopUpButton *)popup {
    NSString *value = popup.selectedItem.representedObject;
    if ([value isKindOfClass:[NSString class]] && [value isEqualToString:MPTemperatureUnitFahrenheit]) {
        return MPTemperatureUnitFahrenheit;
    }

    return MPTemperatureUnitCelsius;
}

- (void)updateSettingsControlState {
    self.cpuRefreshPopup.enabled = self.showCPU;
    self.ramRefreshPopup.enabled = self.showRAM;
    self.temperatureRefreshPopup.enabled = self.showTemperature;
    self.diskRefreshPopup.enabled = self.showDisk;
    self.temperatureUnitPopup.enabled = self.showTemperature;
}

- (NSString *)statusTooltip {
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:@"Menu Pulse"];

    if (self.showCPU) {
        [lines addObject:[NSString stringWithFormat:@"CPU: %@ (every %@)",
                          [self formatPercent:self.cachedCPU],
                          [self formatInterval:self.cpuRefreshInterval]]];
    }

    if (self.showRAM) {
        [lines addObject:[NSString stringWithFormat:@"RAM: %@ (every %@)",
                          [self formatPercent:self.cachedRAM],
                          [self formatInterval:self.ramRefreshInterval]]];
    }

    if (self.showTemperature) {
        NSString *temperature = self.temperatureReadInFlight && !self.cachedTemperature ?
            @"warming up" :
            [self formatTemperature:self.cachedTemperature];
        [lines addObject:[NSString stringWithFormat:@"Temperature: %@ (every %@)",
                          temperature,
                          [self formatInterval:self.temperatureRefreshInterval]]];
    }

    if (self.showDisk) {
        [lines addObject:[NSString stringWithFormat:@"Disk: %@ (every %@)",
                          [self formatPercent:self.cachedDisk],
                          [self formatInterval:self.diskRefreshInterval]]];
    }

    if (!self.showCPU && !self.showRAM && !self.showTemperature && !self.showDisk) {
        [lines addObject:@"No metrics enabled"];
    }

    [lines addObject:[NSString stringWithFormat:@"Open at login: %@", self.cachedLoginEnabled ? @"On" : @"Off"]];
    [lines addObject:@"Click to open settings"];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)formatInterval:(NSTimeInterval)value {
    return [NSString stringWithFormat:@"%ds", (int)value];
}

- (NSString *)formatPercent:(NSNumber *)value {
    if (!value) {
        return @"--%";
    }

    return [NSString stringWithFormat:@"%3d%%", (int)llround(value.doubleValue)];
}

- (NSString *)formatTemperature:(NSNumber *)value {
    NSString *symbol = [self.temperatureUnit isEqualToString:MPTemperatureUnitFahrenheit] ? @"\u00B0F" : @"\u00B0C";
    if (!value) {
        return [self paddedTemperature:[NSString stringWithFormat:@"--%@", symbol]];
    }

    double number = value.doubleValue;
    if ([self.temperatureUnit isEqualToString:MPTemperatureUnitFahrenheit]) {
        number = number * 9.0 / 5.0 + 32.0;
    }

    return [self paddedTemperature:[NSString stringWithFormat:@"%d%@", (int)llround(number), symbol]];
}

- (NSString *)paddedTemperature:(NSString *)value {
    NSInteger width = 5;
    NSInteger padding = MAX(0, width - (NSInteger)value.length);
    if (padding == 0) {
        return value;
    }

    return [[@"" stringByPaddingToLength:(NSUInteger)padding withString:@" " startingAtIndex:0] stringByAppendingString:value];
}

- (NSArray<NSString *> *)twoRowsFromValues:(NSArray<NSString *> *)values {
    if (values.count == 1) {
        return @[values[0], @""];
    }

    return [values subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)2, values.count))];
}

- (NSString *)joinStatusColumnLeft:(NSString *)left right:(NSString *)right {
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    if (left) {
        [values addObject:left];
    }
    if (right) {
        [values addObject:right];
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

- (NSString *)valueAtIndex:(NSUInteger)index inArray:(NSArray<NSString *> *)array {
    return index < array.count ? array[index] : nil;
}

- (void)windowWillClose:(NSNotification *)notification {
    self.settingsWindow = nil;
}

@end
