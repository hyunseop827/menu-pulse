#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPLoginItemManager : NSObject
- (instancetype)initWithLegacyMigrationEnabled:(BOOL)legacyMigrationEnabled NS_DESIGNATED_INITIALIZER;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly) BOOL requiresApproval;
- (BOOL)setEnabled:(BOOL)enabled;
- (BOOL)unregisterModernLoginItem;
- (void)openSystemSettings;
@end

NS_ASSUME_NONNULL_END
