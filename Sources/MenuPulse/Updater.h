#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Menu Pulse 1.7.0's own updater starts the copy it installs with this
/// argument, followed by the process ID of the copy it replaces.
FOUNDATION_EXPORT NSString * const MPRelaunchArgument;

/// Returns YES when the arguments come from that relaunch, after waiting
/// briefly for the replaced copy to quit.
FOUNDATION_EXPORT BOOL MPWaitForReplacedProcess(NSArray<NSString *> *arguments);

/// Whether Info.plist names a feed and an EdDSA public key (32 bytes in base64).
/// Sparkle refuses to start otherwise and shows an alert, so the updater stays
/// off instead, for example in a build with the placeholder key.
FOUNDATION_EXPORT BOOL MPUpdaterConfigurationCanStart(id _Nullable feedURL, id _Nullable publicKey);

/// Whether Check for Updates… is enabled. Sparkle's canCheckForUpdates turns
/// YES again as soon as a check starts, so a running check also disables the
/// button unless an update is on screen, where a click brings it forward.
FOUNDATION_EXPORT BOOL MPUpdateCheckAvailable(BOOL sparkleCanCheck, BOOL sessionInProgress,
                                              BOOL showingUpdate);

/// In-app updates through Sparkle: a daily check of the release feed, and
/// Check for Updates… in Settings.
@interface MPUpdater : NSObject

/// Creates Sparkle's updater without starting it.
- (instancetype)init;

/// Starts Sparkle's daily schedule when Info.plist allows it. Call once, after
/// the app has launched. A failure is logged and leaves updates off.
- (void)start;

/// Runs a user-initiated check, which shows Sparkle's windows.
- (void)checkForUpdates;

/// NO until Sparkle starts and while a check runs; YES while an update or its
/// progress is shown.
@property(nonatomic, readonly) BOOL canCheckForUpdates;

/// YES while Sparkle shows an update, from its window to installation.
/// Calling `checkForUpdates` then brings Sparkle's window to the front.
@property(nonatomic, readonly) BOOL showingUpdate;

/// The version a scheduled check found, until the user first looks at it.
@property(nonatomic, readonly, copy, nullable) NSString *pendingUpdateVersion;

/// Called on the main thread when `canCheckForUpdates`, `showingUpdate`, or
/// `pendingUpdateVersion` changes.
@property(nonatomic, copy, nullable) void (^stateDidChange)(void);

@end

NS_ASSUME_NONNULL_END
