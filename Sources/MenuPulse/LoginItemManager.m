#import "LoginItemManager.h"

#import <unistd.h>

static NSString * const MPLoginItemLabel = @"dev.hyunseop.MenuPulse";

@interface MPLoginItemManager ()
@property(nonatomic, strong) NSFileManager *fileManager;
@end

@implementation MPLoginItemManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileManager = [NSFileManager defaultManager];
    }
    return self;
}

- (BOOL)isEnabled {
    NSString *executablePath = [NSBundle mainBundle].executablePath;
    NSData *data = [NSData dataWithContentsOfURL:[self launchAgentURL]];
    if (!executablePath || !data) {
        return NO;
    }

    NSError *error = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:0
                                                          format:nil
                                                           error:&error];
    if (error || ![plist isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSDictionary *dictionary = (NSDictionary *)plist;
    NSArray *arguments = dictionary[@"ProgramArguments"];
    return [dictionary[@"Label"] isEqualToString:MPLoginItemLabel] &&
        [arguments isKindOfClass:[NSArray class]] &&
        arguments.count > 0 &&
        [arguments.firstObject isEqualToString:executablePath];
}

- (BOOL)setEnabled:(BOOL)enabled {
    return enabled ? [self enable] : [self disable];
}

- (BOOL)enable {
    NSString *executablePath = [NSBundle mainBundle].executablePath;
    if (!executablePath) {
        return NO;
    }

    NSURL *launchAgentURL = [self launchAgentURL];
    NSError *error = nil;
    if (![self.fileManager createDirectoryAtURL:launchAgentURL.URLByDeletingLastPathComponent
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&error]) {
        return NO;
    }

    NSDictionary *plist = @{
        @"Label": MPLoginItemLabel,
        @"ProgramArguments": @[executablePath],
        @"RunAtLoad": @YES,
        @"KeepAlive": @NO,
        @"StandardOutPath": @"/tmp/MenuPulse.out.log",
        @"StandardErrorPath": @"/tmp/MenuPulse.err.log",
    };

    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:&error];
    if (!data) {
        return NO;
    }

    return [data writeToURL:launchAgentURL options:NSDataWritingAtomic error:&error];
}

- (BOOL)disable {
    [self runLaunchctlWithArguments:@[@"bootout", [self guiDomain], [self launchAgentURL].path]];

    NSError *error = nil;
    NSURL *launchAgentURL = [self launchAgentURL];
    if ([self.fileManager fileExistsAtPath:launchAgentURL.path]) {
        return [self.fileManager removeItemAtURL:launchAgentURL error:&error];
    }

    return YES;
}

- (NSURL *)launchAgentURL {
    return [[[[self.fileManager homeDirectoryForCurrentUser]
        URLByAppendingPathComponent:@"Library"]
        URLByAppendingPathComponent:@"LaunchAgents"]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", MPLoginItemLabel]];
}

- (NSString *)guiDomain {
    return [NSString stringWithFormat:@"gui/%d", getuid()];
}

- (BOOL)runLaunchctlWithArguments:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    task.arguments = arguments;
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        return NO;
    }

    [task waitUntilExit];
    return task.terminationStatus == 0;
}

@end
