

#import <Foundation/Foundation.h>

// Enable 1.9.x legacy macros if imported directly
#ifndef KCL_LEGACY_MACROS
    #define KCL_LEGACY_MACROS 1
#endif

#if OS_OBJECT_USE_OBJC
    #define DISPATCH_QUEUE_REFERENCE_TYPE strong
#else
    #define DISPATCH_QUEUE_REFERENCE_TYPE assign
#endif

@class KCLLogMessage;
@protocol KCLLogger;
@protocol KCLLogFormatter;

typedef NS_OPTIONS(NSUInteger, KCLLogFlag) {
    KCLLogFlagError      = (1 << 0), // 0...00001
    KCLLogFlagWarning    = (1 << 1), // 0...00010
    KCLLogFlagInfo       = (1 << 2), // 0...00100
    KCLLogFlagDebug      = (1 << 3), // 0...01000
    KCLLogFlagVerbose    = (1 << 4)  // 0...10000
};

typedef NS_ENUM(NSUInteger, KCLLogLevel) {
    KCLLogLevelOff       = 0,
    KCLLogLevelError     = (KCLLogFlagError),                       // 0...00001
    KCLLogLevelWarning   = (KCLLogLevelError   | KCLLogFlagWarning), // 0...00011
    KCLLogLevelInfo      = (KCLLogLevelWarning | KCLLogFlagInfo),    // 0...00111
    KCLLogLevelDebug     = (KCLLogLevelInfo    | KCLLogFlagDebug),   // 0...01111
    KCLLogLevelVerbose   = (KCLLogLevelDebug   | KCLLogFlagVerbose), // 0...11111
    KCLLogLevelAll       = NSUIntegerMax                           // 1111....11111 (KCLLogLevelVerbose plus any other flags)
};

NSString * KCLExtractFileNameWithoutExtension(const char *filePath, BOOL copy);

#define THIS_FILE         (KCLExtractFileNameWithoutExtension(__FILE__, NO))

#define THIS_METHOD       NSStringFromSelector(_cmd)


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface KCLLog : NSObject

/**
 * Provides access to the underlying logging queue.
 * This may be helpful to Logger classes for things like thread synchronization.
 **/

+ (dispatch_queue_t)loggingQueue;

/**
 * Logging Primitive.
 *
 * This method is used by the macros above.
 * It is suggested you stick with the macros as they're easier to use.
 **/

+ (void)log:(BOOL)synchronous
      level:(KCLLogLevel)level
       flag:(KCLLogFlag)flag
    context:(NSInteger)context
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
        tag:(id)tag
     format:(NSString *)format, ... NS_FORMAT_FUNCTION(9,10);


+ (void)log:(BOOL)asynchronous
      level:(KCLLogLevel)level
       flag:(KCLLogFlag)flag
    context:(NSInteger)context
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
        tag:(id)tag
     format:(NSString *)format
       args:(va_list)argList;

/**
 * Logging Primitive.
 **/
+ (void)log:(BOOL)asynchronous
    message:(NSString *)message
      level:(KCLLogLevel)level
       flag:(KCLLogFlag)flag
    context:(NSInteger)context
       file:(const char *)file
   function:(const char *)function
       line:(NSUInteger)line
        tag:(id)tag;


+ (void)log:(BOOL)asynchronous
    message:(KCLLogMessage *)logMessage;

+ (void)flushLog;


+ (void)addLogger:(id <KCLLogger>)logger;

+ (void)addLogger:(id <KCLLogger>)logger withLevel:(KCLLogLevel)level;

+ (void)removeLogger:(id <KCLLogger>)logger;
+ (void)removeAllLoggers;

+ (NSArray *)allLoggers;

/**
 * Registered Dynamic Logging
 *
 * These methods allow you to obtain a list of classes that are using registered dynamic logging,
 * and also provides methods to get and set their log level during run time.
 **/

+ (NSArray *)registeredClasses;
+ (NSArray *)registeredClassNames;

+ (KCLLogLevel)levelForClass:(Class)aClass;
+ (KCLLogLevel)levelForClassWithName:(NSString *)aClassName;

