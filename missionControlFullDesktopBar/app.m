#import <Cocoa/Cocoa.h>
#import "app.h"
#import "dragMethod.h"
#import "util.h"
#import <os/log.h>

static CFMessagePortRef localPort = nil;
static CFRunLoopSourceRef localPortRunLoopSource = nil;
static bool isRunning = false;

extern int g_argc;
extern char **g_argv;

// Sets the memory result points to to true if Mission Control is up. Returns true if able to
// successfully determine the state of Mission Control, false if an error occurred.
bool determineIfInMissionControl(bool *result)
{
    (*result) = false;
    NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
    
    if (apps.count == 0) {
        NSLog(@"Error: Dock is not running!");
        return false;
    }
    
    NSRunningApplication *dock = apps[0];
    AXUIElementRef dockElement = AXUIElementCreateApplication(dock.processIdentifier);
    
    if (!dockElement) {
        NSLog(@"Error: cannot create AXUIElementRef for Dock");
        return false;
    }
    
    CFArrayRef children = NULL;
    AXError error = AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute, (const void **)&children);
    
    if (error != kAXErrorSuccess || !children) {
        NSLog(@"Error: cannot get Dock children UI elements");
        CFRelease(dockElement);
        return false;
    }
    
    for(int i = 0; i < CFArrayGetCount(children); ++i) {
        AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
        CFStringRef identifier;
        error = AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute, (CFTypeRef *)&identifier);
        
        if (error != kAXErrorSuccess || !identifier || CFGetTypeID(identifier) != CFStringGetTypeID()) {
            continue;
        }
        
        // We can tell if Mission Control is already up if the Dock has a UI element with
        // an AXIdentifier property of "mc". This is undocumented and therefore is liable
        // to change, but hopefully not anytime soon!
        if (CFStringCompare(identifier, CFSTR("mc"), 0) == kCFCompareEqualTo) {
            (*result) = true;
            break;
        }
    }
    
    CFRelease(children);
    CFRelease(dockElement);
    return true;
}

void toggleMissionControl(void)
{
    // Using some undocumented API's here!
    extern int CoreDockSendNotification(CFStringRef);
    CoreDockSendNotification(CFSTR("com.apple.expose.awake"));
}

/*
 Close Mission Control if it's open, otherwise open it.
*/
void handleMissionControl(void)
{
    bool alreadyInMissionControl = false;
    determineIfInMissionControl(&alreadyInMissionControl);
    if (alreadyInMissionControl) {
        os_log(OS_LOG_DEFAULT, "handleMissionControl: closing Mission Control\n");
        toggleMissionControl();
        cleanUpAndFinish();
    } else {
        os_log(OS_LOG_DEFAULT, "[%ld] handleMissionControl: firing drag event then opening Mission Control...\n", getCurrentTimeInMicrosecondsSinceLastCall());
        showMissionControlWithFullDesktopBarUsingDragMethod();
    }
}

void cleanUpAndFinish(void)
{
    os_log(OS_LOG_DEFAULT, "Cleaning up\n");
    dragMethodCleanUp();
    isRunning = false;
}

void giveUpAndReexec(void)
{
    os_log(OS_LOG_DEFAULT, "Giving up and reexecing\n");
    forkDaemon();
    exit(0);
}

bool signalDaemon(void)
{
    CFMessagePortRef remotePort = CFMessagePortCreateRemote(nil,
                                                            CFSTR("com.stevekehlet.missionControlFullDesktopBar"));
    
    if (!remotePort) {
        os_log(OS_LOG_DEFAULT, "Error communicating with daemon.\n");
        return false;
    }
    
    UInt8 junk = 1;
    CFTimeInterval timeout = 3.0;
    CFDataRef data = CFDataCreate(NULL, (UInt8 *)&junk, sizeof(&junk));
    SInt32 status = CFMessagePortSendRequest(remotePort, 0, data, timeout, timeout, nil, nil);
    
    if (status != kCFMessagePortSuccess) {
        NSLog(@"Failed to signal daemon");
    }
    
    CFRelease(data);
    CFRelease(remotePort);
    return true;
}

static CFDataRef receivedMessageAsDaemon(CFMessagePortRef port, SInt32 messageID, CFDataRef data, void *info)
{
    UInt8 junk;
    CFDataGetBytes(data, CFRangeMake(0, sizeof(&junk)), (UInt8 *)&junk);
    if (isRunning) {
        os_log(OS_LOG_DEFAULT, "Daemon: received signal, but ignoring because I'm already running\n");
        return NULL;
    }
    os_log(OS_LOG_DEFAULT, "Daemon: received signal, handling\n");
    isRunning = true;
    handleMissionControl();
    return NULL;
}

void quitDaemon(void)
{
    cleanUpAndFinish();
}

void setupDaemon(void)
{
    localPort = CFMessagePortCreateLocal(nil, CFSTR("com.stevekehlet.missionControlFullDesktopBar"),
                                         receivedMessageAsDaemon, nil, nil);
    CFRunLoopSourceRef localPortRunLoopSource = CFMessagePortCreateRunLoopSource(nil, localPort, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), localPortRunLoopSource, kCFRunLoopCommonModes);
    
    // Work around for issue where various notifications and event taps stop working after the current user switches
    // or the computer goes to sleep.
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceSessionDidResignActiveNotification
                                                                    object:nil
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *notification) { quitDaemon(); }];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceScreensDidSleepNotification
                                                                    object:nil
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *notification) { quitDaemon(); }];
}

void forkDaemon(void)
{
    pid_t pid = fork();
    if (pid > 0) {
        // parent
        return;
    }

    os_log(OS_LOG_DEFAULT, "[%d] Child reexecuting as daemon\n", getpid());
    const char *newArgs[g_argc+2];
    for(int i = 0; i < g_argc; ++i) {
        newArgs[i] = g_argv[i];
    }
    newArgs[g_argc] = "--daemonized";
    newArgs[g_argc+1] = NULL;
    execve(newArgs[0], (char * const *)newArgs, NULL);
}
