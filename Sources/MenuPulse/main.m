#import <AppKit/AppKit.h>

#import "MenuPulse.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        MPMenuPulse *menuPulse = [[MPMenuPulse alloc] init];
        [menuPulse start];
        [application run];
    }

    return 0;
}
