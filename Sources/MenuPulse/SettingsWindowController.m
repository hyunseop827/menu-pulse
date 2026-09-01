#import "SettingsWindowController.h"

#import "SettingsStore.h"

@interface MPSettingsWindowController ()
@property(nonatomic, strong) MPSettingsStore *settingsStore;
@property(nonatomic, strong) NSButton *cpuCheckbox;
@property(nonatomic, strong) NSButton *temperatureCheckbox;
@property(nonatomic, strong) NSButton *ramCheckbox;
@property(nonatomic, strong) NSButton *diskCheckbox;
@property(nonatomic, strong) NSButton *loginCheckbox;
@property(nonatomic, strong) NSPopUpButton *cpuRAMRefreshPopup;
@property(nonatomic, strong) NSPopUpButton *temperatureRefreshPopup;
@property(nonatomic, strong) NSPopUpButton *diskRefreshPopup;
@property(nonatomic, strong) NSPopUpButton *temperatureUnitPopup;
@end

@implementation MPSettingsWindowController

- (instancetype)initWithSettingsStore:(MPSettingsStore *)settingsStore
                              delegate:(id<MPSettingsWindowControllerDelegate>)delegate {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 390, 420)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        _settingsStore = settingsStore;
        _delegate = delegate;
        _alertRunner = ^NSModalResponse(NSAlert *alert) {
            return [alert runModal];
        };
        [self configureWindow];
    }
    return self;
}

- (void)showSettingsWindow {
    [self syncControls];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)closeSettingsWindow {
    [self.window close];
}

- (void)configureWindow {
    self.window.title = @"Menu Pulse Settings";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    NSView *contentView = [[NSView alloc] init];
    self.window.contentView = contentView;

    NSStackView *root = [[NSStackView alloc] init];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 13;
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *header = [NSTextField labelWithString:@"Show in menu bar"];
    header.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];

    self.cpuCheckbox = [NSButton checkboxWithTitle:@"CPU usage"
                                             target:self
                                             action:@selector(metricsChanged:)];
    self.ramCheckbox = [NSButton checkboxWithTitle:@"RAM usage"
                                             target:self
                                             action:@selector(metricsChanged:)];
    self.temperatureCheckbox = [NSButton checkboxWithTitle:@"Temperature"
                                                     target:self
                                                     action:@selector(metricsChanged:)];
    self.diskCheckbox = [NSButton checkboxWithTitle:@"Disk usage"
                                              target:self
                                              action:@selector(metricsChanged:)];
    self.loginCheckbox = [NSButton checkboxWithTitle:@"Open at login"
                                               target:self
                                               action:@selector(loginChanged:)];

    self.temperatureUnitPopup = [self makeTemperatureUnitPopup];
    self.cpuRAMRefreshPopup = [self makeRefreshPopupWithIntervals:
        [MPSettingsStore supportedCPURAMRefreshIntervals]
                                                          action:@selector(refreshIntervalChanged:)];
    self.temperatureRefreshPopup = [self makeRefreshPopupWithIntervals:
        [MPSettingsStore supportedTemperatureRefreshIntervals]
                                                               action:@selector(refreshIntervalChanged:)];
    self.diskRefreshPopup = [self makeRefreshPopupWithIntervals:
        [MPSettingsStore supportedDiskRefreshIntervals]
                                                        action:@selector(refreshIntervalChanged:)];

    [self.cpuRAMRefreshPopup setAccessibilityLabel:@"CPU and RAM refresh interval"];
    [self.cpuRAMRefreshPopup setAccessibilityHelp:@"Choose how often CPU and RAM are updated."];
    [self.temperatureRefreshPopup setAccessibilityLabel:@"Temperature refresh interval"];
    [self.temperatureRefreshPopup setAccessibilityHelp:
        @"Choose how often the hottest temperature sensor is updated."];
    [self.diskRefreshPopup setAccessibilityLabel:@"Disk refresh interval"];
    [self.diskRefreshPopup setAccessibilityHelp:
        @"Choose how often usage of the home volume is updated."];

    [root addArrangedSubview:header];
    [root addArrangedSubview:[self makeSettingsRowWithLeft:
        [self makeMetricViewWithCheckbox:self.cpuCheckbox unitPopup:nil]
                                                       right:
        [self makeMetricViewWithCheckbox:self.ramCheckbox unitPopup:nil]]];
    [root addArrangedSubview:[self makeSettingsRowWithLeft:
        [self makeMetricViewWithCheckbox:self.temperatureCheckbox
                               unitPopup:self.temperatureUnitPopup]
                                                       right:
        [self makeMetricViewWithCheckbox:self.diskCheckbox unitPopup:nil]]];
    [root addArrangedSubview:[self makeRefreshViewWithTitle:@"CPU & RAM refresh"
                                                     popup:self.cpuRAMRefreshPopup]];
    [root addArrangedSubview:[self makeRefreshViewWithTitle:@"Temperature refresh"
                                                     popup:self.temperatureRefreshPopup]];
    [root addArrangedSubview:[self makeRefreshViewWithTitle:@"Disk refresh"
                                                     popup:self.diskRefreshPopup]];

    NSTextField *help = [NSTextField wrappingLabelWithString:
        @"Faster temperature updates may use more energy."];
    help.font = [NSFont systemFontOfSize:11];
    help.textColor = NSColor.secondaryLabelColor;
    help.maximumNumberOfLines = 2;
    [root addArrangedSubview:help];
    [root addArrangedSubview:[self makeActionsView]];

    [contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:18],
        [root.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-18],
        [root.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:18],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor constant:-18],
    ]];

    [self syncControls];
}

