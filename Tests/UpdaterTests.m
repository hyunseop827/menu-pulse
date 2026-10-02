#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>

#import "TestAssert.h"
#import "Updater.h"

@interface MPUpdater (Testing) <SPUStandardUserDriverDelegate>
@property(nonatomic, strong) SPUStandardUpdaterController *controller;
- (void)setPendingUpdateVersion:(nullable NSString *)pendingUpdateVersion;
- (void)setShowingUpdate:(BOOL)showingUpdate;
@end

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

static void MPTestUpdaterBeforeStart(void) {
    MPUpdater *updater = [[MPUpdater alloc] init];
    MPAssert(!updater.controller.updater.sessionInProgress && !updater.canCheckForUpdates,
             @"creating the updater should not start Sparkle or a check");
    MPAssert([updater conformsToProtocol:@protocol(SPUStandardUserDriverDelegate)],
             @"the updater should receive Sparkle's user driver callbacks");
    MPAssert([updater supportsGentleScheduledUpdateReminders],
             @"a menu bar app should take part in scheduled update reminders");
}

static void MPTestUpdaterConfiguration(void) {
    NSString *feed = @"https://github.com/hyunseop827/menu-pulse/releases/latest/download/appcast.xml";
    // The public key of RFC 8032's first Ed25519 test vector: the right shape, nobody's secret.
    NSString *testKey = @"11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=";
    MPAssert(MPUpdaterConfigurationCanStart(feed, testKey) &&
             MPUpdaterConfigurationCanStart(feed, [NSString stringWithFormat:@" %@\n", testKey]),
             @"a feed and a 32-byte EdDSA key should start the updater");
    MPAssert(!MPUpdaterConfigurationCanStart(feed, @"PASTE_PUBLIC_KEY_FROM_generate_keys"),
             @"the placeholder key should keep the updater off");
    MPAssert(!MPUpdaterConfigurationCanStart(feed, @"AAAA") &&
             !MPUpdaterConfigurationCanStart(feed, @"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHg=="),
             @"a key that is not 32 bytes should keep the updater off");
    MPAssert(!MPUpdaterConfigurationCanStart(nil, testKey) && !MPUpdaterConfigurationCanStart(@" ", testKey) &&
             !MPUpdaterConfigurationCanStart(feed, nil) && !MPUpdaterConfigurationCanStart(feed, @42),
             @"a missing feed or key should keep the updater off");

    // This test binary's Info.plist has neither, so starting leaves Sparkle off without an alert.
    MPUpdater *updater = [[MPUpdater alloc] init];
    [updater start];
    MPAssert(!updater.canCheckForUpdates && !updater.controller.updater.sessionInProgress,
             @"an updater without a feed and key should stay off");
}

static void MPTestUpdateCheckAvailability(void) {
    MPAssert(!MPUpdateCheckAvailable(NO, NO, NO), @"Check for Updates waits until Sparkle starts");
    MPAssert(MPUpdateCheckAvailable(YES, NO, NO), @"an idle updater allows a check");
    MPAssert(!MPUpdateCheckAvailable(YES, YES, NO),
             @"a running check keeps the button disabled even though Sparkle says it can check");
    MPAssert(MPUpdateCheckAvailable(YES, YES, YES),
             @"while an update is on screen, a click brings it forward");
    MPAssert(!MPUpdateCheckAvailable(NO, YES, YES), @"Sparkle's own NO always wins");
}

static void MPTestUpdateReminder(void) {
    MPUpdater *updater = [[MPUpdater alloc] init];
    __block NSUInteger changes = 0;
    updater.stateDidChange = ^{
        changes += 1;
    };
    [updater setShowingUpdate:YES];
    [updater setPendingUpdateVersion:@"2.0.0"];
    [updater setPendingUpdateVersion:@"2.0.0"];
    MPAssert(updater.showingUpdate && [updater.pendingUpdateVersion isEqualToString:@"2.0.0"] &&
             changes == 2,
             @"a waiting update should be reported once");
    [updater standardUserDriverDidReceiveUserAttentionForUpdate:[SUAppcastItem emptyAppcastItem]];
    MPAssert(!updater.pendingUpdateVersion && updater.showingUpdate && changes == 3,
             @"the reminder should end once the user looks at the update, but not the session");
    [updater setPendingUpdateVersion:@"2.0.0"];
    [updater standardUserDriverWillFinishUpdateSession];
    MPAssert(!updater.pendingUpdateVersion && !updater.showingUpdate && changes == 6,
             @"everything should end when Sparkle closes the update session");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        MPTestRelaunchArguments();
        MPTestUpdaterBeforeStart();
        MPTestUpdaterConfiguration();
        MPTestUpdateCheckAvailability();
        MPTestUpdateReminder();
        if (MPFailureCount != 0) {
            fprintf(stderr, "%lu updater test(s) failed\n", (unsigned long)MPFailureCount);
            return 1;
        }
        fprintf(stdout, "Updater tests passed\n");
    }
    return 0;
}
