#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPLoginItemManager : NSObject
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly) BOOL requiresApproval;
- (BOOL)setEnabled:(BOOL)enabled;
- (void)openSystemSettings;
@end

NS_ASSUME_NONNULL_END