- (NSStackView *)makeMetricViewWithCheckbox:(NSButton *)checkbox
                                  unitPopup:(nullable NSPopUpButton *)unitPopup {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack.widthAnchor constraintEqualToConstant:165].active = YES;
    [stack addArrangedSubview:checkbox];

    NSPopUpButton *presentUnitPopup = unitPopup;
    if (presentUnitPopup) {
        NSTextField *label = [NSTextField labelWithString:@"Unit"];
        label.font = [NSFont systemFontOfSize:11];
        label.textColor = NSColor.secondaryLabelColor;
        [stack addArrangedSubview:label];
        [stack addArrangedSubview:presentUnitPopup];
    }
    return stack;
}

- (NSStackView *)makeSettingsRowWithLeft:(NSView *)left right:(NSView *)right {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeTop;
    row.spacing = 18;
    [row addArrangedSubview:left];
    [row addArrangedSubview:right];
    return row;
}

- (NSStackView *)makeRefreshViewWithTitle:(NSString *)title popup:(NSPopUpButton *)popup {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 5;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack.widthAnchor constraintEqualToConstant:354].active = YES;

    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    [stack addArrangedSubview:label];
    [stack addArrangedSubview:popup];
    return stack;
}

- (NSStackView *)makeActionsView {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 7;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [stack.widthAnchor constraintEqualToConstant:354].active = YES;

    NSStackView *buttonRow = [[NSStackView alloc] init];
    buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttonRow.alignment = NSLayoutAttributeCenterY;
    buttonRow.spacing = 8;

    NSButton *resetButton = [NSButton buttonWithTitle:@"Reset Defaults"
                                                target:self
                                                action:@selector(resetDefaultsPressed:)];
    NSButton *closeButton = [NSButton buttonWithTitle:@"Close"
                                                target:self
                                                action:@selector(closePressed:)];
    NSButton *quitButton = [NSButton buttonWithTitle:@"Quit"
                                               target:self
                                               action:@selector(quitPressed:)];
    resetButton.bezelStyle = NSBezelStyleRounded;
    closeButton.bezelStyle = NSBezelStyleRounded;
    quitButton.bezelStyle = NSBezelStyleRounded;

    [stack addArrangedSubview:self.loginCheckbox];
    [buttonRow addArrangedSubview:resetButton];
    [buttonRow addArrangedSubview:closeButton];
    [buttonRow addArrangedSubview:quitButton];
    [stack addArrangedSubview:buttonRow];
    return stack;
}

