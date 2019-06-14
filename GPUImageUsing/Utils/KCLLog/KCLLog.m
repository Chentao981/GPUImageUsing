
#ifndef KCL_LEGACY_MACROS
    #define KCL_LEGACY_MACROS 0
#endif

#import "KCLLog.h"

#import <pthread.h>
#import <objc/runtime.h>
#import <mach/mach_host.h>
#import <mach/host_info.h>
#import <libkern/OSAtomic.h>
#import <Availability.h>
#if TARGET_OS_IPHONE
    #import <UIKit/UIDevice.h>
#endif


#if !__has_feature(objc_arc)
#error This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#define KCL_DEBUG NO

#define NSLogDebug(frmt, ...) do{ if(KCL_DEBUG) NSLog((frmt), ##__VA_ARGS__); } while(0)

#define LOG_MAX_QUEUE_SIZE 1000

static void *const GlobalLoggingQueueIdentityKey = (void *)&GlobalLoggingQueueIdentityKey;

@interface KCLLoggerNode : NSObject
{
    // Direct accessors to be used only for performance
    @public
    id <KCLLogger> _logger;
    KCLLogLevel _level;
    dispatch_queue_t _loggerQueue;
}

@property (nonatomic, readonly) id <KCLLogger> logger;
@property (nonatomic, readonly) KCLLogLevel level;
@property (nonatomic, readonly) dispatch_queue_t loggerQueue;

+ (KCLLoggerNode *)nodeWithLogger:(id <KCLLogger>)logger
                     loggerQueue:(dispatch_queue_t)loggerQueue
                           level:(KCLLogLevel)level;

@end


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation KCLLog

// An array used to manage all the individual loggers.
// The array is only modified on the loggingQueue/loggingThread.
static NSMutableArray *_loggers;

// All logging statements are added to the same queue to ensure FIFO operation.
static dispatch_queue_t _loggingQueue;

// Individual loggers are executed concurrently per log statement.
// Each logger has it's own associated queue, and a dispatch group is used for synchrnoization.
static dispatch_group_t _loggingGroup;

// In order to prevent to queue from growing infinitely large,
// a maximum size is enforced (LOG_MAX_QUEUE_SIZE).
static dispatch_semaphore_t _queueSemaphore;

// Minor optimization for uniprocessor machines
static NSUInteger _numProcessors;

+ (void)initialize {
    static dispatch_once_t KCLLogOnceToken;

    dispatch_once(&KCLLogOnceToken, ^{
        _loggers = [[NSMutableArray alloc] initWithCapacity:4];

        NSLogDebug(@"KCLLog: Using grand central dispatch");

        _loggingQueue = dispatch_queue_create("cocoa.lumberjack", NULL);
        _loggingGroup = dispatch_group_create();

        void *nonNullValue = GlobalLoggingQueueIdentityKey; // Whatever, just not null
        dispatch_queue_set_specific(_loggingQueue, GlobalLoggingQueueIdentityKey, nonNullValue, NULL);

        _queueSemaphore = dispatch_semaphore_create(LOG_MAX_QUEUE_SIZE);

        // Figure out how many processors are available.
        // This may be used later for an optimization on uniprocessor machines.

        host_basic_info_data_t hostInfo;
        mach_msg_type_number_t infoCount;

        infoCount = HOST_BASIC_INFO_COUNT;
        host_info(mach_host_self(), HOST_BASIC_INFO, (host_info_t)&hostInfo, &infoCount);

        NSUInteger result = (NSUInteger)hostInfo.max_cpus;
        NSUInteger one    = (NSUInteger)1;

        _numProcessors = MAX(result, one);

        NSLogDebug(@"KCLLog: numProcessors = %@", @(_numProcessors));


#if TARGET_OS_IPHONE
        NSString *notificationName = @"UIApplicationWillTerminateNotification";
#else
        NSString *notificationName = nil;

        // On Command Line Tool apps AppKit may not be avaliable
#ifdef NSAppKitVersionNumber10_0

        if (NSApp) {
            notificationName = @"NSApplicationWillTerminateNotification";
        }

#endif

        if (!notificationName) {
            // If there is no NSApp -> we are running Command Line Tool app.
            // In this case terminate notification wouldn't be fired, so we use workaround.
            atexit_b (^{
                [self applicationWillTerminate:nil];
            });
        }

#endif /* if TARGET_OS_IPHONE */

        if (notificationName) {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(applicationWillTerminate:)
                                                         name:notificationName
                                                       object:nil];
        }
    });
}

