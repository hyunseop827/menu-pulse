#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPMemoryUserDefaults : NSUserDefaults
/// Returns only values written to this store, ignoring registered defaults.
- (nullable id)storedObjectForKey:(NSString *)defaultName;
@end

NS_ASSUME_NONNULL_END
