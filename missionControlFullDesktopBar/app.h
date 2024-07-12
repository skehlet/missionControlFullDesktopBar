#ifndef app_h
#define app_h

#import "commandLineArguments.h"

#define kMessageMissionControlTriggerPressed 1
#define kMessageMissionControlTriggerReleased 2

bool determineIfInMissionControl(bool *result);
void toggleMissionControl(void);
void handleMissionControl(void);
void cleanUpAndFinish(void);
bool signalDaemon(void);
void setupDaemon(void);
void forkDaemon(int argc, const char *argv[]);
void ensureAppStopsAfterDuration(double durationMS);
void removeAppStopTimer(void);

#endif /* app_h */
