#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MPLoginItemStatus) {
    MPLoginItemStatusDisabled,
    MPLoginItemStatusEnabled,
    MPLoginItemStatusRequiresApproval,
};

typedef void (^MPLoginItemUpdateCompletion)(BOOL success);

@interface MPLoginItemManager : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithLegacyMigrationEnabled:(BOOL)legacyMigrationEnabled NS_DESIGNATED_INITIALIZER;
/// Queries ServiceManagement once per read.
@property(nonatomic, readonly) MPLoginItemStatus status;
/// Serializes ServiceManagement updates off the caller's thread. Completion is
/// always delivered on the main thread from the run loop, not the main
/// dispatch queue, so a modal alert shown by the completion does not stall
/// main-queue timers.
- (void)setEnabled:(BOOL)enabled completion:(MPLoginItemUpdateCompletion)completion;
- (void)openSystemSettings;
@end

NS_ASSUME_NONNULL_END
