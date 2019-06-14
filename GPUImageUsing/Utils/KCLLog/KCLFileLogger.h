
#ifndef KCL_LEGACY_MACROS
    #define KCL_LEGACY_MACROS 0
#endif

#import "KCLLog.h"

@class KCLLogFileInfo;


extern unsigned long long const kKCLDefaultLogMaxFileSize;
extern NSTimeInterval     const kKCLDefaultLogRollingFrequency;
extern NSUInteger         const kKCLDefaultLogMaxNumLogFiles;
extern unsigned long long const kKCLDefaultLogFilesDiskQuota;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@protocol KCLLogFileManager <NSObject>
@required

// Public properties

/**
 * The maximum number of archived log files to keep on disk.
 * For example, if this property is set to 3,
 * then the LogFileManager will only keep 3 archived log files (plus the current active log file) on disk.
 * Once the active log file is rolled/archived, then the oldest of the existing 3 rolled/archived log files is deleted.
 *
 * You may optionally disable this option by setting it to zero.
 **/
@property (readwrite, assign, atomic) NSUInteger maximumNumberOfLogFiles;

/**
 * The maximum space that logs can take. On rolling logfile all old logfiles that exceed logFilesDiskQuota will
 * be deleted.
 *
 * You may optionally disable this option by setting it to zero.
 **/
@property (readwrite, assign, atomic) unsigned long long logFilesDiskQuota;

// Public methods

- (NSString *)logsDirectory;

- (NSArray *)unsortedLogFilePaths;
- (NSArray *)unsortedLogFileNames;
- (NSArray *)unsortedLogFileInfos;

- (NSArray *)sortedLogFilePaths;
- (NSArray *)sortedLogFileNames;
- (NSArray *)sortedLogFileInfos;

- (NSString *)createNewLogFile;

@optional

- (void)didArchiveLogFile:(NSString *)logFilePath;
- (void)didRollAndArchiveLogFile:(NSString *)logFilePath;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


@interface KCLLogFileManagerDefault : NSObject <KCLLogFileManager>

- (instancetype)init;
- (instancetype)initWithLogsDirectory:(NSString *)logsDirectory NS_DESIGNATED_INITIALIZER;
#if TARGET_OS_IPHONE

- (instancetype)initWithLogsDirectory:(NSString *)logsDirectory defaultFileProtectionLevel:(NSString *)fileProtectionLevel;
#endif

@property (readonly, copy) NSString *newLogFileName;
- (BOOL)isLogFile:(NSString *)fileName;


@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface KCLLogFileFormatterDefault : NSObject <KCLLogFormatter>

- (instancetype)init;
- (instancetype)initWithDateFormatter:(NSDateFormatter *)dateFormatter NS_DESIGNATED_INITIALIZER;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface KCLFileLogger : KCLAbstractLogger <KCLLogger>

- (instancetype)init;
- (instancetype)initWithLogFileManager:(id <KCLLogFileManager>)logFileManager NS_DESIGNATED_INITIALIZER;


@property (readwrite, assign) unsigned long long maximumFileSize;
@property (readwrite, assign) NSTimeInterval rollingFrequency;
@property (readwrite, assign, atomic) BOOL doNotReuseLogFiles;


@property (strong, nonatomic, readonly) id <KCLLogFileManager> logFileManager;


@property (nonatomic, readwrite, assign) BOOL automaticallyAppendNewlineForCustomFormatters;


- (void)rollLogFileWithCompletionBlock:(void (^)())completionBlock;


- (void)rollLogFile __attribute((deprecated));


- (KCLLogFileInfo *)currentLogFileInfo;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface KCLLogFileInfo : NSObject

@property (strong, nonatomic, readonly) NSString *filePath;
@property (strong, nonatomic, readonly) NSString *fileName;

@property (strong, nonatomic, readonly) NSDictionary *fileAttributes;

@property (strong, nonatomic, readonly) NSDate *creationDate;
@property (strong, nonatomic, readonly) NSDate *modificationDate;

@property (nonatomic, readonly) unsigned long long fileSize;

@property (nonatomic, readonly) NSTimeInterval age;

@property (nonatomic, readwrite) BOOL isArchived;

+ (instancetype)logFileWithPath:(NSString *)filePath;

- (instancetype)initWithFilePath:(NSString *)filePath NS_DESIGNATED_INITIALIZER;

- (void)reset;
- (void)renameFile:(NSString *)newFileName;

#if TARGET_IPHONE_SIMULATOR

- (BOOL)hasExtensionAttributeWithName:(NSString *)attrName;

- (void)addExtensionAttributeWithName:(NSString *)attrName;
- (void)removeExtensionAttributeWithName:(NSString *)attrName;

#else /* if TARGET_IPHONE_SIMULATOR */

// Normal use of extended attributes used everywhere else,
// such as on Macs and on iPhone devices.

- (BOOL)hasExtendedAttributeWithName:(NSString *)attrName;

- (void)addExtendedAttributeWithName:(NSString *)attrName;
- (void)removeExtendedAttributeWithName:(NSString *)attrName;

#endif /* if TARGET_IPHONE_SIMULATOR */

- (NSComparisonResult)reverseCompareByCreationDate:(KCLLogFileInfo *)another;
- (NSComparisonResult)reverseCompareByModificationDate:(KCLLogFileInfo *)another;

@end
