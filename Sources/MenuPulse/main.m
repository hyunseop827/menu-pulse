#import <AppKit/AppKit.h>

#import "LoginItemManager.h"
#import "MenuPulse.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2) {
            NSString *command = [NSString stringWithUTF8String:argv[1]];
            MPLoginItemManager *loginItemManager = [[MPLoginItemManager alloc] init];
            if ([command isEqualToString:@"--register-login-item"]) {
                return [loginItemManager setEnabled:YES] ? 0 : 1;
            }
            if ([command isEqualToString:@"--unregister-login-item"]) {
                return [loginItemManager setEnabled:NO] ? 0 : 1;
            }
        }

        NSApplication *application = [NSApplication sharedApplication];
        MPMenuPulse *menuPulse = [[MPMenuPulse alloc] init];
        [menuPulse start];
        [application run];
    }

    return 0;
}
