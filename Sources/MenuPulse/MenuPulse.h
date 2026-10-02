#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPMenuPulse : NSObject
- (instancetype)init NS_UNAVAILABLE;
/// `updatesEnabled` NO keeps Sparkle from starting, for test and benchmark runs.
- (instancetype)initWithLoginItemMigrationEnabled:(BOOL)loginItemMigrationEnabled
                                    updatesEnabled:(BOOL)updatesEnabled NS_DESIGNATED_INITIALIZER;
- (void)start;
/// Shows Settings once the app is running, so an update can show its new version.
- (void)showSettingsAfterLaunch;
@end

NS_ASSUME_NONNULL_END
