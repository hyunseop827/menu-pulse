#import "Updater.h"

#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <errno.h>
#import <signal.h>
#import <unistd.h>

NSString * const MPRelaunchArgument = @"--relaunch-after-update";

static NSString * const MPLatestReleaseURLString =
    @"https://api.github.com/repos/hyunseop827/menu-pulse/releases/latest";
static NSString * const MPDownloadBaseURLString =
    @"https://github.com/hyunseop827/menu-pulse/releases/download/";
// `make dmg` publishes these next to the DMG on every release.
static NSString * const MPUpdateArchiveName = @"MenuPulse.zip";
static NSString * const MPUpdateChecksumsName = @"SHA256SUMS.txt";
static NSString * const MPUpdateAppName = @"Menu Pulse.app";
static const NSUInteger MPUpdateArchiveMaximumBytes = 64 * 1024 * 1024;

static NSError *MPUpdateError(NSString *description) {
    return [NSError errorWithDomain:@"MenuPulse.Updater"
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static BOOL MPFail(NSError **error, NSString *description) {
    if (error) {
        *error = MPUpdateError(description);
    }
    return NO;
}

static BOOL MPParseVersion(NSString *version, NSInteger components[3]) {
    NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
    if (parts.count != 3) {
        return NO;
    }
    NSCharacterSet *nonDigits =
        [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet;
    for (NSUInteger index = 0; index < 3; index += 1) {
        NSString *part = parts[index];
        if (part.length == 0 || part.length > 9 ||
            [part rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
            return NO;
        }
        components[index] = part.integerValue;
    }
    return YES;
}

NSComparisonResult MPCompareVersions(NSString *version, NSString *otherVersion) {
    NSInteger components[3] = {0};
    NSInteger otherComponents[3] = {0};
    BOOL valid = MPParseVersion(version, components);
    BOOL otherValid = MPParseVersion(otherVersion, otherComponents);
    if (!valid || !otherValid) {
        return valid == otherValid ? NSOrderedSame
            : (valid ? NSOrderedDescending : NSOrderedAscending);
    }
    for (NSUInteger index = 0; index < 3; index += 1) {
        if (components[index] != otherComponents[index]) {
            return components[index] < otherComponents[index]
                ? NSOrderedAscending : NSOrderedDescending;
        }
    }
    return NSOrderedSame;
}

NSString *MPVersionFromReleaseJSON(NSData *data) {
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id tag = ((NSDictionary *)object)[@"tag_name"];
    if (![tag isKindOfClass:[NSString class]] || ![tag hasPrefix:@"v"]) {
        return nil;
    }
    NSString *version = [(NSString *)tag substringFromIndex:1];
    NSInteger components[3] = {0};
    return MPParseVersion(version, components) ? version : nil;
}

NSString *MPChecksumForFile(NSString *checksums, NSString *fileName) {
    NSCharacterSet *nonHexDigits =
        [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet;
    for (NSString *line in [checksums componentsSeparatedByCharactersInSet:
                                NSCharacterSet.newlineCharacterSet]) {
        NSArray<NSString *> *fields = [[line componentsSeparatedByCharactersInSet:
                                           NSCharacterSet.whitespaceCharacterSet]
            filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        if (fields.count != 2) {
            continue;
        }
        // `shasum` marks files it read in binary mode with an asterisk.
        NSString *name = [fields[1] hasPrefix:@"*"] ? [fields[1] substringFromIndex:1] : fields[1];
        NSString *checksum = fields[0].lowercaseString;
        if ([name isEqualToString:fileName] && checksum.length == CC_SHA256_DIGEST_LENGTH * 2 &&
            [checksum rangeOfCharacterFromSet:nonHexDigits].location == NSNotFound) {
            return checksum;
        }
    }
    return nil;
}

BOOL MPWaitForReplacedProcess(NSArray<NSString *> *arguments) {
    NSUInteger index = [arguments indexOfObject:MPRelaunchArgument];
    if (index == NSNotFound || index + 1 >= arguments.count) {
        return NO;
    }
    // The old copy quits as soon as this one launches. The wait is capped so a
    // stuck process cannot keep Menu Pulse from starting.
    pid_t replacedProcess = (pid_t)arguments[index + 1].intValue;
    for (NSUInteger attempt = 0;
         replacedProcess > 1 && replacedProcess != getpid() && attempt < 100;
         attempt += 1) {
        if (kill(replacedProcess, 0) != 0 && errno == ESRCH) {
            break;
        }
        usleep(100000);
    }
    return YES;
}

static void MPPerformOnMainRunLoop(dispatch_block_t block) {
    // Results run from the main run loop rather than the main queue, so a modal
    // alert shown in response does not stall the main-queue refresh timer.
    CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(mainRunLoop, kCFRunLoopDefaultMode, block);
    CFRunLoopWakeUp(mainRunLoop);
}

static NSURLSession *MPMakeSession(void) {
    NSURLSessionConfiguration *configuration =
        NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = 30;
    configuration.timeoutIntervalForResource = 120;
    return [NSURLSession sessionWithConfiguration:configuration];
}

/// Runs on the updater queue, which may wait for the response.
static NSData *_Nullable MPFetchData(NSURLSession *session, NSURLRequest *request,
                                     NSError **error) {
    __block NSData *result = nil;
    __block NSError *failure = nil;
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *_Nullable data,
                                                                NSURLResponse *_Nullable response,
                                                                NSError *_Nullable taskError) {
        // File URLs, which the tests use, have no HTTP status.
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? ((NSHTTPURLResponse *)response).statusCode : 200;
        if (taskError) {
            failure = taskError;
        } else if (status == 403 || status == 429) {
            failure = MPUpdateError(@"GitHub is limiting requests right now. Try again later.");
        } else if (status != 200 || !data) {
            failure = MPUpdateError([NSString stringWithFormat:
                @"GitHub returned an unexpected response (HTTP %ld).", (long)status]);
        } else {
            result = data;
        }
        dispatch_semaphore_signal(finished);
    }];
    [task resume];
    dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);
    if (!result && error) {
        *error = failure;
    }
    return result;
}

static NSString *MPSHA256Hex(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index += 1) {
        [hex appendFormat:@"%02x", digest[index]];
    }
    return hex;
}

static BOOL MPRunTool(NSString *path, NSArray<NSString *> *arguments) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:NULL]) {
        return NO;
    }
    [task waitUntilExit];
    return task.terminationReason == NSTaskTerminationReasonExit && task.terminationStatus == 0;
}

