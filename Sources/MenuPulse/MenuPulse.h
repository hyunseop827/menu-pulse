#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPMenuPulse : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLoginItemMigrationEnabled:(BOOL)loginItemMigrationEnabled NS_DESIGNATED_INITIALIZER;
- (void)start;
/// Shows Settings once the app is running, so an update can show its new version.
- (void)showSettingsAfterLaunch;
@end

NS_ASSUME_NONNULL_END
