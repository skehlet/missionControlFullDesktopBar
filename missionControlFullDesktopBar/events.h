#ifndef events_h
#define events_h

#import <Cocoa/Cocoa.h>

void postLeftMouseButtonEvent(UInt32 eventType, short x, short y);
void postLeftMouseButtonEventWithUserData(UInt32 eventType, short x, short y, int64_t userData);
void postInternalMouseEvent(NSEventType type, NSWindow *window);
CGPoint currentMouseLocation(void);
CGPoint currentUnflippedMouseLocation(void);

#endif /* events_h */