/// Returns NO when this Mac's macOS is older than `minimumVersion`, or when the
/// value is malformed, since macOS would then refuse to open the update.
static BOOL MPSystemMeetsMinimumVersion(id minimumVersion) {
    if (!minimumVersion) {
        return YES;
    }
    if (![minimumVersion isKindOfClass:[NSString class]]) {
        return NO;
    }
    NSArray<NSString *> *parts = [(NSString *)minimumVersion componentsSeparatedByString:@"."];
    NSCharacterSet *nonDigits =
        [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet;
    NSInteger components[3] = {0};
    if (parts.count == 0 || parts.count > 3) {
        return NO;
    }
    for (NSUInteger index = 0; index < parts.count; index += 1) {
        if (parts[index].length == 0 || parts[index].length > 9 ||
            [parts[index] rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
            return NO;
        }
        components[index] = parts[index].integerValue;
    }
    NSOperatingSystemVersion version = {components[0], components[1], components[2]};
    return [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:version];
}

static BOOL MPCodeSignatureIsValid(NSURL *appURL) {
    SecStaticCodeRef code = NULL;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)appURL, kSecCSDefaultFlags, &code) !=
            errSecSuccess || !code) {
        return NO;
    }
    OSStatus status = SecStaticCodeCheckValidity(
        code, kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode, NULL);
    CFRelease(code);
    return status == errSecSuccess;
}

@interface MPUpdater ()
@property(nonatomic, copy) NSString *bundleIdentifier;
@property(nonatomic, strong) NSURL *latestReleaseURL;
@property(nonatomic, strong) NSURL *downloadBaseURL;
@property(nonatomic, strong) dispatch_queue_t queue;
@end

