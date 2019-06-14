

#import "KCLASLLogger.h"
#import <asl.h>

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

static KCLASLLogger *sharedInstance;

@interface KCLASLLogger () {
    aslclient _client;
}

@end


@implementation KCLASLLogger

+ (instancetype)sharedInstance {
    static dispatch_once_t KCLASLLoggerOnceToken;

    dispatch_once(&KCLASLLoggerOnceToken, ^{
        sharedInstance = [[[self class] alloc] init];
    });

    return sharedInstance;
}

- (instancetype)init {
    if (sharedInstance != nil) {
        return nil;
    }

    if ((self = [super init])) {
        _client = asl_open(NULL, "com.apple.console", 0);
    }

    return self;
}

- (void)logMessage:(KCLLogMessage *)logMessage {
    // Skip captured log messages
    if ([logMessage->_fileName isEqualToString:@"KCLASLLogCapture"]) {
        return;
    }

    NSString * message = _logFormatter ? [_logFormatter formatLogMessage:logMessage] : logMessage->_message;

    if (logMessage) {
        const char *msg = [message UTF8String];

        size_t aslLogLevel;
        switch (logMessage->_flag) {
            // Note: By default ASL will filter anything above level 5 (Notice).
            // So our mappings shouldn't go above that level.
            case KCLLogFlagError     : aslLogLevel = ASL_LEVEL_CRIT;     break;
            case KCLLogFlagWarning   : aslLogLevel = ASL_LEVEL_ERR;      break;
            case KCLLogFlagInfo      : aslLogLevel = ASL_LEVEL_WARNING;  break; // Regular NSLog's level
            case KCLLogFlagDebug     :
            case KCLLogFlagVerbose   :
            default                 : aslLogLevel = ASL_LEVEL_NOTICE;   break;
        }

        static char const *const level_strings[] = { "0", "1", "2", "3", "4", "5", "6", "7" };

        // NSLog uses the current euid to set the ASL_KEY_READ_UID.
        uid_t const readUID = geteuid();

        char readUIDString[16];
#ifndef NS_BLOCK_ASSERTIONS
        int l = snprintf(readUIDString, sizeof(readUIDString), "%d", readUID);
#else
        snprintf(readUIDString, sizeof(readUIDString), "%d", readUID);
#endif

        NSAssert(l < sizeof(readUIDString),
                 @"Formatted euid is too long.");
        NSAssert(aslLogLevel < (sizeof(level_strings) / sizeof(level_strings[0])),
                 @"Unhandled ASL log level.");

        aslmsg m = asl_new(ASL_TYPE_MSG);
        if (m != NULL) {
            if (asl_set(m, ASL_KEY_LEVEL, level_strings[aslLogLevel]) == 0 &&
                asl_set(m, ASL_KEY_MSG, msg) == 0 &&
                asl_set(m, ASL_KEY_READ_UID, readUIDString) == 0) {
                asl_send(_client, m);
            }
            asl_free(m);
        }
        //TODO handle asl_* failures non-silently?
    }
}

- (NSString *)loggerName {
    return @"cocoa.lumberjack.aslLogger";
}

@end