+ (void)setLevel:(KCLLogLevel)level forClass:(Class)aClass;
+ (void)setLevel:(KCLLogLevel)level forClassWithName:(NSString *)aClassName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol KCLLogger <NSObject>

- (void)logMessage:(KCLLogMessage *)logMessage;

@property (nonatomic, strong) id <KCLLogFormatter> logFormatter;

@optional

- (void)didAddLogger;
- (void)willRemoveLogger;

- (void)flush;

@property (nonatomic, DISPATCH_QUEUE_REFERENCE_TYPE, readonly) dispatch_queue_t loggerQueue;

@property (nonatomic, readonly) NSString *loggerName;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol KCLLogFormatter <NSObject>
@required

- (NSString *)formatLogMessage:(KCLLogMessage *)logMessage;

@optional

- (void)didAddToLogger:(id <KCLLogger>)logger;
- (void)willRemoveFromLogger:(id <KCLLogger>)logger;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol KCLRegisteredDynamicLogging

+ (KCLLogLevel)ddLogLevel;
+ (void)ddSetLogLevel:(KCLLogLevel)level;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef NS_DESIGNATED_INITIALIZER
    #define NS_DESIGNATED_INITIALIZER
#endif

typedef NS_OPTIONS(NSInteger, KCLLogMessageOptions) {
    KCLLogMessageCopyFile     = 1 << 0,
    KCLLogMessageCopyFunction = 1 << 1
};

@interface KCLLogMessage : NSObject <NSCopying>
{
    // Direct accessors to be used only for performance
    @public
    NSString *_message;
    KCLLogLevel _level;
    KCLLogFlag _flag;
    NSInteger _context;
    NSString *_file;
    NSString *_fileName;
    NSString *_function;
    NSUInteger _line;
    id _tag;
    KCLLogMessageOptions _options;
    NSDate *_timestamp;
    NSString *_threadID;
    NSString *_threadName;
    NSString *_queueLabel;
}

- (instancetype)initWithMessage:(NSString *)message
                          level:(KCLLogLevel)level
                           flag:(KCLLogFlag)flag
                        context:(NSInteger)context
                           file:(NSString *)file
                       function:(NSString *)function
                           line:(NSUInteger)line
                            tag:(id)tag
                        options:(KCLLogMessageOptions)options
                      timestamp:(NSDate *)timestamp NS_DESIGNATED_INITIALIZER;

/**
 * Read-only properties
 **/
@property (readonly, nonatomic) NSString *message;
@property (readonly, nonatomic) KCLLogLevel level;
@property (readonly, nonatomic) KCLLogFlag flag;
@property (readonly, nonatomic) NSInteger context;
@property (readonly, nonatomic) NSString *file;
@property (readonly, nonatomic) NSString *fileName;
@property (readonly, nonatomic) NSString *function;
@property (readonly, nonatomic) NSUInteger line;
@property (readonly, nonatomic) id tag;
@property (readonly, nonatomic) KCLLogMessageOptions options;
@property (readonly, nonatomic) NSDate *timestamp;
@property (readonly, nonatomic) NSString *threadID; // ID as it appears in NSLog calculated from the machThreadID
@property (readonly, nonatomic) NSString *threadName;
@property (readonly, nonatomic) NSString *queueLabel;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface KCLAbstractLogger : NSObject <KCLLogger>
{
    // Direct accessors to be used only for performance
    @public
    id <KCLLogFormatter> _logFormatter;
    dispatch_queue_t _loggerQueue;
}

@property (nonatomic, strong) id <KCLLogFormatter> logFormatter;
@property (nonatomic, DISPATCH_QUEUE_REFERENCE_TYPE) dispatch_queue_t loggerQueue;

// For thread-safety assertions
@property (nonatomic, readonly, getter=isOnGlobalLoggingQueue)  BOOL onGlobalLoggingQueue;
@property (nonatomic, readonly, getter=isOnInternalLoggerQueue) BOOL onInternalLoggerQueue;

@end

