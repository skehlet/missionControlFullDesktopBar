#import <Cocoa/Cocoa.h>
#import <sys/time.h>

static long lastCall = 0;

bool accessibilityAvailable(void)
{
    return AXIsProcessTrustedWithOptions((CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @true});
}

long getCurrentTimeInMicroseconds(void)
{
    struct timeval now;
    gettimeofday(&now, NULL);
    long usecs = now.tv_sec * 1000000 + now.tv_usec;
    return usecs;
}

long getCurrentTimeInMilliseconds(void)
{
    return getCurrentTimeInMicroseconds() / 1000000;
}

long getCurrentTimeInMicrosecondsSinceLastCall(void)
{
    long now = getCurrentTimeInMicroseconds();
    long diff = now - lastCall;
    lastCall = now;
    return diff;
}
