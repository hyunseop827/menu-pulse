#import "TestAssert.h"
#import "Updater.h"

static NSString * const MPTestBundleIdentifier = @"dev.hyunseop.MenuPulse.UpdaterTests";

static BOOL MPRun(NSString *path, NSArray<NSString *> *arguments, NSURL *_Nullable directory) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    task.currentDirectoryURL = directory;
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![task launchAndReturnError:NULL]) {
        return NO;
    }
    [task waitUntilExit];
    return task.terminationReason == NSTaskTerminationReasonExit && task.terminationStatus == 0;
}

static void MPWaitUntil(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30.0];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                               beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

static NSData *MPData(NSString *text) {
    return [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
}

static NSString *MPAppVersion(NSString *appPath) {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
        [appPath stringByAppendingPathComponent:@"Contents/Info.plist"]];
    return info[@"CFBundleShortVersionString"] ?: @"";
}

/// Builds a signed app bundle like `make app`, with a system tool as its executable.
static NSString *MPMakeApp(NSString *folderPath, NSString *bundleIdentifier, NSString *version) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *appPath = [folderPath stringByAppendingPathComponent:@"Menu Pulse.app"];
    NSString *executableFolderPath = [appPath stringByAppendingPathComponent:@"Contents/MacOS"];
    [fileManager createDirectoryAtPath:executableFolderPath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];
    [fileManager copyItemAtPath:@"/usr/bin/true"
                         toPath:[executableFolderPath stringByAppendingPathComponent:@"MenuPulse"]
                          error:NULL];
    NSDictionary *info = @{
        @"CFBundleExecutable": @"MenuPulse",
        @"CFBundleIdentifier": bundleIdentifier,
        @"CFBundlePackageType": @"APPL",
        @"CFBundleShortVersionString": version,
        @"CFBundleVersion": version,
        @"LSMinimumSystemVersion": @"13.0",
    };
    [info writeToFile:[appPath stringByAppendingPathComponent:@"Contents/Info.plist"]
           atomically:YES];
    MPAssert(MPRun(@"/usr/bin/codesign", @[@"--force", @"--sign", @"-", appPath], nil),
             @"the test app should be signed ad hoc");
    return appPath;
}

