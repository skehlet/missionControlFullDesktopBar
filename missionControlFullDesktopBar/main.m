#import <Cocoa/Cocoa.h>
#import <os/log.h>
#import "app.h"
#import "util.h"

// To tail the logs:
// log stream --process missionControlFullDesktopBar

int g_argc;
char **g_argv;

int main(int argc, char *argv[])
{
    @autoreleasepool {
        if (!accessibilityAvailable()) {
            NSLog(@"Cannot run without Accessibility");
            return 1;
        }

        g_argc = argc;
        g_argv = argv;
        
        if (argc == 1) {
            // parent
            if (signalDaemon()) {
                return 0;
            }
            forkDaemon();
            os_log(OS_LOG_DEFAULT, "[%d] Parent forked, exiting\n", getpid());
            exit(0);
            
        } else {
            // child, re-executed
            os_log(OS_LOG_DEFAULT, "[%d] Child in re-exec, becoming a daemon\n", getpid());
            NSApplicationLoad();
            setupDaemon();
            signalDaemon();
            int statusCode = NSApplicationMain(argc, (const char**)argv); // never returns
            return statusCode;
        }
    }
}
