#import "MenuPulse.h"

#import "LoginItemManager.h"
#import "Monitors.h"
#import "RefreshScheduler.h"
#import "SettingsStore.h"
#import "TemperatureReader.h"

#import <AppKit/AppKit.h>

@interface MPMenuPulse () <NSWindowDelegate>
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
@property(nonatomic, copy) NSArray<NSString *> *lastRenderedRows;
@property(nonatomic, strong, nullable) NSWindow *settingsWindow;
@property(nonatomic, weak, nullable) NSButton *cpuCheckbox;
@property(nonatomic, weak, nullable) NSButton *temperatureCheckbox;
@property(nonatomic, weak, nullable) NSButton *ramCheckbox;
@property(nonatomic, weak, nullable) NSButton *diskCheckbox;
@property(nonatomic, weak, nullable) NSButton *loginCheckbox;
@property(nonatomic, weak, nullable) NSPopUpButton *cpuRAMRefreshPopup;
@property(nonatomic, weak, nullable) NSPopUpButton *temperatureUnitPopup;
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

    self.cachedLoginEnabled = self.loginItemManager.isEnabled;

    NSStatusBarButton *button = self.statusItem.button;
    button.imagePosition = NSImageOnly;
    button.target = self;
    button.action = @selector(showSettings);
    button.toolTip = @"Menu Pulse Settings";

    __weak typeof(self) weakSelf = self;
    self.refreshScheduler = [[MPRefreshScheduler alloc] initWithDueHandler:^(MPRefreshMetric dueMetrics) {
        [weakSelf refreshMetrics:dueMetrics];
    }];
    self.refreshScheduler.cpuRAMRefreshIntervalSeconds = self.cpuRAMRefreshIntervalSeconds;
    self.refreshScheduler.activeMetrics = [self activeRefreshMetrics];
    [self.refreshScheduler start];
    [self updateStatusImage];
}

- (BOOL)showCPU {
    return self.settingsStore.showCPU;
}

- (void)setShowCPU:(BOOL)value {
    self.settingsStore.showCPU = value;
}

- (BOOL)showTemperature {
    return self.settingsStore.showTemperature;
}

- (void)setShowTemperature:(BOOL)value {
    self.settingsStore.showTemperature = value;
}

- (BOOL)showRAM {
    return self.settingsStore.showRAM;
}

- (void)setShowRAM:(BOOL)value {
    self.settingsStore.showRAM = value;
}

- (BOOL)showDisk {
    return self.settingsStore.showDisk;
}

- (void)setShowDisk:(BOOL)value {
    self.settingsStore.showDisk = value;
}

- (NSString *)temperatureUnit {
    return self.settingsStore.temperatureUnit;
}

- (void)setTemperatureUnit:(NSString *)value {
    self.settingsStore.temperatureUnit = value;
}

- (NSTimeInterval)cpuRAMRefreshIntervalSeconds {
    return self.settingsStore.cpuRAMRefreshIntervalSeconds;
}

- (void)setCpuRAMRefreshIntervalSeconds:(NSTimeInterval)value {
    self.settingsStore.cpuRAMRefreshIntervalSeconds = value;
}

- (void)showSettings {
    if (!self.settingsWindow) {
        self.settingsWindow = [self makeSettingsWindow];
    }

    self.cachedLoginEnabled = self.loginItemManager.isEnabled;
    [self syncSettingsControls];
    [self.settingsWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSWindow *)makeSettingsWindow {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 360, 330)
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
    NSPopUpButton *cpuRAMRefreshPopup = [self makeCPURAMRefreshPopup];
    NSPopUpButton *temperatureUnitPopup = [self makeTemperatureUnitPopup];

    self.cpuCheckbox = cpu;
    self.ramCheckbox = ram;
    self.temperatureCheckbox = temperature;
    self.diskCheckbox = disk;
    self.loginCheckbox = login;
    self.cpuRAMRefreshPopup = cpuRAMRefreshPopup;
    self.temperatureUnitPopup = temperatureUnitPopup;

    [root addArrangedSubview:header];
    [root addArrangedSubview:[self makeSettingsRowWithLeft:[self makeMetricViewWithCheckbox:cpu unitPopup:nil]
                                                     right:[self makeMetricViewWithCheckbox:ram unitPopup:nil]]];
    [root addArrangedSubview:[self makeSettingsRowWithLeft:[self makeMetricViewWithCheckbox:temperature
                                                                                  unitPopup:temperatureUnitPopup]
                                                     right:[self makeMetricViewWithCheckbox:disk unitPopup:nil]]];
    [root addArrangedSubview:[self makeRefreshSettingsViewWithPopup:cpuRAMRefreshPopup]];
    [root addArrangedSubview:[self makeActionsViewWithLogin:login]];
    [contentView addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:18],
        [root.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-18],
        [root.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:18],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor constant:-18],
    ]];

    return window;
}