/**
 * Provides access to the logging queue.
 **/
+ (dispatch_queue_t)loggingQueue {
    return _loggingQueue;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (void)applicationWillTerminate:(NSNotification *)notification {
    [self flushLog];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logger Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (void)addLogger:(id <KCLLogger>)logger {
    [self addLogger:logger withLevel:KCLLogLevelAll]; // KCLLogLevelAll has all bits set
}

+ (void)addLogger:(id <KCLLogger>)logger withLevel:(KCLLogLevel)level {
    if (!logger) {
        return;
    }

    dispatch_async(_loggingQueue, ^{ @autoreleasepool {
                                        [self lt_addLogger:logger level:level];
                                    } });
}

+ (void)removeLogger:(id <KCLLogger>)logger {
    if (!logger) {
        return;
    }

    dispatch_async(_loggingQueue, ^{ @autoreleasepool {
                                        [self lt_removeLogger:logger];
                                    } });
}

+ (void)removeAllLoggers {
    dispatch_async(_loggingQueue, ^{ @autoreleasepool {
                                        [self lt_removeAllLoggers];
                                    } });
}

+ (NSArray *)allLoggers {
    __block NSArray *theLoggers;

    dispatch_sync(_loggingQueue, ^{ @autoreleasepool {
                                       theLoggers = [self lt_allLoggers];
                                   } });

    return theLoggers;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Master Logging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (void)queueLogMessage:(KCLLogMessage *)logMessage asynchronously:(BOOL)asyncFlag {
    dispatch_semaphore_wait(_queueSemaphore, DISPATCH_TIME_FOREVER);

    dispatch_block_t logBlock = ^{
        @autoreleasepool {
            [self lt_log:logMessage];
        }
    };

    if (asyncFlag) {
        dispatch_async(_loggingQueue, logBlock);
    } else {
        dispatch_sync(_loggingQueue, logBlock);
    }
}

+ (void)log:(BOOL)asynchronous
      level:(KCLLogLevel)level
       flag:(KCLLogFlag)flag
    context:(NSInteger)context
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
        tag:(id)tag
     format:(NSString *)format, ... {
    va_list args;
    
    if (format) {
        va_start(args, format);
        
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        [self log:asynchronous
          message:message
            level:level
             flag:flag
          context:context
             file:file
         function:function
             line:line
              tag:tag];

        va_end(args);
    }
}

+ (void)log:(BOOL)asynchronous
      level:(KCLLogLevel)level
       flag:(KCLLogFlag)flag
    context:(NSInteger)context
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
        tag:(id)tag
     format:(NSString *)format
       args:(va_list)args {
    
    if (format) {
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        [self log:asynchronous
          message:message
            level:level
             flag:flag
          context:context
             file:file
         function:function
             line:line
              tag:tag];
    }
}

+ (void)log:(BOOL)asynchronous
    message:(NSString *)message
      level:(KCLLogLevel)level
       flag:(KCLLogFlag)flag
    context:(NSInteger)context
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
        tag:(id)tag {
    
    KCLLogMessage *logMessage = [[KCLLogMessage alloc] initWithMessage:message
                                                               level:level
                                                                flag:flag
                                                             context:context
                                                                file:[NSString stringWithFormat:@"%s", file]
                                                            function:[NSString stringWithFormat:@"%s", function]
                                                                line:line
                                                                 tag:tag
                                                             options:(KCLLogMessageOptions)0
                                                           timestamp:nil];
    
    [self queueLogMessage:logMessage asynchronously:asynchronous];
}

+ (void)log:(BOOL)asynchronous
    message:(KCLLogMessage *)logMessage {
    [self queueLogMessage:logMessage asynchronously:asynchronous];
}

+ (void)flushLog {
    dispatch_sync(_loggingQueue, ^{ @autoreleasepool {
                                       [self lt_flush];
                                   } });
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Registered Dynamic Logging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (BOOL)isRegisteredClass:(Class)class {
    SEL getterSel = @selector(ddLogLevel);
    SEL setterSel = @selector(ddSetLogLevel:);

#if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR
    
    BOOL result = NO;

    unsigned int methodCount, i;
    Method *methodList = class_copyMethodList(object_getClass(class), &methodCount);

    if (methodList != NULL) {
        BOOL getterFound = NO;
        BOOL setterFound = NO;

        for (i = 0; i < methodCount; ++i) {
            SEL currentSel = method_getName(methodList[i]);

            if (currentSel == getterSel) {
                getterFound = YES;
            } else if (currentSel == setterSel) {
                setterFound = YES;
            }

            if (getterFound && setterFound) {
                result = YES;
                break;
            }
        }

        free(methodList);
    }

    return result;

#else
    
    Method getter = class_getClassMethod(class, getterSel);
    Method setter = class_getClassMethod(class, setterSel);

    if ((getter != NULL) && (setter != NULL)) {
        return YES;
    }

    return NO;

#endif /* if TARGET_OS_IPHONE && !TARGET_IPHONE_SIMULATOR */
}

+ (NSArray *)registeredClasses {
    NSUInteger numClasses = 0;
    Class *classes = NULL;

    while (numClasses == 0) {

        numClasses = (NSUInteger)MAX(objc_getClassList(NULL, 0), 0);

        // numClasses now tells us how many classes we have (but it might change)
        // So we can allocate our buffer, and get pointers to all the class definitions.

        NSUInteger bufferSize = numClasses;

        classes = numClasses ? (Class *)malloc(sizeof(Class) * bufferSize) : NULL;
        if (classes == NULL) {
            return nil; //no memory or classes?
        }

        numClasses = (NSUInteger)MAX(objc_getClassList(classes, (int)bufferSize),0);

        if (numClasses > bufferSize || numClasses == 0) {
            //apparently more classes added between calls (or a problem); try again
            free(classes);
            numClasses = 0;
        }
    }

    // We can now loop through the classes, and test each one to see if it is a KCLLogging class.

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:numClasses];

    for (NSUInteger i = 0; i < numClasses; i++) {
        Class class = classes[i];

        if ([self isRegisteredClass:class]) {
            [result addObject:class];
        }
    }

    free(classes);

    return result;
}

+ (NSArray *)registeredClassNames {
    NSArray *registeredClasses = [self registeredClasses];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[registeredClasses count]];

    for (Class class in registeredClasses) {
        [result addObject:NSStringFromClass(class)];
    }
    return result;
}

+ (KCLLogLevel)levelForClass:(Class)aClass {
    if ([self isRegisteredClass:aClass]) {
        return [aClass ddLogLevel];
    }
    return (KCLLogLevel)-1;
}

+ (KCLLogLevel)levelForClassWithName:(NSString *)aClassName {
    Class aClass = NSClassFromString(aClassName);

    return [self levelForClass:aClass];
}

+ (void)setLevel:(KCLLogLevel)level forClass:(Class)aClass {
    if ([self isRegisteredClass:aClass]) {
        [aClass ddSetLogLevel:level];
    }
}

+ (void)setLevel:(KCLLogLevel)level forClassWithName:(NSString *)aClassName {
    Class aClass = NSClassFromString(aClassName);
    [self setLevel:level forClass:aClass];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logging Thread
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (void)lt_addLogger:(id <KCLLogger>)logger level:(KCLLogLevel)level {
    // Add to loggers array.
    // Need to create loggerQueue if loggerNode doesn't provide one.

    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");

    dispatch_queue_t loggerQueue = NULL;

    if ([logger respondsToSelector:@selector(loggerQueue)]) {
        // Logger may be providing its own queue

        loggerQueue = [logger loggerQueue];
    }

    if (loggerQueue == nil) {
        // Automatically create queue for the logger.
        // Use the logger name as the queue name if possible.

        const char *loggerQueueName = NULL;

        if ([logger respondsToSelector:@selector(loggerName)]) {
            loggerQueueName = [[logger loggerName] UTF8String];
        }

        loggerQueue = dispatch_queue_create(loggerQueueName, NULL);
    }

    KCLLoggerNode *loggerNode = [KCLLoggerNode nodeWithLogger:logger loggerQueue:loggerQueue level:level];
    [_loggers addObject:loggerNode];

    if ([logger respondsToSelector:@selector(didAddLogger)]) {
        dispatch_async(loggerNode->_loggerQueue, ^{ @autoreleasepool {
            [logger didAddLogger];
        } });
    }
}

+ (void)lt_removeLogger:(id <KCLLogger>)logger {
    // Find associated loggerNode in list of added loggers

    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");

    KCLLoggerNode *loggerNode = nil;

    for (KCLLoggerNode *node in _loggers) {
        if (node->_logger == logger) {
            loggerNode = node;
            break;
        }
    }
    
    if (loggerNode == nil) {
        NSLogDebug(@"KCLLog: Request to remove logger which wasn't added");
        return;
    }
    
    // Notify logger
    if ([logger respondsToSelector:@selector(willRemoveLogger)]) {
        dispatch_async(loggerNode->_loggerQueue, ^{ @autoreleasepool {
            [logger willRemoveLogger];
        } });
    }
    
    // Remove from loggers array
    [_loggers removeObject:loggerNode];
}

+ (void)lt_removeAllLoggers {
    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");
    
    // Notify all loggers
    for (KCLLoggerNode *loggerNode in _loggers) {
        if ([loggerNode->_logger respondsToSelector:@selector(willRemoveLogger)]) {
            dispatch_async(loggerNode->_loggerQueue, ^{ @autoreleasepool {
                [loggerNode->_logger willRemoveLogger];
            } });
        }
    }
    
    // Remove all loggers from array

    [_loggers removeAllObjects];
}

+ (NSArray *)lt_allLoggers {
    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");

    NSMutableArray *theLoggers = [NSMutableArray new];

    for (KCLLoggerNode *loggerNode in _loggers) {
        [theLoggers addObject:loggerNode->_logger];
    }

    return [theLoggers copy];
}

+ (void)lt_log:(KCLLogMessage *)logMessage {
    // Execute the given log message on each of our loggers.

    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");

    if (_numProcessors > 1) {
        for (KCLLoggerNode *loggerNode in _loggers) {
            // skip the loggers that shouldn't write this message based on the log level

            if (!(logMessage->_flag & loggerNode->_level)) {
                continue;
            }
            
            dispatch_group_async(_loggingGroup, loggerNode->_loggerQueue, ^{ @autoreleasepool {
                [loggerNode->_logger logMessage:logMessage];
            } });
        }
        
        dispatch_group_wait(_loggingGroup, DISPATCH_TIME_FOREVER);
    } else {
        // Execute each logger serialy, each within its own queue.
        
        for (KCLLoggerNode *loggerNode in _loggers) {
            // skip the loggers that shouldn't write this message based on the log level

            if (!(logMessage->_flag & loggerNode->_level)) {
                continue;
            }
            
            dispatch_sync(loggerNode->_loggerQueue, ^{ @autoreleasepool {
                [loggerNode->_logger logMessage:logMessage];
            } });
        }
    }
    
    dispatch_semaphore_signal(_queueSemaphore);
}

+ (void)lt_flush {
    NSAssert(dispatch_get_specific(GlobalLoggingQueueIdentityKey),
             @"This method should only be run on the logging thread/queue");
    
    for (KCLLoggerNode *loggerNode in _loggers) {
        if ([loggerNode->_logger respondsToSelector:@selector(flush)]) {
            dispatch_group_async(_loggingGroup, loggerNode->_loggerQueue, ^{ @autoreleasepool {
                [loggerNode->_logger flush];
            } });
        }
    }
    
    dispatch_group_wait(_loggingGroup, DISPATCH_TIME_FOREVER);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

NSString * KCLExtractFileNameWithoutExtension(const char *filePath, BOOL copy) {
    if (filePath == NULL) {
        return nil;
    }

    char *lastSlash = NULL;
    char *lastDot = NULL;

    char *p = (char *)filePath;

    while (*p != '\0') {
        if (*p == '/') {
            lastSlash = p;
        } else if (*p == '.') {
            lastDot = p;
        }

        p++;
    }

    char *subStr;
    NSUInteger subLen;

    if (lastSlash) {
        if (lastDot) {
            // lastSlash -> lastDot
            subStr = lastSlash + 1;
            subLen = (NSUInteger)(lastDot - subStr);
        } else {
            // lastSlash -> endOfString
            subStr = lastSlash + 1;
            subLen = (NSUInteger)(p - subStr);
        }
    } else {
        if (lastDot) {
            // startOfString -> lastDot
            subStr = (char *)filePath;
            subLen = (NSUInteger)(lastDot - subStr);
        } else {
            // startOfString -> endOfString
            subStr = (char *)filePath;
            subLen = (NSUInteger)(p - subStr);
        }
    }

    if (copy) {
        return [[NSString alloc] initWithBytes:subStr
                                        length:subLen
                                      encoding:NSUTF8StringEncoding];
    } else {
        return [[NSString alloc] initWithBytesNoCopy:subStr
                                              length:subLen
                                            encoding:NSUTF8StringEncoding
                                        freeWhenDone:NO];
    }
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation KCLLoggerNode

- (instancetype)initWithLogger:(id <KCLLogger>)logger loggerQueue:(dispatch_queue_t)loggerQueue level:(KCLLogLevel)level {
    if ((self = [super init])) {
        _logger = logger;

        if (loggerQueue) {
            _loggerQueue = loggerQueue;
            #if !OS_OBJECT_USE_OBJC
            dispatch_retain(loggerQueue);
            #endif
        }

        _level = level;
    }
    return self;
}

+ (KCLLoggerNode *)nodeWithLogger:(id <KCLLogger>)logger loggerQueue:(dispatch_queue_t)loggerQueue level:(KCLLogLevel)level {
    return [[KCLLoggerNode alloc] initWithLogger:logger loggerQueue:loggerQueue level:level];
}

- (void)dealloc {
    #if !OS_OBJECT_USE_OBJC
    if (_loggerQueue) {
        dispatch_release(_loggerQueue);
    }
    #endif
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation KCLLogMessage

#if TARGET_OS_IPHONE

// Compiling for iOS

    #define USE_DISPATCH_CURRENT_QUEUE_LABEL ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0)
    #define USE_DISPATCH_GET_CURRENT_QUEUE   ([[[UIDevice currentDevice] systemVersion] floatValue] >= 6.1)

#else

// Compiling for Mac OS X

  #ifndef MAC_OS_X_VERSION_10_9
    #define MAC_OS_X_VERSION_10_9            1090
  #endif

  #if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_9 // Mac OS X 10.9 or later required

    #define USE_DISPATCH_CURRENT_QUEUE_LABEL YES
    #define USE_DISPATCH_GET_CURRENT_QUEUE   NO

  #else

    #define USE_DISPATCH_CURRENT_QUEUE_LABEL ([NSTimer instancesRespondToSelector : @selector(tolerance)]) // OS X 10.9+
    #define USE_DISPATCH_GET_CURRENT_QUEUE   (![NSTimer instancesRespondToSelector : @selector(tolerance)]) // < OS X 10.9

  #endif

#endif /* if TARGET_OS_IPHONE */

- (instancetype)initWithMessage:(NSString *)message
                          level:(KCLLogLevel)level
                           flag:(KCLLogFlag)flag
                        context:(NSInteger)context
                           file:(NSString *)file
                       function:(NSString *)function
                           line:(NSUInteger)line
                            tag:(id)tag
                        options:(KCLLogMessageOptions)options
                      timestamp:(NSDate *)timestamp {
    if ((self = [super init])) {
        _message      = [message copy];
        _level        = level;
        _flag         = flag;
        _context      = context;
        _file         = file;
        _function     = function;
        _line         = line;
        _tag          = tag;
        _options      = options;
        _timestamp    = timestamp ?: [NSDate new];
        
        _threadID     = [[NSString alloc] initWithFormat:@"%x", pthread_mach_thread_np(pthread_self())];
        _threadName   = NSThread.currentThread.name;

        // Get the file name without extension
        _fileName = [_file lastPathComponent];
        NSUInteger dotLocation = [_fileName rangeOfString:@"." options:NSBackwardsSearch].location;
        if (dotLocation != NSNotFound)
        {
            _fileName = [_fileName substringToIndex:dotLocation];
        }
        
        // Try to get the current queue's label
        if (USE_DISPATCH_CURRENT_QUEUE_LABEL) {
            _queueLabel = [[NSString alloc] initWithFormat:@"%s", dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)];
        } else if (USE_DISPATCH_GET_CURRENT_QUEUE) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Wdeprecated-declarations"
            dispatch_queue_t currentQueue = dispatch_get_current_queue();
            #pragma clang diagnostic pop
            _queueLabel = [[NSString alloc] initWithFormat:@"%s", dispatch_queue_get_label(currentQueue)];
        } else {
            _queueLabel = @""; // iOS 6.x only
        }
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    KCLLogMessage *newMessage = [KCLLogMessage new];
    
    newMessage->_message = _message;
    newMessage->_level = _level;
    newMessage->_flag = _flag;
    newMessage->_context = _context;
    newMessage->_file = _file;
    newMessage->_fileName = _fileName;
    newMessage->_function = _function;
    newMessage->_line = _line;
    newMessage->_tag = _tag;
    newMessage->_options = _options;
    newMessage->_timestamp = _timestamp;
    newMessage->_threadID = _threadID;
    newMessage->_threadName = _threadName;
    newMessage->_queueLabel = _queueLabel;

    return newMessage;
}

@end


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation KCLAbstractLogger

- (instancetype)init {
    if ((self = [super init])) {
        const char *loggerQueueName = NULL;

        if ([self respondsToSelector:@selector(loggerName)]) {
            loggerQueueName = [[self loggerName] UTF8String];
        }

        _loggerQueue = dispatch_queue_create(loggerQueueName, NULL);

        void *key = (__bridge void *)self;
        void *nonNullValue = (__bridge void *)self;

        dispatch_queue_set_specific(_loggerQueue, key, nonNullValue, NULL);
    }

    return self;
}

- (void)dealloc {
    #if !OS_OBJECT_USE_OBJC

    if (_loggerQueue) {
        dispatch_release(_loggerQueue);
    }

    #endif
}

- (void)logMessage:(KCLLogMessage *)logMessage {
    // Override me
}

- (id <KCLLogFormatter>)logFormatter {
   
    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");

    dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];

    __block id <KCLLogFormatter> result;

    dispatch_sync(globalLoggingQueue, ^{
        dispatch_sync(_loggerQueue, ^{
            result = _logFormatter;
        });
    });

    return result;
}

- (void)setLogFormatter:(id <KCLLogFormatter>)logFormatter {
    // The design of this method is documented extensively in the logFormatter message (above in code).

    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");

    dispatch_block_t block = ^{
        @autoreleasepool {
            if (_logFormatter != logFormatter) {
                if ([_logFormatter respondsToSelector:@selector(willRemoveFromLogger:)]) {
                    [_logFormatter willRemoveFromLogger:self];
                }

                _logFormatter = logFormatter;

                if ([_logFormatter respondsToSelector:@selector(didAddToLogger:)]) {
                    [_logFormatter didAddToLogger:self];
                }
            }
        }
    };

    dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];

    dispatch_async(globalLoggingQueue, ^{
        dispatch_async(_loggerQueue, block);
    });
}

- (dispatch_queue_t)loggerQueue {
    return _loggerQueue;
}

- (NSString *)loggerName {
    return NSStringFromClass([self class]);
}

- (BOOL)isOnGlobalLoggingQueue {
    return (dispatch_get_specific(GlobalLoggingQueueIdentityKey) != NULL);
}

- (BOOL)isOnInternalLoggerQueue {
    void *key = (__bridge void *)self;

    return (dispatch_get_specific(key) != NULL);
}

@end
