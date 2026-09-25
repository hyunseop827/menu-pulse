#import "LoginItemManager.h"

#import <ServiceManagement/ServiceManagement.h>
#import <unistd.h>

static NSString * const MPLegacyLoginItemLabel = @"dev.hyunseop.MenuPulse";

@interface MPLoginItemManager ()
@property(nonatomic, strong) dispatch_queue_t operationQueue;
@end

@implementation MPLoginItemManager

- (instancetype)initWithLegacyMigrationEnabled:(BOOL)legacyMigrationEnabled {
    self = [super init];
    if (self) {
        _operationQueue = dispatch_queue_create(
            "MenuPulse.login-item-manager",
            DISPATCH_QUEUE_SERIAL
        );
        if (legacyMigrationEnabled) {
            [self migrateLegacyLoginItemIfPossible];
        }
    }
    return self;
}

- (MPLoginItemStatus)status {
    switch (SMAppService.mainAppService.status) {
        case SMAppServiceStatusEnabled:
            return MPLoginItemStatusEnabled;
        case SMAppServiceStatusRequiresApproval:
            return MPLoginItemStatusRequiresApproval;
        default:
            return MPLoginItemStatusDisabled;
    }
}

- (void)setEnabled:(BOOL)enabled completion:(MPLoginItemUpdateCompletion)completion {
    MPLoginItemUpdateCompletion copiedCompletion = [completion copy];
    dispatch_async(self.operationQueue, ^{
        BOOL success = [self performSetEnabled:enabled];
        CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
        CFRunLoopPerformBlock(mainRunLoop, kCFRunLoopCommonModes, ^{
            copiedCompletion(success);
        });
        CFRunLoopWakeUp(mainRunLoop);
    });
}

- (BOOL)performSetEnabled:(BOOL)enabled {
    if (enabled) {
        SMAppService *service = SMAppService.mainAppService;
        if (service.status == SMAppServiceStatusEnabled) {
            [self removeLegacyLoginItem];
            return YES;
        }

        if (![service registerAndReturnError:NULL]) {
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

- (BOOL)performUnregisterModernLoginItem {
    SMAppService *service = SMAppService.mainAppService;
    if (service.status == SMAppServiceStatusNotRegistered) {
        return YES;
    }

    if (![service unregisterAndReturnError:NULL]) {
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
        [service registerAndReturnError:NULL];
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

    // Delete the plist first so an interrupted migration cannot leave the
    // legacy agent behind for the next login.
    if (![fileManager removeItemAtURL:legacyURL error:NULL]) {
        return NO;
    }

    // When the legacy agent launched this process, booting it out would
    // terminate Menu Pulse itself. Its definition is unloaded at logout, and
    // without the plist it does not return.
    NSString *serviceName = NSProcessInfo.processInfo.environment[@"XPC_SERVICE_NAME"];
    if ([serviceName isEqualToString:MPLegacyLoginItemLabel]) {
        return YES;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = @[
        @"bootout",
        [NSString stringWithFormat:@"gui/%d/%@", getuid(), MPLegacyLoginItemLabel],
    ];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if ([task launchAndReturnError:NULL]) {
        [task waitUntilExit];
    }
    return YES;
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