- (NSStackView *)makeMetricViewWithCheckbox:(NSButton *)checkbox
                                  unitPopup:(NSPopUpButton *)unitPopup {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack.widthAnchor constraintEqualToConstant:150].active = YES;

    [stack addArrangedSubview:checkbox];

    if (unitPopup) {
        NSTextField *unitLabel = [NSTextField labelWithString:@"Unit"];
        unitLabel.font = [NSFont systemFontOfSize:11];
        unitLabel.textColor = NSColor.secondaryLabelColor;
        [stack addArrangedSubview:unitLabel];
        [stack addArrangedSubview:unitPopup];
    }

    return stack;
}

- (NSStackView *)makeRefreshSettingsViewWithPopup:(NSPopUpButton *)popup {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack.widthAnchor constraintEqualToConstant:320].active = YES;

    NSTextField *label = [NSTextField labelWithString:@"CPU & RAM refresh"];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];

    NSTextField *help = [NSTextField wrappingLabelWithString:
        @"Temperature and disk update less often to save energy."];
    help.font = [NSFont systemFontOfSize:11];
    help.textColor = NSColor.secondaryLabelColor;
    help.maximumNumberOfLines = 2;

    [stack addArrangedSubview:label];
    [stack addArrangedSubview:popup];
    [stack addArrangedSubview:help];
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

    NSButton *resetButton = [NSButton buttonWithTitle:@"Reset Metrics" target:self action:@selector(resetMetrics)];
    NSButton *quitButton = [NSButton buttonWithTitle:@"Quit" target:self action:@selector(quit)];
    resetButton.bezelStyle = NSBezelStyleRounded;
    quitButton.bezelStyle = NSBezelStyleRounded;

    [stack addArrangedSubview:login];
    [buttonRow addArrangedSubview:resetButton];
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

- (NSPopUpButton *)makeCPURAMRefreshPopup {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.target = self;
    popup.action = @selector(cpuRAMRefreshIntervalChanged);
    [popup.widthAnchor constraintEqualToConstant:168].active = YES;

    NSArray<NSNumber *> *intervals = @[
        @(MPCPURAMRefreshIntervalFast),
        @(MPCPURAMRefreshIntervalDefault),
        @(MPCPURAMRefreshIntervalSlow),
    ];
    for (NSNumber *interval in intervals) {
        NSString *unit = interval.integerValue == 1 ? @"second" : @"seconds";
        [popup addItemWithTitle:[NSString stringWithFormat:@"Every %ld %@",
                                  (long)interval.integerValue,
                                  unit]];
        popup.lastItem.representedObject = interval;
    }

    [popup setAccessibilityLabel:@"CPU and RAM refresh interval"];
    [popup setAccessibilityHelp:@"Temperature and disk use slower fixed intervals."];
    return popup;
}

- (void)syncSettingsControls {
    self.cpuCheckbox.state = self.showCPU ? NSControlStateValueOn : NSControlStateValueOff;
    self.temperatureCheckbox.state = self.showTemperature ? NSControlStateValueOn : NSControlStateValueOff;
    self.ramCheckbox.state = self.showRAM ? NSControlStateValueOn : NSControlStateValueOff;
    self.diskCheckbox.state = self.showDisk ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginCheckbox.state = self.cachedLoginEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self selectCPURAMRefreshInterval:self.cpuRAMRefreshIntervalSeconds
                              inPopup:self.cpuRAMRefreshPopup];
    [self selectTemperatureUnit:self.temperatureUnit inPopup:self.temperatureUnitPopup];
    [self updateSettingsControlState];
}

