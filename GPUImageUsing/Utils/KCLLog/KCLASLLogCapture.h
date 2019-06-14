
#import "KCLASLLogger.h"

@protocol KCLLogger;

/**
 *  This class provides the ability to capture the ASL (Apple System Logs)
 */
@interface KCLASLLogCapture : NSObject

+ (void)start;
+ (void)stop;

+ (KCLLogLevel)captureLevel;
+ (void)setCaptureLevel:(KCLLogLevel)level;

@end
