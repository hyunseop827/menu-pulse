#import <AppKit/AppKit.h>

#import "MenuPulse.h"
#import "Updater.h"

int main(void) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        // An updated copy waits for the old one to quit before adding its
        // menu bar item. The old copy quits once this one has created
        // NSApplication, so the wait must come after it.
        BOOL relaunchedAfterUpdate = MPWaitForReplacedProcess(NSProcessInfo.processInfo.arguments);
        BOOL loginItemMigrationEnabled =
            ![NSProcessInfo.processInfo.environment[@"MENU_PULSE_DISABLE_LOGIN_ITEM_MIGRATION"]
                isEqualToString:@"1"];
        MPMenuPulse *menuPulse = [[MPMenuPulse alloc]
            initWithLoginItemMigrationEnabled:loginItemMigrationEnabled];
        [menuPulse start];
        if (relaunchedAfterUpdate) {
            [menuPulse showSettingsAfterLaunch];
        }
        [application run];
    }

    return 0;
}