- (void)settingsChanged {
    BOOL wasShowingCPU = self.showCPU;
    BOOL wasShowingRAM = self.showRAM;
    BOOL wasShowingTemperature = self.showTemperature;
    self.showCPU = self.cpuCheckbox.state == NSControlStateValueOn;
    self.showTemperature = self.temperatureCheckbox.state == NSControlStateValueOn;
    self.showRAM = self.ramCheckbox.state == NSControlStateValueOn;
    self.showDisk = self.diskCheckbox.state == NSControlStateValueOn;

    if (wasShowingCPU != self.showCPU) {
        [self.cpuMonitor reset];
        self.cachedCPU = nil;
    }
    if (wasShowingRAM && !self.showRAM) {
        self.cachedRAM = nil;
    }
    if (wasShowingTemperature && !self.showTemperature) {
        [self releaseTemperatureReaderIfDisabled];
    }
    if (!self.showDisk) {
        self.cachedDisk = nil;
        self.cachedDiskAvailableBytes = nil;
    }

    [self updateSettingsControlState];
    self.refreshScheduler.activeMetrics = [self activeRefreshMetrics];
    [self updateStatusImage];
}

- (void)temperatureUnitChanged {
    self.temperatureUnit = [self selectedTemperatureUnitFromPopup:self.temperatureUnitPopup];
    [self updateStatusImage];
}

- (void)cpuRAMRefreshIntervalChanged {
    NSNumber *selectedInterval = self.cpuRAMRefreshPopup.selectedItem.representedObject;
    self.cpuRAMRefreshIntervalSeconds = selectedInterval.doubleValue;
    self.refreshScheduler.cpuRAMRefreshIntervalSeconds = self.cpuRAMRefreshIntervalSeconds;
    [self updateStatusImage];
}

- (void)loginChanged {
    BOOL shouldEnable = self.loginCheckbox.state == NSControlStateValueOn;
    if (![self.loginItemManager setEnabled:shouldEnable]) {
        self.cachedLoginEnabled = self.loginItemManager.isEnabled;
        self.loginCheckbox.state = self.cachedLoginEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        if (shouldEnable && self.loginItemManager.requiresApproval) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Allow Menu Pulse at Login";
            alert.informativeText =
                @"macOS requires approval in System Settings before Menu Pulse can open automatically.";
            [alert addButtonWithTitle:@"Open Login Items"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] == NSAlertFirstButtonReturn) {
                [self.loginItemManager openSystemSettings];
            }
        } else {
            NSBeep();
        }
        return;
    }

    self.cachedLoginEnabled = self.loginItemManager.isEnabled;
    [self updateStatusImage];
}

- (void)resetMetrics {
    [self.refreshScheduler stop];
    [self.settingsStore resetMetricSettings];
    [self.cpuMonitor reset];
    self.cachedCPU = nil;
    self.cachedRAM = nil;
    self.cachedDisk = nil;
    self.cachedDiskAvailableBytes = nil;
    [self releaseTemperatureReaderIfDisabled];
    [self syncSettingsControls];
    self.refreshScheduler.cpuRAMRefreshIntervalSeconds = self.cpuRAMRefreshIntervalSeconds;
    self.refreshScheduler.activeMetrics = [self activeRefreshMetrics];
    [self.refreshScheduler invalidateLastSampleForMetrics:(MPRefreshMetricCPU | MPRefreshMetricRAM)];
    [self.refreshScheduler start];
    [self updateStatusImage];
}

- (void)quit {
    [self.refreshScheduler stop];
    [NSApp terminate:nil];
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

    self.temperatureRequestGeneration += 1;
    self.temperatureReadInFlight = NO;
    self.cachedTemperature = nil;
}