- (NSPopUpButton *)makeTemperatureUnitPopup {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.target = self;
    popup.action = @selector(temperatureUnitChanged:);
    [popup.widthAnchor constraintEqualToConstant:135].active = YES;
    [popup addItemWithTitle:@"Celsius (\u00B0C)"];
    popup.lastItem.representedObject = MPTemperatureUnitCelsius;
    [popup addItemWithTitle:@"Fahrenheit (\u00B0F)"];
    popup.lastItem.representedObject = MPTemperatureUnitFahrenheit;
    [popup setAccessibilityLabel:@"Temperature unit"];
    [popup setAccessibilityHelp:@"Choose Celsius or Fahrenheit for temperature."];
    return popup;
}

- (NSPopUpButton *)makeRefreshPopupWithIntervals:(NSArray<NSNumber *> *)intervals
                                           action:(SEL)action {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.target = self;
    popup.action = action;
    [popup.widthAnchor constraintEqualToConstant:180].active = YES;
    for (NSNumber *interval in intervals) {
        [popup addItemWithTitle:[self titleForInterval:interval.doubleValue]];
        popup.lastItem.representedObject = interval;
    }
    return popup;
}

- (NSString *)titleForInterval:(NSTimeInterval)interval {
    NSInteger seconds = (NSInteger)llround(interval);
    if (seconds >= 60 && seconds % 60 == 0) {
        NSInteger minutes = seconds / 60;
        return [NSString stringWithFormat:@"Every %ld minute%@",
                                          (long)minutes,
                                          minutes == 1 ? @"" : @"s"];
    }
    return [NSString stringWithFormat:@"Every %ld second%@",
                                      (long)seconds,
                                      seconds == 1 ? @"" : @"s"];
}

- (void)syncControls {
    self.cpuCheckbox.state = self.settingsStore.showCPU
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.ramCheckbox.state = self.settingsStore.showRAM
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.temperatureCheckbox.state = self.settingsStore.showTemperature
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.diskCheckbox.state = self.settingsStore.showDisk
        ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginCheckbox.state = self.loginEnabled
        ? NSControlStateValueOn : NSControlStateValueOff;
    [self selectValue:@(self.settingsStore.cpuRAMRefreshIntervalSeconds)
              inPopup:self.cpuRAMRefreshPopup];
    [self selectValue:@(self.settingsStore.temperatureRefreshIntervalSeconds)
              inPopup:self.temperatureRefreshPopup];
    [self selectValue:@(self.settingsStore.diskRefreshIntervalSeconds)
              inPopup:self.diskRefreshPopup];
    [self selectValue:self.settingsStore.temperatureUnit
              inPopup:self.temperatureUnitPopup];
    [self updateControlState];
}

- (void)setLoginEnabled:(BOOL)loginEnabled {
    _loginEnabled = loginEnabled;
    self.loginCheckbox.state = loginEnabled ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)selectValue:(id)value inPopup:(NSPopUpButton *)popup {
    for (NSMenuItem *item in popup.itemArray) {
        if ([item.representedObject isEqual:value]) {
            [popup selectItem:item];
            return;
        }
    }
}

- (void)updateControlState {
    self.cpuRAMRefreshPopup.enabled =
        self.settingsStore.showCPU || self.settingsStore.showRAM;
    self.temperatureUnitPopup.enabled = self.settingsStore.showTemperature;
    self.temperatureRefreshPopup.enabled = self.settingsStore.showTemperature;
    self.diskRefreshPopup.enabled = self.settingsStore.showDisk;
}

