#import <Cocoa/Cocoa.h>
#import <unistd.h>
#import <os/log.h>
#import "CGSPrivate.h"
#import "events.h"
#import "app.h"
#import "invisibleWindow.h"
#import "util.h"

static bool mouseIsDown = false;
static bool appMouseIsDown = false;
static NSTimer *clickableWindowTimer = nil;

bool screenPositionContainsWindowOfThisApp(int x, int y)
{
    AXUIElementRef application, element;
    CFStringRef role;
    pid_t pid = getpid();
    
    application = AXUIElementCreateApplication(pid);
    
    if (!application) {
        return false;
    }
    
    // Because we're passing in a AXUIElementRef for this application
    // rather than the system-wide UI element, if the specified coordinates
    // contains a window of this app, then AXUIElementCopyElementAtPosition
    // will return an element reference that is a window or an element
    // contained within a window. Otherwise it will return an application
    // element.
    
    AXError error = AXUIElementCopyElementAtPosition(application, x, y, &element);
    
    if (error != kAXErrorSuccess || !element) {
        CFRelease(application);
        return false;
    }
    
    error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute, (CFTypeRef *)&role); 
    
    if (error != kAXErrorSuccess || !role) {
        CFRelease(application);
        CFRelease(element);
        return false;
    }
    
    bool isNotApplication = (CFStringCompare(role, kAXApplicationRole, 0) != kCFCompareEqualTo);
    CFRelease(role);
    CFRelease(application);
    CFRelease(element);
    
    return isNotApplication;
}

void removeClickableWindowTimer(void)
{
    if (clickableWindowTimer && [clickableWindowTimer isValid]) {
        [clickableWindowTimer invalidate];
        clickableWindowTimer = nil;
    }
}

void checkWindowClickable(CGPoint p, CFTimeInterval startTime)
{
    if (screenPositionContainsWindowOfThisApp(p.x, p.y)) {
        os_log(OS_LOG_DEFAULT, "Posting mouse event\n");
        removeClickableWindowTimer();
        
        // Now we click down on the window. The next step occurs when the window receives a mouseDown event
        postLeftMouseButtonEvent(kCGEventLeftMouseDown, p.x, p.y);
        mouseIsDown = true;
    }
    
    if ((CACurrentMediaTime() - startTime) > 0.5) {
        // A safeguard against the window never becoming visible
        os_log(OS_LOG_DEFAULT, "Error: Invisible window was never clickable... aborting!\n");
        removeClickableWindowTimer();
        cleanUpAndFinish();
    }

}

void positionInvisibleWindowUnderCursorAndOrderFront(CGPoint flippedP)
{    
    // First step: position our invisible, draggable window directly underneath of the cursor
    flippedP.y += kInvisibleWindowSize;
    [sharedInvisibleWindow() setFrameTopLeftPoint:NSMakePoint(flippedP.x - kInvisibleWindowSize/2,
                                                              flippedP.y - kInvisibleWindowSize/2)];
    [sharedInvisibleWindow() makeKeyAndOrderFront:NSApp];
}

void showMissionControlWithFullDesktopBarUsingDragMethod(void)
{
    if ([NSEvent pressedMouseButtons] & 0x01) {
        os_log(OS_LOG_DEFAULT, "Mouse is already pressed\n");
        toggleMissionControl();
        cleanUpAndFinish();
        return;
    }
    
    [sharedInvisibleView() resetTracking];
    
    CGPoint p = currentMouseLocation();
    CGPoint flippedP = currentUnflippedMouseLocation();
    positionInvisibleWindowUnderCursorAndOrderFront(flippedP);
    
    // Because we are in the realm of unholy hacks, for whatever reason sending
    // the window a mouse event directly doesn't trigger a drag event unless
    // the window has received at least one regular mouse event already.
    if ([sharedInvisibleView() hasReceivedAnyMouseDowns]) {
        os_log(OS_LOG_DEFAULT, "[%ld] Posting internal mouse event\n", getCurrentTimeInMicrosecondsSinceLastCall());
        postInternalMouseEvent(NSEventTypeLeftMouseDown, sharedInvisibleWindow());
        appMouseIsDown = true;
        
    } else {
        os_log(OS_LOG_DEFAULT, "[%ld] Waiting for window to be clickable\n", getCurrentTimeInMicrosecondsSinceLastCall());
        
        // This should hopefully ensure the window becomes visible and appears on top of everything:
        CGSSetWindowLevel(CGSMainConnectionID(),
                          (CGSWindowID)sharedInvisibleWindow().windowNumber, NSPopUpMenuWindowLevel);
        CGSOrderWindow(CGSMainConnectionID(),
                       (CGSWindowID)sharedInvisibleWindow().windowNumber,
                       kCGSOrderAbove, 0);
        
        removeClickableWindowTimer();
        CFTimeInterval startTime = CACurrentMediaTime();
        
        // Next step: wait until the window is properly under the cursor and can be clicked
        clickableWindowTimer = [NSTimer scheduledTimerWithTimeInterval:0.001 repeats:YES block:^(NSTimer *timer) {
            checkWindowClickable(p, startTime);
        }];
    }
}

void dragMethodCleanUp(void)
{
    removeClickableWindowTimer();
    
    if (mouseIsDown) {
        CGPoint p = currentMouseLocation();
        postLeftMouseButtonEvent(kCGEventLeftMouseUp, p.x, p.y);
        mouseIsDown = false;
    }
    
    if (appMouseIsDown) {
        postInternalMouseEvent(NSEventTypeLeftMouseUp, sharedInvisibleWindow());
        appMouseIsDown = false;
    }
    
    if (sharedInvisibleWindowExists()) {
        [sharedInvisibleWindow() orderOut:nil];
    }
}

void appMouseUp(void)
{
    os_log(OS_LOG_DEFAULT, "appMouseUp\n");
    if (appMouseIsDown) {
        postInternalMouseEvent(NSEventTypeLeftMouseUp, sharedInvisibleWindow());
        appMouseIsDown = false;
    }
}
