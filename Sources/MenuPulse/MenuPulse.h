#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPMenuPulse : NSObject
- (instancetype)initWithLoginItemMigrationEnabled:(BOOL)loginItemMigrationEnabled NS_DESIGNATED_INITIALIZER;
- (void)start;
@end

NS_ASSUME_NONNULL_END