- (void)metricsChanged:(id)sender {
    (void)sender;
    self.settingsStore.showCPU = self.cpuCheckbox.state == NSControlStateValueOn;
    self.settingsStore.showRAM = self.ramCheckbox.state == NSControlStateValueOn;
    self.settingsStore.showTemperature =
        self.temperatureCheckbox.state == NSControlStateValueOn;
    self.settingsStore.showDisk = self.diskCheckbox.state == NSControlStateValueOn;
    [self updateControlState];
    [self.delegate settingsWindowControllerDidChangeMetrics:self];
}

- (void)temperatureUnitChanged:(id)sender {
    (void)sender;
    NSString *unit = self.temperatureUnitPopup.selectedItem.representedObject;
    self.settingsStore.temperatureUnit = unit;
    [self.delegate settingsWindowControllerDidChangeTemperatureUnit:self];
}

- (void)refreshIntervalChanged:(id)sender {
    NSPopUpButton *popup = sender;
    NSTimeInterval interval = [popup.selectedItem.representedObject doubleValue];
    if (popup == self.cpuRAMRefreshPopup) {
        self.settingsStore.cpuRAMRefreshIntervalSeconds = interval;
    } else if (popup == self.temperatureRefreshPopup) {
        self.settingsStore.temperatureRefreshIntervalSeconds = interval;
    } else if (popup == self.diskRefreshPopup) {
        self.settingsStore.diskRefreshIntervalSeconds = interval;
    }
    [self.delegate settingsWindowControllerDidChangeRefreshIntervals:self];
}

- (void)loginChanged:(id)sender {
    (void)sender;
    BOOL enabled = self.loginCheckbox.state == NSControlStateValueOn;
    [self.delegate settingsWindowController:self didRequestLoginEnabled:enabled];
}

- (void)closePressed:(id)sender {
    (void)sender;
    [self closeSettingsWindow];
}

- (void)quitPressed:(id)sender {
    (void)sender;
    NSAlert *alert = [self alertWithMessage:@"Quit Menu Pulse?"
                               informative:@"Menu bar monitoring will stop.\nOpen at login will remain enabled."
                                     action:@"Quit"
                                     cancel:@"Cancel"];
    if (self.alertRunner(alert) == NSAlertFirstButtonReturn) {
        [self.delegate settingsWindowControllerDidRequestQuit:self];
    }
}

- (void)resetDefaultsPressed:(id)sender {
    (void)sender;
    NSAlert *alert = [self alertWithMessage:@"Reset all settings?"
                               informative:@"CPU/RAM: On, every 3 seconds\nTemperature: Off, every 30 seconds\nDisk: Off, every 5 minutes\nTemperature unit: Celsius\nOpen at login: On"
                                     action:@"Reset"
                                     cancel:@"Cancel"];
    if (self.alertRunner(alert) == NSAlertFirstButtonReturn) {
        [self.delegate settingsWindowControllerDidRequestResetDefaults:self];
    }
}

- (BOOL)runOpenAtLoginPrompt {
    NSAlert *alert = [self alertWithMessage:@"Open Menu Pulse at Login?"
                               informative:@"Menu Pulse can start automatically after you sign in."
                                     action:@"Enable"
                                     cancel:@"Not Now"];
    return self.alertRunner(alert) == NSAlertFirstButtonReturn;
}

- (void)showLoginApprovalAlert {
    NSAlert *alert = [self alertWithMessage:@"Allow Menu Pulse at Login"
                               informative:@"macOS requires approval in System Settings before Menu Pulse can open automatically."
                                     action:@"Open Login Items"
                                     cancel:@"Cancel"];
    if (self.alertRunner(alert) == NSAlertFirstButtonReturn) {
        [self.delegate settingsWindowControllerDidRequestOpenLoginItems:self];
    }
}

- (NSAlert *)alertWithMessage:(NSString *)message
                  informative:(NSString *)informative
                        action:(NSString *)action
                        cancel:(NSString *)cancel {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = informative;
    NSButton *actionButton = [alert addButtonWithTitle:action];
    actionButton.keyEquivalent = @"\r";
    NSButton *cancelButton = [alert addButtonWithTitle:cancel];
    cancelButton.keyEquivalent = @"\e";
    return alert;
}

@end
