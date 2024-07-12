#import <Cocoa/Cocoa.h>
#import "app.h"
#import "util.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (!accessibilityAvailable()) {
            NSLog(@"Cannot run without Accessibility");
            return 1;
        }

        if (argc == 1) {
            // parent
            if (signalDaemon()) {
                return 0;
            }
            forkDaemon(argc, argv);
            printf("[%d] Parent forked, exiting\n", getpid());
            exit(0);
            
        } else {
            // child, re-executed
            printf("[%d] Child in re-exec, becoming a daemon\n", getpid());
            NSApplicationLoad();
            setupDaemon();
            signalDaemon();
            int statusCode = NSApplicationMain(argc, argv); // never returns
            return statusCode;
        }
    }
}
