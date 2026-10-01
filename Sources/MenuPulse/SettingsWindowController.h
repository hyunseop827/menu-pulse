#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MPSettingsStore;
@class MPSettingsWindowController;

typedef NSModalResponse (^MPSettingsAlertRunner)(NSAlert *alert);
typedef BOOL (^MPSettingsURLOpener)(NSURL *url);

typedef NS_ENUM(NSInteger, MPUpdateActivity) {
    MPUpdateActivityIdle,
    MPUpdateActivityChecking,
    MPUpdateActivityInstalling,
};

@protocol MPSettingsWindowControllerDelegate <NSObject>
- (void)settingsWindowControllerDidChangeMetrics:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidChangeTemperatureUnit:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidChangeRefreshIntervals:(MPSettingsWindowController *)controller;
- (void)settingsWindowController:(MPSettingsWindowController *)controller
      didRequestLoginEnabled:(BOOL)enabled;
- (void)settingsWindowControllerDidRequestOpenLoginItems:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidRequestResetDefaults:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidRequestQuit:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidRequestUpdateCheck:(MPSettingsWindowController *)controller;
- (void)settingsWindowControllerDidCloseWindow:(MPSettingsWindowController *)controller;
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
/// Disables Check for Updates and shows progress in its title.
@property(nonatomic) MPUpdateActivity updateActivity;
@property(nonatomic, copy) MPSettingsAlertRunner alertRunner;
@property(nonatomic, copy) MPSettingsURLOpener urlOpener;

- (void)showSettingsWindow;
- (void)closeSettingsWindow;
- (void)syncControls;

/// Returns YES only when the user chooses Enable.
- (BOOL)runOpenAtLoginPrompt;
- (void)showLoginApprovalAlert;

- (void)showUpToDateAlertWithVersion:(NSString *)version;
/// Returns YES only when the user chooses Update.
- (BOOL)runUpdatePromptWithVersion:(NSString *)version currentVersion:(NSString *)currentVersion;
- (void)showManualUpdateAlertWithVersion:(NSString *)version;
- (void)showUpdateCheckFailedAlertWithError:(nullable NSError *)error;
- (void)showUpdateFailedAlertWithError:(NSError *)error version:(NSString *)version;
- (void)showRelaunchFailedAlertWithVersion:(NSString *)version;

@end

NS_ASSUME_NONNULL_END
