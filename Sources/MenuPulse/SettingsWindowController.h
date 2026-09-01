#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MPSettingsStore;
@class MPSettingsWindowController;

typedef NSModalResponse (^MPSettingsAlertRunner)(NSAlert *alert);

@protocol MPSettingsWindowControllerDelegate <NSObject>
- (void)settingsWindowControllerDidChangeMetrics:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidChangeTemperatureUnit:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidChangeRefreshIntervals:(MPSettingsWindowController *)controller;
- (void)settingsWindowController:(MPSettingsWindowController *)controller
      didRequestLoginEnabled:(BOOL)enabled;
- (void)settingsWindowControllerDidRequestOpenLoginItems:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidRequestResetDefaults:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidRequestQuit:(MPSettingsWindowController *)controller;
@end

@interface MPSettingsWindowController : NSWindowController

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithSettingsStore:(MPSettingsStore *)settingsStore
                              delegate:(id<MPSettingsWindowControllerDelegate>)delegate
    NS_DESIGNATED_INITIALIZER;

@property(nonatomic, weak) id<MPSettingsWindowControllerDelegate> delegate;
@property(nonatomic) BOOL loginEnabled;
@property(nonatomic, copy) MPSettingsAlertRunner alertRunner;

- (void)showSettingsWindow;
- (void)closeSettingsWindow;
- (void)syncControls;

/// Returns YES only when the user chooses Enable.
- (BOOL)runOpenAtLoginPrompt;
- (void)showLoginApprovalAlert;

@end

NS_ASSUME_NONNULL_END
