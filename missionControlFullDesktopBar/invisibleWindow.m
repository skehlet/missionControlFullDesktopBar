#import <Cocoa/Cocoa.h>
#import <os/log.h>
#import "invisibleWindow.h"
#import "app.h"
#import "dragMethod.h"
#import "util.h"

static NSWindow *_invisibleWindow = nil;
static InvisibleView *_invisibleView = nil;

@interface NSWindow (Private)
- (void )_setPreventsActivation:(bool)preventsActivation;
@end

static void createSharedInvisibleWindowAndView(void)
{
    // The idea behind this window is that it's invisible and it cannot activate, but it
    // receives mouse clicks and clicking anywhere on it will trigger the start of a drag
    // operation. So all we need to do to make Mission Control use the full desktop bar is
    // have the window be in the process of dragging while Mission Control is invoked
    _invisibleWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0,
                                                                        kInvisibleWindowSize,
                                                                        kInvisibleWindowSize)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    _invisibleWindow.collectionBehavior = NSWindowCollectionBehaviorIgnoresCycle | NSWindowCollectionBehaviorTransient;
    [_invisibleWindow _setPreventsActivation:true];
    _invisibleWindow.ignoresMouseEvents = NO;
    [_invisibleWindow setBackgroundColor:[NSColor clearColor]];
    _invisibleWindow.opaque = NO;
    
    // In case we need to debug, uncomment this line to make the invisible window not invisible:
    //[_invisibleWindow setBackgroundColor:[NSColor colorWithRed:0.0 green:1.0 blue:1.0 alpha:0.5]];
    
    _invisibleView = [[InvisibleView alloc] initWithFrame:NSMakeRect(0, 0,
                                                                     _invisibleWindow.frame.size.width,
                                                                     _invisibleWindow.frame.size.height)];
    [_invisibleWindow setContentView:_invisibleView];
    [_invisibleView registerForDraggedTypes:@[NSPasteboardTypeString]];
}

bool sharedInvisibleWindowExists(void)
{
    return _invisibleWindow != nil;
}

NSWindow * sharedInvisibleWindow(void)
{
    if (!_invisibleWindow) {
        createSharedInvisibleWindowAndView();
    }
    
    return _invisibleWindow;
}

InvisibleView * sharedInvisibleView(void)
{
    if (!_invisibleView) {
        createSharedInvisibleWindowAndView();
    }
    
    return _invisibleView;
}

@implementation InvisibleView {
    bool startedDrag;
    bool receivedMouseDown;
    NSTimer *abortTimer;
    CFTimeInterval startTime;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self) {
        abortTimer = nil;
        receivedMouseDown = false;
        [self resetTracking];
    }
    
    return self;
}

- (void)mouseDown:(NSEvent *)event
{
    if (startedDrag) {
        return;
    }
    
    os_log(OS_LOG_DEFAULT, "[%ld] Received mouse down in invisible view\n", getCurrentTimeInMicrosecondsSinceLastCall());
    [self createAbortTimer];
    
    // Having received a mouse down event, we initiate a drag, as when a drag is in
    // progress, Mission Control always shows the full desktop bar. In this case we
    // are dragging an empty string of text, which should hopefully have no effect
    // on any other open apps.
    
    receivedMouseDown = true;
    startedDrag = true;
    NSString *stringData = @"";
    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:stringData];
    dragItem.draggingFrame = NSMakeRect(0, 0, 1, 1);
    NSDraggingSession *draggingSession = [self beginDraggingSessionWithItems:[NSArray arrayWithObject:dragItem]
                                                                       event:event source:self];
    
    if (!draggingSession) {
        NSLog(@"Failed to create dragging session");
        cleanUpAndFinish();
        return;
    }
    
    draggingSession.animatesToStartingPositionsOnCancelOrFail = NO;
    draggingSession.draggingFormation = NSDraggingFormationNone;
    
    os_log(OS_LOG_DEFAULT, "[%ld] mouseDown done, waiting for drag event\n", getCurrentTimeInMicrosecondsSinceLastCall());
    appMouseUp(); // this seems to fire the drag event quicker
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    os_log(OS_LOG_DEFAULT, "[%ld] Received drag event, invoking Mission Control...\n", getCurrentTimeInMicrosecondsSinceLastCall());
    // At this point we know the drag is successfully in progress, so we can invoke
    // Mission Control and immediately post an event to release the mouse button and
    // thus end the drag. With any luck, both the user and macOS should be none
    // the wiser.
    [self removeAbortTimer];
    toggleMissionControl();
    cleanUpAndFinish();
    
    return NSDragOperationNone;
}

- (void)resetTracking
{
    startedDrag = false;
    [self removeAbortTimer];
}

- (void)createAbortTimer
{
    [self removeAbortTimer];
    
    // We're giving ourselves a fraction of a second for the drag to occur on its own, otherwise
    // we give up and trigger a cleanup. Interestingly, this triggers the drag event.
    abortTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block:^(NSTimer *timer) {
        os_log(OS_LOG_DEFAULT, "Drag timer expired -- forcing clean up\n");
        cleanUpAndFinish();
        // If this happens, reset the receivedMouseDown flag, we might need another real mouse down
        self->receivedMouseDown = false;
    }];
}

- (void)removeAbortTimer
{
    if (abortTimer) {
        if (abortTimer.isValid) {
            [abortTimer invalidate];
        }
        
        abortTimer = nil;
    }
}

- (bool)hasReceivedAnyMouseDowns
{
    return receivedMouseDown;
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    return NSDragOperationNone;
}

@end