/// Lays out release assets the way `make dmg` and the release workflow do.
static NSString *MPPublish(NSString *downloadsPath, NSString *version, NSString *appPath) {
    NSString *releasePath = [downloadsPath stringByAppendingPathComponent:
        [@"v" stringByAppendingString:version]];
    [NSFileManager.defaultManager createDirectoryAtPath:releasePath
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
    NSString *zipPath = [releasePath stringByAppendingPathComponent:@"MenuPulse.zip"];
    MPAssert(MPRun(@"/usr/bin/ditto", @[@"-c", @"-k", @"--keepParent", appPath, zipPath], nil),
             @"the test release should be zipped");
    // The DMG line comes first, as in real releases, so the parser must pick by name.
    NSString *script = [NSString stringWithFormat:
        @"{ printf '%@  MenuPulse.dmg\\n'; shasum -a 256 MenuPulse.zip; } > SHA256SUMS.txt",
        [@"" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0]];
    MPAssert(MPRun(@"/bin/sh", @[@"-c", script], [NSURL fileURLWithPath:releasePath]),
             @"the test release should list its checksums");
    return releasePath;
}

static void MPTestVersions(void) {
    MPAssert(MPCompareVersions(@"1.10.0", @"1.9.9") == NSOrderedDescending,
             @"versions should compare numerically, not as text");
    MPAssert(MPCompareVersions(@"1.6.0", @"1.6.0") == NSOrderedSame &&
             MPCompareVersions(@"1.6.0", @"1.6.1") == NSOrderedAscending &&
             MPCompareVersions(@"2.0.0", @"1.99.99") == NSOrderedDescending,
             @"major, minor, and patch should compare in order");
    MPAssert(MPCompareVersions(@"", @"0.0.0") == NSOrderedAscending &&
             MPCompareVersions(@"1.6", @"0.0.1") == NSOrderedAscending &&
             MPCompareVersions(@"1.6.0-beta", @"0.0.1") == NSOrderedAscending &&
             MPCompareVersions(@"1.6.0", @"1.x.0") == NSOrderedDescending &&
             MPCompareVersions(@"bad", @"worse") == NSOrderedSame,
             @"invalid versions should sort before every valid version");
}

static void MPTestReleaseJSON(void) {
    NSString *(^version)(NSString *) = ^NSString *(NSString *json) {
        return MPVersionFromReleaseJSON(MPData(json));
    };
    MPAssert([version(@"{\"tag_name\":\"v1.7.0\",\"draft\":false}") isEqualToString:@"1.7.0"],
             @"a vX.Y.Z tag should give its version");
    MPAssert(!version(@"{\"tag_name\":\"1.7.0\"}") && !version(@"{\"tag_name\":\"v1.7\"}") &&
             !version(@"{\"tag_name\":\"v1.7.0-beta\"}") && !version(@"{\"tag_name\":7}") &&
             !version(@"[\"v1.7.0\"]") && !version(@"not json"),
             @"other tags and responses should be rejected");
}

static void MPTestChecksums(void) {
    NSString *dmg = [@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    NSString *zip = [@"" stringByPaddingToLength:64 withString:@"B" startingAtIndex:0];
    NSString *sums = [NSString stringWithFormat:@"%@  MenuPulse.dmg\n%@ *MenuPulse.zip\n",
                                                dmg, zip];
    MPAssert([MPChecksumForFile(sums, @"MenuPulse.zip") isEqualToString:zip.lowercaseString],
             @"the checksum should be found by file name, including binary-mode lines");
    MPAssert([MPChecksumForFile(sums, @"MenuPulse.dmg") isEqualToString:dmg],
             @"each file should get its own checksum");
    MPAssert(!MPChecksumForFile(sums, @"Other.zip") &&
             !MPChecksumForFile(@"abc  MenuPulse.zip\n", @"MenuPulse.zip") &&
             !MPChecksumForFile([NSString stringWithFormat:@"%@  MenuPulse.zip\n",
                 [@"" stringByPaddingToLength:64 withString:@"g" startingAtIndex:0]],
                                @"MenuPulse.zip"),
             @"missing files and malformed checksums should be rejected");
}

static void MPTestRelaunchArguments(void) {
    MPAssert(!MPWaitForReplacedProcess(@[@"MenuPulse"]) &&
             !MPWaitForReplacedProcess(@[@"MenuPulse", MPRelaunchArgument]),
             @"a normal launch should not be treated as an update relaunch");

    NSTask *exited = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/true"]
                                                arguments:@[]
                                                    error:NULL
                                       terminationHandler:nil];
    [exited waitUntilExit];
    NSDate *start = [NSDate date];
    BOOL relaunched = MPWaitForReplacedProcess(@[
        @"MenuPulse", MPRelaunchArgument,
        [NSString stringWithFormat:@"%d", exited.processIdentifier],
    ]);
    MPAssert(relaunched && -start.timeIntervalSinceNow < 1.0,
             @"an update relaunch should not wait for a copy that already quit");
    start = [NSDate date];
    relaunched = MPWaitForReplacedProcess(@[
        MPRelaunchArgument, [NSString stringWithFormat:@"%d", getpid()],
    ]);
    MPAssert(relaunched && -start.timeIntervalSinceNow < 1.0,
             @"an update relaunch should never wait for itself");

    NSTask *quitting = [NSTask launchedTaskWithExecutableURL:
                                   [NSURL fileURLWithPath:@"/bin/sleep"]
                                                  arguments:@[@"0.5"]
                                                      error:NULL
                                         terminationHandler:nil];
    start = [NSDate date];
    relaunched = MPWaitForReplacedProcess(@[
        MPRelaunchArgument, [NSString stringWithFormat:@"%d", quitting.processIdentifier],
    ]);
    NSTimeInterval waited = -start.timeIntervalSinceNow;
    MPAssert(relaunched && !quitting.running && waited >= 0.4 && waited < 5.0,
             @"an update relaunch should wait until the replaced copy quits");
}

static void MPTestFetchLatestVersion(NSString *rootPath) {
    NSString *feedPath = [rootPath stringByAppendingPathComponent:@"latest.json"];
    MPUpdater *updater = [[MPUpdater alloc]
        initWithAppURL:[NSURL fileURLWithPath:[rootPath stringByAppendingPathComponent:@"Menu Pulse.app"]]
      bundleIdentifier:MPTestBundleIdentifier
        currentVersion:@"1.0.0"
      latestReleaseURL:[NSURL fileURLWithPath:feedPath]
       downloadBaseURL:[NSURL fileURLWithPath:rootPath isDirectory:YES]];

    __block BOOL finished = NO;
    __block NSString *latestVersion = nil;
    __block NSError *latestError = nil;
    void (^fetch)(void) = ^{
        finished = NO;
        [updater fetchLatestVersion:^(NSString *version, NSError *error) {
            latestVersion = version;
            latestError = error;
            finished = YES;
        }];
        MPWaitUntil(^BOOL { return finished; });
    };

    fetch();
    MPAssert(finished && !latestVersion && latestError,
             @"a missing release feed should report an error");

    [MPData(@"{\"tag_name\":\"v1.1.0\"}") writeToFile:feedPath atomically:YES];
    fetch();
    MPAssert([latestVersion isEqualToString:@"1.1.0"] && !latestError,
             @"the latest release tag should give the newest version");

    [MPData(@"{\"tag_name\":\"nightly\"}") writeToFile:feedPath atomically:YES];
    fetch();
    MPAssert(!latestVersion && [latestError.localizedDescription containsString:@"unexpected format"],
             @"an unexpected tag should be reported, not offered as an update");
}

static void MPTestInstall(NSString *rootPath) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *installedFolderPath = [rootPath stringByAppendingPathComponent:@"Applications"];
    NSString *downloadsPath = [rootPath stringByAppendingPathComponent:@"Downloads"];
    NSString *installedPath = MPMakeApp(installedFolderPath, MPTestBundleIdentifier, @"1.0.0");
    MPUpdater *updater = [[MPUpdater alloc]
        initWithAppURL:[NSURL fileURLWithPath:installedPath]
      bundleIdentifier:MPTestBundleIdentifier
        currentVersion:@"1.0.0"
      latestReleaseURL:[NSURL fileURLWithPath:[rootPath stringByAppendingPathComponent:@"latest.json"]]
       downloadBaseURL:[NSURL fileURLWithPath:downloadsPath isDirectory:YES]];
    MPAssert(updater.canReplaceApp, @"an app in a writable folder should be replaceable");

    NSError *(^install)(NSString *) = ^NSError *(NSString *version) {
        __block BOOL finished = NO;
        __block NSError *result = nil;
        [updater installVersion:version completion:^(NSError *error) {
            result = error;
            finished = YES;
        }];
        MPWaitUntil(^BOOL { return finished; });
        MPAssert(finished, @"the install should finish");
        return result;
    };

    NSError *error = install(@"1.1.0");
    MPAssert([error.domain isEqualToString:NSURLErrorDomain] &&
             [MPAppVersion(installedPath) isEqualToString:@"1.0.0"],
             @"a release without assets should fail and keep the installed app");

    MPPublish(downloadsPath, @"1.2.0",
              MPMakeApp([rootPath stringByAppendingPathComponent:@"Mislabeled"],
                        MPTestBundleIdentifier, @"1.1.0"));
    error = install(@"1.2.0");
    MPAssert([error.localizedDescription isEqualToString:
        @"The download doesn't contain Menu Pulse 1.2.0."] &&
             [MPAppVersion(installedPath) isEqualToString:@"1.0.0"],
             @"a release whose app has another version should be rejected");

    MPPublish(downloadsPath, @"1.3.0",
              MPMakeApp([rootPath stringByAppendingPathComponent:@"OtherApp"],
                        @"com.example.Other", @"1.3.0"));
    error = install(@"1.3.0");
    MPAssert([error.localizedDescription isEqualToString:
        @"The download doesn't contain Menu Pulse 1.3.0."] &&
             [MPAppVersion(installedPath) isEqualToString:@"1.0.0"],
             @"a release with another bundle identifier should be rejected");

    NSString *tamperedPath = MPMakeApp([rootPath stringByAppendingPathComponent:@"Tampered"],
                                       MPTestBundleIdentifier, @"1.4.0");
    NSString *tamperedInfoPath = [tamperedPath stringByAppendingPathComponent:@"Contents/Info.plist"];
    NSMutableDictionary *tamperedInfo =
        [[NSDictionary dictionaryWithContentsOfFile:tamperedInfoPath] mutableCopy];
    tamperedInfo[@"Changed"] = @YES;
    [tamperedInfo writeToFile:tamperedInfoPath atomically:YES];
    MPPublish(downloadsPath, @"1.4.0", tamperedPath);
    error = install(@"1.4.0");
    MPAssert([error.localizedDescription isEqualToString:
        @"The downloaded app's code signature isn't valid."] &&
             [MPAppVersion(installedPath) isEqualToString:@"1.0.0"],
             @"an app changed after signing should be rejected");

    NSString *releasePath = MPPublish(downloadsPath, @"1.5.0",
                                      MPMakeApp([rootPath stringByAppendingPathComponent:@"Corrupt"],
                                                MPTestBundleIdentifier, @"1.5.0"));
    NSString *zipPath = [releasePath stringByAppendingPathComponent:@"MenuPulse.zip"];
    NSMutableData *zip = [NSMutableData dataWithContentsOfFile:zipPath];
    [zip appendData:MPData(@"x")];
    [zip writeToFile:zipPath atomically:YES];
    error = install(@"1.5.0");
    MPAssert([error.localizedDescription isEqualToString:
        @"The download didn't match its published checksum."] &&
             [MPAppVersion(installedPath) isEqualToString:@"1.0.0"],
             @"a download that does not match its checksum should be rejected");

    NSString *futurePath = MPMakeApp([rootPath stringByAppendingPathComponent:@"Future"],
                                     MPTestBundleIdentifier, @"1.5.1");
    NSString *futureInfoPath = [futurePath stringByAppendingPathComponent:@"Contents/Info.plist"];
    NSMutableDictionary *futureInfo =
        [[NSDictionary dictionaryWithContentsOfFile:futureInfoPath] mutableCopy];
    futureInfo[@"LSMinimumSystemVersion"] = @"99.0";
    [futureInfo writeToFile:futureInfoPath atomically:YES];
    MPAssert(MPRun(@"/usr/bin/codesign", @[@"--force", @"--sign", @"-", futurePath], nil),
             @"the future test app should be signed after its Info.plist changes");
    MPPublish(downloadsPath, @"1.5.1", futurePath);
    error = install(@"1.5.1");
    MPAssert([error.localizedDescription isEqualToString:
        @"Menu Pulse 1.5.1 requires macOS 99.0 or later."] &&
             [MPAppVersion(installedPath) isEqualToString:@"1.0.0"],
             @"an update this Mac cannot open should not replace the working app");

    MPPublish(downloadsPath, @"1.6.0",
              MPMakeApp([rootPath stringByAppendingPathComponent:@"Valid"],
                        MPTestBundleIdentifier, @"1.6.0"));
    error = install(@"1.6.0");
    MPAssert(!error && [MPAppVersion(installedPath) isEqualToString:@"1.6.0"],
             @"a verified release should replace the installed app");
    MPAssert(MPRun(@"/usr/bin/codesign", @[@"--verify", @"--strict", installedPath], nil),
             @"the installed update should keep a valid signature");
    NSArray<NSString *> *installedItems =
        [fileManager contentsOfDirectoryAtPath:installedFolderPath error:NULL];
    MPAssert([installedItems isEqualToArray:@[@"Menu Pulse.app"]],
             @"the update should leave no backup or staging items next to the app");
}

