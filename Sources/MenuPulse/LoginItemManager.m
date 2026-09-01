#import "LoginItemManager.h"

#import <ServiceManagement/ServiceManagement.h>
#import <unistd.h>

static NSString * const MPLegacyLoginItemLabel = @"dev.hyunseop.MenuPulse";

@interface MPLoginItemManager ()
@property(nonatomic, strong) dispatch_queue_t operationQueue;
- (BOOL)performSetEnabled:(BOOL)enabled;
- (BOOL)performUnregisterModernLoginItem;
- (BOOL)waitForModernLoginItemToBecomeUnregistered;
- (BOOL)isOnOperationQueue;
@end

@implementation MPLoginItemManager

static const void *MPLoginItemOperationQueueKey = &MPLoginItemOperationQueueKey;

- (instancetype)init {
    return [self initWithLegacyMigrationEnabled:YES];
}

- (instancetype)initWithLegacyMigrationEnabled:(BOOL)legacyMigrationEnabled {
    self = [super init];
    if (self) {
        _operationQueue = dispatch_queue_create(
            "MenuPulse.login-item-manager",
            DISPATCH_QUEUE_SERIAL
        );
        dispatch_queue_set_specific(
            _operationQueue,
            MPLoginItemOperationQueueKey,
            (__bridge void *)self,
            NULL
        );
        if (legacyMigrationEnabled) {
            [self migrateLegacyLoginItemIfPossible];
        }
    }
    return self;
}

- (BOOL)isEnabled {
    return SMAppService.mainAppService.status == SMAppServiceStatusEnabled;
}

- (BOOL)requiresApproval {
    return SMAppService.mainAppService.status == SMAppServiceStatusRequiresApproval;
}

- (BOOL)setEnabled:(BOOL)enabled {
    __block BOOL success = NO;
    void (^operation)(void) = ^{
        success = [self performSetEnabled:enabled];
    };
    if ([self isOnOperationQueue]) {
        operation();
    } else {
        dispatch_sync(self.operationQueue, operation);
    }
    return success;
}

- (void)setEnabled:(BOOL)enabled completion:(MPLoginItemUpdateCompletion)completion {
    MPLoginItemUpdateCompletion copiedCompletion = [completion copy];
    dispatch_async(self.operationQueue, ^{
        BOOL success = [self performSetEnabled:enabled];
        dispatch_async(dispatch_get_main_queue(), ^{
            copiedCompletion(success);
        });
    });
}

- (BOOL)performSetEnabled:(BOOL)enabled {
    if (enabled) {
        SMAppService *service = SMAppService.mainAppService;
        if (service.status == SMAppServiceStatusEnabled) {
            [self removeLegacyLoginItem];
            return YES;
        }

        NSError *error = nil;
        if (![service registerAndReturnError:&error]) {
            return NO;
        }

        BOOL didEnable = service.status == SMAppServiceStatusEnabled;
        if (didEnable) {
            [self removeLegacyLoginItem];
        }
        return didEnable;
    }

    if (![self performUnregisterModernLoginItem]) {
        return NO;
    }
    return [self removeLegacyLoginItem];
}

- (BOOL)unregisterModernLoginItem {
    __block BOOL success = NO;
    void (^operation)(void) = ^{
        success = [self performUnregisterModernLoginItem];
    };
    if ([self isOnOperationQueue]) {
        operation();
    } else {
        dispatch_sync(self.operationQueue, operation);
    }
    return success;
}

- (BOOL)performUnregisterModernLoginItem {
    SMAppService *service = SMAppService.mainAppService;
    if (service.status == SMAppServiceStatusNotRegistered) {
        return YES;
    }

    NSError *error = nil;
    if (![service unregisterAndReturnError:&error]) {
        return NO;
    }
    return [self waitForModernLoginItemToBecomeUnregistered];
}

- (BOOL)waitForModernLoginItemToBecomeUnregistered {
    static const NSUInteger maximumAttempts = 10;
    static const useconds_t delayMicroseconds = 50000;

    for (NSUInteger attempt = 0; attempt < maximumAttempts; attempt += 1) {
        if (SMAppService.mainAppService.status == SMAppServiceStatusNotRegistered) {
            return YES;
        }
        if (attempt + 1 < maximumAttempts) {
            usleep(delayMicroseconds);
        }
    }
    return NO;
}

- (BOOL)isOnOperationQueue {
    return dispatch_get_specific(MPLoginItemOperationQueueKey) == (__bridge void *)self;
}

- (void)openSystemSettings {
    [SMAppService openSystemSettingsLoginItems];
}

- (void)migrateLegacyLoginItemIfPossible {
    if (![self isStableInstallationLocation]) {
        return;
    }

    NSURL *legacyURL = [self legacyLoginItemURL];
    NSString *legacyPath = legacyURL.path;
    if (!legacyPath ||
        ![[NSFileManager defaultManager] fileExistsAtPath:legacyPath]) {
        return;
    }

    SMAppService *service = SMAppService.mainAppService;
    if (service.status == SMAppServiceStatusNotRegistered) {
        NSError *error = nil;
        [service registerAndReturnError:&error];
    }

    if (service.status == SMAppServiceStatusEnabled) {
        [self removeLegacyLoginItem];
    }
}

- (BOOL)isStableInstallationLocation {
    NSString *bundlePath = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    if (!bundlePath) {
        return NO;
    }

    NSString *userApplications = [[[[NSFileManager defaultManager] homeDirectoryForCurrentUser]
        URLByAppendingPathComponent:@"Applications"
                        isDirectory:YES].path stringByStandardizingPath];
    return [bundlePath hasPrefix:@"/Applications/"] ||
        (userApplications && [bundlePath hasPrefix:
            [userApplications stringByAppendingString:@"/"]]);
}

- (BOOL)removeLegacyLoginItem {
    NSURL *legacyURL = [self legacyLoginItemURL];
    NSString *legacyPath = legacyURL.path;
    if (!legacyPath) {
        return NO;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:legacyPath]) {
        return YES;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = @[
        @"bootout",
        [NSString stringWithFormat:@"gui/%d", getuid()],
        legacyPath,
    ];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        [task waitUntilExit];
    }

    return [fileManager removeItemAtURL:legacyURL error:&error];
}

- (NSURL *)legacyLoginItemURL {
    NSURL *libraryURL = [[[NSFileManager defaultManager] homeDirectoryForCurrentUser]
        URLByAppendingPathComponent:@"Library"
                        isDirectory:YES];
    NSURL *agentsURL = [libraryURL URLByAppendingPathComponent:@"LaunchAgents"
                                                   isDirectory:YES];
    return [agentsURL URLByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.plist", MPLegacyLoginItemLabel]];
}

@end
