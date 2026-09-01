#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MPLoginItemUpdateCompletion)(BOOL success);

@interface MPLoginItemManager : NSObject
- (instancetype)initWithLegacyMigrationEnabled:(BOOL)legacyMigrationEnabled NS_DESIGNATED_INITIALIZER;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly) BOOL requiresApproval;
/// Synchronous variant retained for command-line install and uninstall helpers.
- (BOOL)setEnabled:(BOOL)enabled;
/// Serializes ServiceManagement updates off the caller's thread. Completion is
/// always delivered on the main queue.
- (void)setEnabled:(BOOL)enabled completion:(MPLoginItemUpdateCompletion)completion;
- (BOOL)unregisterModernLoginItem;
- (void)openSystemSettings;
@end

NS_ASSUME_NONNULL_END
