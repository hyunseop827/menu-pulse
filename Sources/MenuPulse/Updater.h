#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Passed to the updated copy, followed by the process ID of the copy it replaces.
FOUNDATION_EXPORT NSString * const MPRelaunchArgument;

typedef void (^MPLatestVersionCompletion)(NSString *_Nullable version, NSError *_Nullable error);
typedef void (^MPUpdateCompletion)(NSError *_Nullable error);

/// Compares `major.minor.patch` versions; anything else sorts before every valid version.
FOUNDATION_EXPORT NSComparisonResult MPCompareVersions(NSString *version, NSString *otherVersion);
/// Returns the version of a GitHub release whose tag is `vX.Y.Z`.
FOUNDATION_EXPORT NSString *_Nullable MPVersionFromReleaseJSON(NSData *data);
/// Returns the lowercase SHA-256 that `shasum` output lists for `fileName`.
FOUNDATION_EXPORT NSString *_Nullable MPChecksumForFile(NSString *checksums, NSString *fileName);
/// Returns YES when the arguments come from an update relaunch, after waiting
/// briefly for the replaced copy to quit.
FOUNDATION_EXPORT BOOL MPWaitForReplacedProcess(NSArray<NSString *> *arguments);

/// Checks GitHub for the latest release and replaces the app with it.
@interface MPUpdater : NSObject

/// Uses the running app and the Menu Pulse releases on GitHub.
- (instancetype)init;
- (instancetype)initWithAppURL:(NSURL *)appURL
               bundleIdentifier:(NSString *)bundleIdentifier
                 currentVersion:(NSString *)currentVersion
               latestReleaseURL:(NSURL *)latestReleaseURL
                downloadBaseURL:(NSURL *)downloadBaseURL NS_DESIGNATED_INITIALIZER;

@property(nonatomic, readonly) NSURL *appURL;
@property(nonatomic, readonly, copy) NSString *currentVersion;
/// NO when the app runs from a read-only or unwritable location, such as the disk image.
@property(nonatomic, readonly) BOOL canReplaceApp;

/// Completes on the main run loop with the latest published version.
- (void)fetchLatestVersion:(MPLatestVersionCompletion)completion;
/// Downloads, verifies, and installs `version` in place of the app, then
/// completes on the main run loop.
- (void)installVersion:(NSString *)version completion:(MPUpdateCompletion)completion;
/// Opens the installed copy, which waits for this process to quit.
- (void)relaunch:(MPUpdateCompletion)completion;

@end

NS_ASSUME_NONNULL_END