@implementation MPUpdater

- (instancetype)init {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *version = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    // Both URLs are valid constants.
    NSURL *latestReleaseURL = [NSURL URLWithString:MPLatestReleaseURLString];
    NSURL *downloadBaseURL = [NSURL URLWithString:MPDownloadBaseURLString];
    return [self initWithAppURL:bundle.bundleURL
               bundleIdentifier:bundle.bundleIdentifier ?: @""
                 currentVersion:[version isKindOfClass:[NSString class]] ? version : @""
               latestReleaseURL:latestReleaseURL
                downloadBaseURL:downloadBaseURL];
}

- (instancetype)initWithAppURL:(NSURL *)appURL
               bundleIdentifier:(NSString *)bundleIdentifier
                 currentVersion:(NSString *)currentVersion
               latestReleaseURL:(NSURL *)latestReleaseURL
                downloadBaseURL:(NSURL *)downloadBaseURL {
    self = [super init];
    if (self) {
        _appURL = appURL;
        _bundleIdentifier = [bundleIdentifier copy];
        _currentVersion = [currentVersion copy];
        _latestReleaseURL = latestReleaseURL;
        _downloadBaseURL = downloadBaseURL;
        _queue = dispatch_queue_create(
            "MenuPulse.updater",
            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                    QOS_CLASS_USER_INITIATED, 0));
    }
    return self;
}

- (BOOL)canReplaceApp {
    NSURL *folderURL = self.appURL.URLByDeletingLastPathComponent;
    NSString *folderPath = folderURL.path;
    NSString *appPath = self.appURL.path;
    NSNumber *readOnly = nil;
    [folderURL getResourceValue:&readOnly forKey:NSURLVolumeIsReadOnlyKey error:NULL];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    return [appPath.pathExtension isEqualToString:@"app"] && folderPath && !readOnly.boolValue &&
        [fileManager isWritableFileAtPath:folderPath] &&
        [fileManager isWritableFileAtPath:appPath];
}

- (void)fetchLatestVersion:(MPLatestVersionCompletion)completion {
    MPLatestVersionCompletion copiedCompletion = [completion copy];
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        NSString *version = [self latestVersionWithError:&error];
        MPPerformOnMainRunLoop(^{
            copiedCompletion(version, version ? nil : error);
        });
    });
}

- (nullable NSString *)latestVersionWithError:(NSError **)error {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.latestReleaseURL];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    NSURLSession *session = MPMakeSession();
    NSData *data = MPFetchData(session, request, error);
    [session finishTasksAndInvalidate];
    if (!data) {
        return nil;
    }
    NSString *version = MPVersionFromReleaseJSON(data);
    if (!version) {
        MPFail(error, @"The latest release on GitHub has an unexpected format.");
    }
    return version;
}

- (void)installVersion:(NSString *)version completion:(MPUpdateCompletion)completion {
    MPUpdateCompletion copiedCompletion = [completion copy];
    NSString *copiedVersion = [version copy];
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        BOOL installed = [self replaceAppWithVersion:copiedVersion error:&error];
        NSError *result = installed ? nil
            : (error ?: MPUpdateError(@"The update couldn't be installed."));
        MPPerformOnMainRunLoop(^{
            copiedCompletion(result);
        });
    });
}

- (BOOL)replaceAppWithVersion:(NSString *)version error:(NSError **)error {
    // A replacement directory on the app's volume lets the final swap be a rename.
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *workURL = [fileManager URLForDirectory:NSItemReplacementDirectory
                                         inDomain:NSUserDomainMask
                                appropriateForURL:self.appURL
                                           create:YES
                                            error:error];
    if (!workURL) {
        return NO;
    }
    BOOL replaced = [self replaceAppWithVersion:version workURL:workURL error:error];
    [fileManager removeItemAtURL:workURL error:NULL];
    return replaced;
}

