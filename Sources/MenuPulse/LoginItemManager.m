#import "LoginItemManager.h"

#import <ServiceManagement/ServiceManagement.h>
#import <unistd.h>

static NSString * const MPLegacyLoginItemLabel = @"dev.hyunseop.MenuPulse";

@implementation MPLoginItemManager

- (instancetype)init {
    self = [super init];
    if (self) {
        [self migrateLegacyLoginItemIfPossible];
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
    SMAppService *service = SMAppService.mainAppService;

    if (enabled) {
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

    if (service.status == SMAppServiceStatusNotRegistered) {
        return [self removeLegacyLoginItem];
    }

    NSError *error = nil;
    if (![service unregisterAndReturnError:&error]) {
        return NO;
    }

    BOOL didDisable = service.status != SMAppServiceStatusEnabled;
    return didDisable && [self removeLegacyLoginItem];
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