- (void)requestTemperatureRead {
    if (self.temperatureReadInFlight) {
        return;
    }

    self.temperatureReadInFlight = YES;
    NSUInteger generation = ++self.temperatureRequestGeneration;

    __weak typeof(self) weakSelf = self;
    [[self activeTemperatureReader] temperatureCelsiusAsync:^(NSNumber *temperatureCelsius) {
        MPMenuPulse *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (generation != strongSelf.temperatureRequestGeneration) {
            return;
        }

        strongSelf.temperatureReadInFlight = NO;
        if (!strongSelf.showTemperature) {
            strongSelf.cachedTemperature = nil;
            [strongSelf updateStatusImage];
            return;
        }

        strongSelf.cachedTemperature = temperatureCelsius;
        [strongSelf updateStatusImage];
    }];
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
    NSString *cpu = self.showCPU ? [NSString stringWithFormat:@"CPU:%@", [self formatPercent:self.cachedCPU]] : nil;
    NSString *ram = self.showRAM ? [NSString stringWithFormat:@"RAM:%@", [self formatPercent:self.cachedRAM]] : nil;
    NSString *temperature = self.showTemperature ?
        [NSString stringWithFormat:@"TEMP:%@", [self formatTemperature:self.cachedTemperature]] : nil;
    NSString *disk = self.showDisk ? [NSString stringWithFormat:@"DISK:%@", [self formatPercent:self.cachedDisk]] : nil;

    NSArray<NSString *> *leftColumn = [self compactValues:@[cpu ?: NSNull.null, ram ?: NSNull.null]];
    NSArray<NSString *> *rightColumn = [self compactValues:@[temperature ?: NSNull.null, disk ?: NSNull.null]];

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
        CGFloat y = count == 1 ?
            floor((image.size.height - [rows[index] sizeWithAttributes:attributes].height) / 2.0) :
            (index == 0 ? 10.5 : -0.5);
        [rows[index] drawAtPoint:NSMakePoint(0, y) withAttributes:attributes];
    }

    [image unlockFocus];
    image.template = YES;
    return image;
}

- (CGFloat)textWidth:(NSString *)value attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes {
    return [value sizeWithAttributes:attributes].width;
}

- (void)selectCPURAMRefreshInterval:(NSTimeInterval)interval
                            inPopup:(NSPopUpButton *)popup {
    for (NSMenuItem *item in popup.itemArray) {
        NSNumber *value = item.representedObject;
        if ([value isKindOfClass:[NSNumber class]] && fabs(value.doubleValue - interval) < 0.001) {
            [popup selectItem:item];
            return;
        }
    }

    [popup selectItemAtIndex:1];
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
    self.temperatureUnitPopup.enabled = self.showTemperature;
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
        NSString *temperature = self.temperatureReadInFlight && !self.cachedTemperature ?
            @"warming up" :
            [self formatTemperature:self.cachedTemperature];
        [lines addObject:[NSString stringWithFormat:@"TEMP (hottest sensor): %@ (every %@)",
                          temperature,
                          [self formatInterval:MPTemperatureRefreshInterval]]];
    }

    if (self.showDisk) {
        [lines addObject:[NSString stringWithFormat:@"Disk: %@, %@ (every %@)",
                          [self formatPercent:self.cachedDisk],
                          [self formatAvailableBytes:self.cachedDiskAvailableBytes],
                          [self formatInterval:MPDiskRefreshInterval]]];
    }

    if (!self.showCPU && !self.showRAM && !self.showTemperature && !self.showDisk) {
        [lines addObject:@"No metrics enabled"];
    }

    NSString *loginState = self.loginItemManager.requiresApproval ?
        @"Needs approval" :
        (self.cachedLoginEnabled ? @"On" : @"Off");
    [lines addObject:[NSString stringWithFormat:@"Open at login: %@", loginState]];
    [lines addObject:@"Click to open settings"];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)formatInterval:(NSTimeInterval)value {
    return [NSString stringWithFormat:@"%ds", (int)value];
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
        return @[values[0]];
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
