#import <AppKit/AppKit.h>

#import "LoginItemManager.h"
#import "MenuPulse.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2) {
            NSString *command = [NSString stringWithUTF8String:argv[1]];
            if ([command isEqualToString:@"--register-login-item"]) {
                MPLoginItemManager *loginItemManager = [[MPLoginItemManager alloc]
                    initWithLegacyMigrationEnabled:NO];
                return [loginItemManager setEnabled:YES] ? 0 : 1;
            }
            if ([command isEqualToString:@"--unregister-login-item"]) {
                MPLoginItemManager *loginItemManager = [[MPLoginItemManager alloc]
                    initWithLegacyMigrationEnabled:NO];
                return [loginItemManager unregisterModernLoginItem] ? 0 : 1;
            }
        }

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