static void MPTestReplaceableLocations(NSString *rootPath) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    MPUpdater *(^updaterForApp)(NSString *) = ^MPUpdater *(NSString *appPath) {
        NSURL *rootURL = [NSURL fileURLWithPath:rootPath isDirectory:YES];
        return [[MPUpdater alloc] initWithAppURL:[NSURL fileURLWithPath:appPath]
                                bundleIdentifier:MPTestBundleIdentifier
                                  currentVersion:@"1.0.0"
                                latestReleaseURL:rootURL
                                 downloadBaseURL:rootURL];
    };

    MPAssert(!updaterForApp([rootPath stringByAppendingPathComponent:@"Missing.app"]).canReplaceApp,
             @"a missing app should not be replaceable");
    NSString *executablePath = [rootPath stringByAppendingPathComponent:@"MenuPulse"];
    [[NSData data] writeToFile:executablePath atomically:YES];
    MPAssert(!updaterForApp(executablePath).canReplaceApp,
             @"a bare executable outside an app bundle should not be replaced");

    NSString *lockedFolderPath = [rootPath stringByAppendingPathComponent:@"Locked"];
    NSString *lockedAppPath = MPMakeApp(lockedFolderPath, MPTestBundleIdentifier, @"1.0.0");
    [fileManager setAttributes:@{NSFilePosixPermissions: @0555}
                  ofItemAtPath:lockedFolderPath
                         error:NULL];
    MPAssert(!updaterForApp(lockedAppPath).canReplaceApp,
             @"an app in a folder the user cannot write should not be replaceable");
    [fileManager setAttributes:@{NSFilePosixPermissions: @0755}
                  ofItemAtPath:lockedFolderPath
                         error:NULL];
}

int main(void) {
    @autoreleasepool {
        NSString *rootPath = [NSTemporaryDirectory()
            stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        [NSFileManager.defaultManager createDirectoryAtPath:rootPath
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:NULL];

        MPTestVersions();
        MPTestReleaseJSON();
        MPTestChecksums();
        MPTestRelaunchArguments();
        MPTestFetchLatestVersion(rootPath);
        MPTestInstall(rootPath);
        MPTestReplaceableLocations(rootPath);

        [NSFileManager.defaultManager removeItemAtPath:rootPath error:NULL];
        if (MPFailureCount != 0) {
            fprintf(stderr, "%lu updater test(s) failed\n", (unsigned long)MPFailureCount);
            return 1;
        }
        fprintf(stdout, "Updater tests passed\n");
    }
    return 0;
}
