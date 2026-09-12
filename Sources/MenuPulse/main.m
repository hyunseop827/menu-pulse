#import <AppKit/AppKit.h>

#import "MenuPulse.h"

int main(void) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        BOOL loginItemMigrationEnabled =
            ![NSProcessInfo.processInfo.environment[@"MENU_PULSE_DISABLE_LOGIN_ITEM_MIGRATION"]
                isEqualToString:@"1"];
        MPMenuPulse *menuPulse = [[MPMenuPulse alloc]
            initWithLoginItemMigrationEnabled:loginItemMigrationEnabled];
        [menuPulse start];
        [application run];
    }

    return 0;
}
