#import "Updater.h"

#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>
#import <errno.h>
#import <signal.h>
#import <unistd.h>

NSString * const MPRelaunchArgument = @"--relaunch-after-update";

static void *MPUpdaterStateContext = &MPUpdaterStateContext;
// Sparkle's KVO-compliant properties that decide whether a check can start.
static NSString * const MPCanCheckForUpdatesKey = @"canCheckForUpdates";
static NSString * const MPSessionInProgressKey = @"sessionInProgress";

BOOL MPUpdaterConfigurationCanStart(id feedURL, id publicKey) {
    if (![feedURL isKindOfClass:[NSString class]] || ![publicKey isKindOfClass:[NSString class]]) {
        return NO;
    }
    // Sparkle ignores white space around both values.
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    if ([(NSString *)feedURL stringByTrimmingCharactersInSet:whitespace].length == 0) {
        return NO;
    }
    NSData *key = [[NSData alloc]
        initWithBase64EncodedString:[(NSString *)publicKey stringByTrimmingCharactersInSet:whitespace]
                            options:0];
    return key.length == 32;
}

BOOL MPUpdateCheckAvailable(BOOL sparkleCanCheck, BOOL sessionInProgress, BOOL showingUpdate) {
    return sparkleCanCheck && (!sessionInProgress || showingUpdate);
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

@interface MPUpdater () <SPUStandardUserDriverDelegate>
@property(nonatomic, strong) SPUStandardUpdaterController *controller;
@property(nonatomic, readwrite) BOOL showingUpdate;
@property(nonatomic, readwrite, copy, nullable) NSString *pendingUpdateVersion;
@end

@implementation MPUpdater

- (instancetype)init {
    self = [super init];
    if (self) {
        _controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO
                                                                    updaterDelegate:nil
                                                                 userDriverDelegate:self];
        for (NSString *keyPath in @[MPCanCheckForUpdatesKey, MPSessionInProgressKey]) {
            [_controller.updater addObserver:self
                                  forKeyPath:keyPath
                                     options:0
                                     context:MPUpdaterStateContext];
        }
    }
    return self;
}

- (void)dealloc {
    for (NSString *keyPath in @[MPCanCheckForUpdatesKey, MPSessionInProgressKey]) {
        [_controller.updater removeObserver:self forKeyPath:keyPath context:MPUpdaterStateContext];
    }
}

- (void)start {
    NSBundle *bundle = NSBundle.mainBundle;
    if (!MPUpdaterConfigurationCanStart([bundle objectForInfoDictionaryKey:@"SUFeedURL"],
                                        [bundle objectForInfoDictionaryKey:@"SUPublicEDKey"])) {
        NSLog(@"Updates are off: Info.plist has no update feed or no EdDSA public key.");
        return;
    }
    // Started here rather than by the controller, which would show Sparkle's
    // alert at every launch about something the user cannot change.
    NSError *error = nil;
    if (![self.controller.updater startUpdater:&error]) {
        NSLog(@"The updater did not start: %@", error.localizedDescription);
    }
}

- (void)checkForUpdates {
    // Sparkle activates the app for user-initiated checks, and brings an
    // update window that is already open to the front.
    [self.controller checkForUpdates:nil];
}

- (BOOL)canCheckForUpdates {
    SPUUpdater *updater = self.controller.updater;
    return MPUpdateCheckAvailable(updater.canCheckForUpdates, updater.sessionInProgress,
                                  self.showingUpdate);
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (context != MPUpdaterStateContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [self notifyStateDidChange];
}

- (void)setShowingUpdate:(BOOL)showingUpdate {
    if (showingUpdate == _showingUpdate) {
        return;
    }
    _showingUpdate = showingUpdate;
    [self notifyStateDidChange];
}

- (void)setPendingUpdateVersion:(nullable NSString *)pendingUpdateVersion {
    if (pendingUpdateVersion == _pendingUpdateVersion ||
        [_pendingUpdateVersion isEqual:pendingUpdateVersion]) {
        return;
    }
    _pendingUpdateVersion = [pendingUpdateVersion copy];
    [self notifyStateDidChange];
}

- (void)notifyStateDidChange {
    void (^handler)(void) = self.stateDidChange;
    if (handler) {
        handler();
    }
}

#pragma mark - SPUStandardUserDriverDelegate

// Sparkle brings the update window to the front for checks the user starts
// and right after launch. A later scheduled check opens it behind other apps
// rather than taking focus while the user types, and its download and install
// windows never take focus. Menu Pulse has no Dock icon to reveal them, so the
// menu bar item mentions a new update and brings Sparkle's window forward.
- (BOOL)supportsGentleScheduledUpdateReminders {
    return YES;
}

- (void)standardUserDriverWillHandleShowingUpdate:(BOOL)handleShowingUpdate
                                        forUpdate:(SUAppcastItem *)update
                                            state:(SPUUserUpdateState *)state {
    (void)handleShowingUpdate;
    self.showingUpdate = YES;
    if (!state.userInitiated) {
        self.pendingUpdateVersion = update.displayVersionString;
    }
}

- (void)standardUserDriverDidReceiveUserAttentionForUpdate:(SUAppcastItem *)update {
    (void)update;
    self.pendingUpdateVersion = nil;
}

- (void)standardUserDriverWillFinishUpdateSession {
    self.showingUpdate = NO;
    self.pendingUpdateVersion = nil;
}

@end
