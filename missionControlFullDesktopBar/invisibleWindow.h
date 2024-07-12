#ifndef invisibleWindow_h
#define invisibleWindow_h

#define kInvisibleWindowSize 50

@interface InvisibleView : NSView <NSDraggingSource>
- (void)resetTracking;
- (bool)hasReceivedAnyMouseDowns;
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context;
@end

NSWindow * sharedInvisibleWindow(void);
InvisibleView * sharedInvisibleView(void);
bool sharedInvisibleWindowExists(void);

#endif /* invisibleWindow_h */