- (BOOL)replaceAppWithVersion:(NSString *)version workURL:(NSURL *)workURL error:(NSError **)error {
    NSURL *releaseURL = [self.downloadBaseURL
        URLByAppendingPathComponent:[@"v" stringByAppendingString:version]
                        isDirectory:YES];
    NSURL *checksumsDownloadURL = [releaseURL URLByAppendingPathComponent:MPUpdateChecksumsName];
    NSURL *archiveDownloadURL = [releaseURL URLByAppendingPathComponent:MPUpdateArchiveName];
    NSURLSession *session = MPMakeSession();
    NSData *checksums = MPFetchData(
        session, [NSURLRequest requestWithURL:checksumsDownloadURL], error);
    NSData *archive = checksums ? MPFetchData(
        session, [NSURLRequest requestWithURL:archiveDownloadURL], error) : nil;
    [session finishTasksAndInvalidate];
    if (!checksums || !archive) {
        return NO;
    }

    NSString *checksumText = [[NSString alloc] initWithData:checksums
                                                   encoding:NSUTF8StringEncoding];
    NSString *expected = checksumText ? MPChecksumForFile(checksumText, MPUpdateArchiveName) : nil;
    if (archive.length > MPUpdateArchiveMaximumBytes || !expected ||
        ![expected isEqualToString:MPSHA256Hex(archive)]) {
        return MPFail(error, @"The download didn't match its published checksum.");
    }

    NSURL *archiveURL = [workURL URLByAppendingPathComponent:MPUpdateArchiveName];
    NSURL *extractedURL = [workURL URLByAppendingPathComponent:@"Extracted" isDirectory:YES];
    NSString *archivePath = archiveURL.path;
    NSString *extractedPath = extractedURL.path;
    if (![archive writeToURL:archiveURL options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    if (!archivePath || !extractedPath ||
        !MPRunTool(@"/usr/bin/ditto", @[@"-x", @"-k", archivePath, extractedPath])) {
        return MPFail(error, @"The download couldn't be unpacked.");
    }

    NSURL *newAppURL = [extractedURL URLByAppendingPathComponent:MPUpdateAppName
                                                     isDirectory:YES];
    NSURL *infoURL = [newAppURL URLByAppendingPathComponent:@"Contents/Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:infoURL error:NULL];
    if (![info[@"CFBundleIdentifier"] isEqual:self.bundleIdentifier] ||
        ![info[@"CFBundleShortVersionString"] isEqual:version]) {
        return MPFail(error, [NSString stringWithFormat:
            @"The download doesn't contain Menu Pulse %@.", version]);
    }
    if (!MPCodeSignatureIsValid(newAppURL)) {
        return MPFail(error, @"The downloaded app's code signature isn't valid.");
    }
    // The old copy is deleted by the swap, so never install one that cannot open.
    id minimumSystemVersion = info[@"LSMinimumSystemVersion"];
    if (!MPSystemMeetsMinimumVersion(minimumSystemVersion)) {
        return MPFail(error, [NSString stringWithFormat:
            @"Menu Pulse %@ requires macOS %@ or later.", version, minimumSystemVersion]);
    }

    return [NSFileManager.defaultManager replaceItemAtURL:self.appURL
                                            withItemAtURL:newAppURL
                                           backupItemName:nil
                                                  options:NSFileManagerItemReplacementUsingNewMetadataOnly
                                         resultingItemURL:NULL
                                                    error:error];
}

- (void)relaunch:(MPUpdateCompletion)completion {
    MPUpdateCompletion copiedCompletion = [completion copy];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    // The new copy waits for this one to quit before it adds its menu bar
    // item, so the item keeps its saved position.
    configuration.createsNewApplicationInstance = YES;
    configuration.arguments = @[
        MPRelaunchArgument,
        [NSString stringWithFormat:@"%d", getpid()],
    ];
    [NSWorkspace.sharedWorkspace openApplicationAtURL:self.appURL
                                        configuration:configuration
                                    completionHandler:^(NSRunningApplication *_Nullable app,
                                                        NSError *_Nullable error) {
        (void)app;
        MPPerformOnMainRunLoop(^{
            copiedCompletion(error);
        });
    }];
}

@end
