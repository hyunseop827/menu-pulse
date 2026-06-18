#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPLoginItemManager : NSObject
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
- (BOOL)setEnabled:(BOOL)enabled;
@end

NS_ASSUME_NONNULL_END
