
#import "KCLTTYLogger.h"

#import <unistd.h>
#import <sys/uio.h>

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#define LOG_LEVEL 2

#define NSLogError(frmt, ...)    do{ if(LOG_LEVEL >= 1) NSLog((frmt), ##__VA_ARGS__); } while(0)
#define NSLogWarn(frmt, ...)     do{ if(LOG_LEVEL >= 2) NSLog((frmt), ##__VA_ARGS__); } while(0)
#define NSLogInfo(frmt, ...)     do{ if(LOG_LEVEL >= 3) NSLog((frmt), ##__VA_ARGS__); } while(0)
#define NSLogDebug(frmt, ...)    do{ if(LOG_LEVEL >= 4) NSLog((frmt), ##__VA_ARGS__); } while(0)
#define NSLogVerbose(frmt, ...)  do{ if(LOG_LEVEL >= 5) NSLog((frmt), ##__VA_ARGS__); } while(0)

#define XCODE_COLORS_ESCAPE_SEQ "\033["

#define XCODE_COLORS_RESET_FG   XCODE_COLORS_ESCAPE_SEQ "fg;" // Clear any foreground color
#define XCODE_COLORS_RESET_BG   XCODE_COLORS_ESCAPE_SEQ "bg;" // Clear any background color
#define XCODE_COLORS_RESET      XCODE_COLORS_ESCAPE_SEQ ";"  // Clear any foreground or background color

#define MAP_TO_TERMINAL_APP_COLORS 1


@interface KCLTTYLoggerColorProfile : NSObject {
    @public
    KCLLogFlag mask;
    NSInteger context;

    uint8_t fg_r;
    uint8_t fg_g;
    uint8_t fg_b;

    uint8_t bg_r;
    uint8_t bg_g;
    uint8_t bg_b;

    NSUInteger fgCodeIndex;
    NSString *fgCodeRaw;

    NSUInteger bgCodeIndex;
    NSString *bgCodeRaw;

    char fgCode[24];
    size_t fgCodeLen;

    char bgCode[24];
    size_t bgCodeLen;

    char resetCode[8];
    size_t resetCodeLen;
}

- (instancetype)initWithForegroundColor:(KCLColor *)fgColor backgroundColor:(KCLColor *)bgColor flag:(KCLLogFlag)mask context:(NSInteger)ctxt;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface KCLTTYLogger () {
    NSUInteger _calendarUnitFlags;
    
    NSString *_appName;
    char *_app;
    size_t _appLen;
    
    NSString *_processID;
    char *_pid;
    size_t _pidLen;
    
    BOOL _colorsEnabled;
    NSMutableArray *_colorProfilesArray;
    NSMutableDictionary *_colorProfilesDict;
}

@end


@implementation KCLTTYLogger

static BOOL isaColorTTY;
static BOOL isaColor256TTY;
static BOOL isaXcodeColorTTY;

static NSArray *codes_fg = nil;
static NSArray *codes_bg = nil;
static NSArray *colors   = nil;

static KCLTTYLogger *sharedInstance;

+ (void)initialize_colors_16 {
    if (codes_fg || codes_bg || colors) {
        return;
    }

    NSMutableArray *m_codes_fg = [NSMutableArray arrayWithCapacity:16];
    NSMutableArray *m_codes_bg = [NSMutableArray arrayWithCapacity:16];
    NSMutableArray *m_colors   = [NSMutableArray arrayWithCapacity:16];

    // In a standard shell only 16 colors are supported.
    //
    // More information about ansi escape codes can be found online.
    // http://en.wikipedia.org/wiki/ANSI_escape_code

    [m_codes_fg addObject:@"30m"];   // normal - black
    [m_codes_fg addObject:@"31m"];   // normal - red
    [m_codes_fg addObject:@"32m"];   // normal - green
    [m_codes_fg addObject:@"33m"];   // normal - yellow
    [m_codes_fg addObject:@"34m"];   // normal - blue
    [m_codes_fg addObject:@"35m"];   // normal - magenta
    [m_codes_fg addObject:@"36m"];   // normal - cyan
    [m_codes_fg addObject:@"37m"];   // normal - gray
    [m_codes_fg addObject:@"1;30m"]; // bright - darkgray
    [m_codes_fg addObject:@"1;31m"]; // bright - red
    [m_codes_fg addObject:@"1;32m"]; // bright - green
    [m_codes_fg addObject:@"1;33m"]; // bright - yellow
    [m_codes_fg addObject:@"1;34m"]; // bright - blue
    [m_codes_fg addObject:@"1;35m"]; // bright - magenta
    [m_codes_fg addObject:@"1;36m"]; // bright - cyan
    [m_codes_fg addObject:@"1;37m"]; // bright - white

    [m_codes_bg addObject:@"40m"];   // normal - black
    [m_codes_bg addObject:@"41m"];   // normal - red
    [m_codes_bg addObject:@"42m"];   // normal - green
    [m_codes_bg addObject:@"43m"];   // normal - yellow
    [m_codes_bg addObject:@"44m"];   // normal - blue
    [m_codes_bg addObject:@"45m"];   // normal - magenta
    [m_codes_bg addObject:@"46m"];   // normal - cyan
    [m_codes_bg addObject:@"47m"];   // normal - gray
    [m_codes_bg addObject:@"1;40m"]; // bright - darkgray
    [m_codes_bg addObject:@"1;41m"]; // bright - red
    [m_codes_bg addObject:@"1;42m"]; // bright - green
    [m_codes_bg addObject:@"1;43m"]; // bright - yellow
    [m_codes_bg addObject:@"1;44m"]; // bright - blue
    [m_codes_bg addObject:@"1;45m"]; // bright - magenta
    [m_codes_bg addObject:@"1;46m"]; // bright - cyan
    [m_codes_bg addObject:@"1;47m"]; // bright - white

#if MAP_TO_TERMINAL_APP_COLORS

    // Standard Terminal.app colors:
    //
    // These are the default colors used by Apple's Terminal.app.

    [m_colors addObject:KCLMakeColor(  0,   0,   0)]; // normal - black

#else /* if MAP_TO_TERMINAL_APP_COLORS */

    // Standard xterm colors:
    //
    // These are the default colors used by most xterm shells.

    [m_colors addObject:KCLMakeColor(  0,   0,   0)]; // normal - black

#endif /* if MAP_TO_TERMINAL_APP_COLORS */

    codes_fg = [m_codes_fg copy];
    codes_bg = [m_codes_bg copy];
    colors   = [m_colors   copy];

    NSAssert([codes_fg count] == [codes_bg count], @"Invalid colors/codes array(s)");
    NSAssert([codes_fg count] == [colors count],   @"Invalid colors/codes array(s)");
}

/**
 * Initializes the colors array, as well as the codes_fg and codes_bg arrays, for 256 color mode.
 *
 * This method is used when the application is running from within a shell that supports 256 color mode.
 * This method is not invoked if the application is running within Xcode, or via normal UI app launch.
 **/
+ (void)initialize_colors_256 {
    if (codes_fg || codes_bg || colors) {
        return;
    }

    NSMutableArray *m_codes_fg = [NSMutableArray arrayWithCapacity:(256 - 16)];
    NSMutableArray *m_codes_bg = [NSMutableArray arrayWithCapacity:(256 - 16)];
    NSMutableArray *m_colors   = [NSMutableArray arrayWithCapacity:(256 - 16)];

    #if MAP_TO_TERMINAL_APP_COLORS

    [m_colors addObject:KCLMakeColor( 47,  49,  49)];
    
    // Color codes

    int index = 16;

    while (index < 256) {
        [m_codes_fg addObject:[NSString stringWithFormat:@"38;5;%dm", index]];
        [m_codes_bg addObject:[NSString stringWithFormat:@"48;5;%dm", index]];

        index++;
    }

    #else /* if MAP_TO_TERMINAL_APP_COLORS */

    // Standard xterm colors:
    //
    // These are the colors xterm shells use in xterm-256color mode.
    // In this mode, the shell supports 256 different colors, specified by 256 color codes.
    //
    // The first 16 color codes map to the original 16 color codes supported by the earlier xterm-color mode.
    // These are generally configurable, and thus we ignore them for the purposes of mapping,
    // as we can't rely on them being constant. They are largely duplicated anyway.
    //
    // The next 216 color codes are designed to run the spectrum, with several shades of every color.
    // The last 24 color codes represent a grayscale.
    //
    // While the color codes are standardized, the actual RGB values for each color code is not.
    // However most standard xterms follow a well known color chart,
    // which can easily be calculated using the simple formula below.
    //
    // More information about ansi escape codes can be found online.
    // http://en.wikipedia.org/wiki/ANSI_escape_code

    int index = 16;

    int r; // red
    int g; // green
    int b; // blue

    int ri; // r increment
    int gi; // g increment
    int bi; // b increment

    // Calculate xterm colors (using standard algorithm)

    int r = 0;
    int g = 0;
    int b = 0;

    for (ri = 0; ri < 6; ri++) {
        r = (ri == 0) ? 0 : 95 + (40 * (ri - 1));

        for (gi = 0; gi < 6; gi++) {
            g = (gi == 0) ? 0 : 95 + (40 * (gi - 1));

            for (bi = 0; bi < 6; bi++) {
                b = (bi == 0) ? 0 : 95 + (40 * (bi - 1));

                [m_codes_fg addObject:[NSString stringWithFormat:@"38;5;%dm", index]];
                [m_codes_bg addObject:[NSString stringWithFormat:@"48;5;%dm", index]];
                [m_colors addObject:KCLMakeColor(r, g, b)];

                index++;
            }
        }
    }

    // Calculate xterm grayscale (using standard algorithm)

    r = 8;
    g = 8;
    b = 8;

    while (index < 256) {
        [m_codes_fg addObject:[NSString stringWithFormat:@"38;5;%dm", index]];
        [m_codes_bg addObject:[NSString stringWithFormat:@"48;5;%dm", index]];
        [m_colors addObject:KCLMakeColor(r, g, b)];

        r += 10;
        g += 10;
        b += 10;

        index++;
    }

    #endif /* if MAP_TO_TERMINAL_APP_COLORS */

    codes_fg = [m_codes_fg copy];
    codes_bg = [m_codes_bg copy];
    colors   = [m_colors   copy];

    NSAssert([codes_fg count] == [codes_bg count], @"Invalid colors/codes array(s)");
    NSAssert([codes_fg count] == [colors count],   @"Invalid colors/codes array(s)");
}

+ (void)getRed:(CGFloat *)rPtr green:(CGFloat *)gPtr blue:(CGFloat *)bPtr fromColor:(KCLColor *)color {
    #if TARGET_OS_IPHONE

    // iOS

    BOOL done = NO;

    if ([color respondsToSelector:@selector(getRed:green:blue:alpha:)]) {
        done = [color getRed:rPtr green:gPtr blue:bPtr alpha:NULL];
    }

    if (!done) {
        // The method getRed:green:blue:alpha: was only available starting iOS 5.
        // So in iOS 4 and earlier, we have to jump through hoops.

        CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();

        unsigned char pixel[4];
        CGContextRef context = CGBitmapContextCreate(&pixel, 1, 1, 8, 4, rgbColorSpace, (CGBitmapInfo)(kCGBitmapAlphaInfoMask & kCGImageAlphaNoneSkipLast));

        CGContextSetFillColorWithColor(context, [color CGColor]);
        CGContextFillRect(context, CGRectMake(0, 0, 1, 1));

        if (rPtr) {
            *rPtr = pixel[0] / 255.0f;
        }

        if (gPtr) {
            *gPtr = pixel[1] / 255.0f;
        }

        if (bPtr) {
            *bPtr = pixel[2] / 255.0f;
        }

        CGContextRelease(context);
        CGColorSpaceRelease(rgbColorSpace);
    }

    #elif __has_include(<AppKit/NSColor.h>)

    // OS X with AppKit

    NSColor *safeColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];

    [safeColor getRed:rPtr green:gPtr blue:bPtr alpha:NULL];

    #else /* if TARGET_OS_IPHONE */

    // OS X without AppKit

    [color getRed:rPtr green:gPtr blue:bPtr alpha:NULL];

    #endif /* if TARGET_OS_IPHONE */
}

/**
 * Maps the given color to the closest available color supported by the shell.
 * The shell may support 256 colors, or only 16.
 *
 * This method loops through the known supported color set, and calculates the closest color.
 * The array index of that color, within the colors array, is then returned.
 * This array index may also be used as the index within the codes_fg and codes_bg arrays.
 **/
+ (NSUInteger)codeIndexForColor:(KCLColor *)inColor {
    CGFloat inR, inG, inB;

    [self getRed:&inR green:&inG blue:&inB fromColor:inColor];

    NSUInteger bestIndex = 0;
    CGFloat lowestDistance = 100.0f;

    NSUInteger i = 0;

    for (KCLColor *color in colors) {
        // Calculate Euclidean distance (lower value means closer to given color)

        CGFloat r, g, b;
        [self getRed:&r green:&g blue:&b fromColor:color];

    #if CGFLOAT_IS_DOUBLE
        CGFloat distance = sqrt(pow(r - inR, 2.0) + pow(g - inG, 2.0) + pow(b - inB, 2.0));
    #else
        CGFloat distance = sqrtf(powf(r - inR, 2.0f) + powf(g - inG, 2.0f) + powf(b - inB, 2.0f));
    #endif

        NSLogVerbose(@"KCLTTYLogger: %3lu : %.3f,%.3f,%.3f & %.3f,%.3f,%.3f = %.6f",
                     (unsigned long)i, inR, inG, inB, r, g, b, distance);

        if (distance < lowestDistance) {
            bestIndex = i;
            lowestDistance = distance;

            NSLogVerbose(@"KCLTTYLogger: New best index = %lu", (unsigned long)bestIndex);
        }

        i++;
    }

    return bestIndex;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t KCLTTYLoggerOnceToken;

    dispatch_once(&KCLTTYLoggerOnceToken, ^{
        // Xcode does NOT natively support colors in the Xcode debugging console.
        // You'll need to install the XcodeColors plugin to see colors in the Xcode console.
        //
        // PS - Please read the header file before diving into the source code.

        char *xcode_colors = getenv("XcodeColors");
        char *term = getenv("TERM");

        if (xcode_colors && (strcmp(xcode_colors, "YES") == 0)) {
            isaXcodeColorTTY = YES;
        } else if (term) {
            if (strcasestr(term, "color") != NULL) {
                isaColorTTY = YES;
                isaColor256TTY = (strcasestr(term, "256") != NULL);

                if (isaColor256TTY) {
                    [self initialize_colors_256];
                } else {
                    [self initialize_colors_16];
                }
            }
        }

        NSLogInfo(@"KCLTTYLogger: isaColorTTY = %@", (isaColorTTY ? @"YES" : @"NO"));
        NSLogInfo(@"KCLTTYLogger: isaColor256TTY: %@", (isaColor256TTY ? @"YES" : @"NO"));
        NSLogInfo(@"KCLTTYLogger: isaXcodeColorTTY: %@", (isaXcodeColorTTY ? @"YES" : @"NO"));

        sharedInstance = [[[self class] alloc] init];
    });

    return sharedInstance;
}

- (instancetype)init {
    if (sharedInstance != nil) {
        return nil;
    }

    if ((self = [super init])) {
        _calendarUnitFlags = (NSCalendarUnitYear     |
                             NSCalendarUnitMonth    |
                             NSCalendarUnitDay      |
                             NSCalendarUnitHour     |
                             NSCalendarUnitMinute   |
                             NSCalendarUnitSecond);

        // Initialze 'app' variable (char *)

        _appName = [[NSProcessInfo processInfo] processName];

        _appLen = [_appName lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

        if (_appLen == 0) {
            _appName = @"<UnnamedApp>";
            _appLen = [_appName lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        }

        _app = (char *)malloc(_appLen + 1);

        if (_app == NULL) {
            return nil;
        }

        BOOL processedAppName = [_appName getCString:_app maxLength:(_appLen + 1) encoding:NSUTF8StringEncoding];

        if (NO == processedAppName) {
            return nil;
        }

        // Initialize 'pid' variable (char *)

        _processID = [NSString stringWithFormat:@"%i", (int)getpid()];

        _pidLen = [_processID lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        _pid = (char *)malloc(_pidLen + 1);

        if (_pid == NULL) {
            return nil;
        }

        BOOL processedID = [_processID getCString:_pid maxLength:(_pidLen + 1) encoding:NSUTF8StringEncoding];

        if (NO == processedID) {
            return nil;
        }

        // Initialize color stuff

        _colorsEnabled = NO;
        _colorProfilesArray = [[NSMutableArray alloc] initWithCapacity:8];
        _colorProfilesDict = [[NSMutableDictionary alloc] initWithCapacity:8];

        _automaticallyAppendNewlineForCustomFormatters = YES;
    }

    return self;
}

- (void)loadDefaultColorProfiles {
    [self setForegroundColor:KCLMakeColor(214,  57,  30) backgroundColor:nil forFlag:KCLLogFlagError];
    [self setForegroundColor:KCLMakeColor(204, 121,  32) backgroundColor:nil forFlag:KCLLogFlagWarning];
}

- (BOOL)colorsEnabled {
    // The design of this method is taken from the KCLAbstractLogger implementation.
    // For extensive documentation please refer to the KCLAbstractLogger implementation.

    // Note: The internal implementation MUST access the colorsEnabled variable directly,
    // This method is designed explicitly for external access.
    //
    // Using "self." syntax to go through this method will cause immediate deadlock.
    // This is the intended result. Fix it by accessing the ivar directly.
    // Great strides have been take to ensure this is safe to do. Plus it's MUCH faster.

    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");

    dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];

    __block BOOL result;

    dispatch_sync(globalLoggingQueue, ^{
        dispatch_sync(self.loggerQueue, ^{
            result = _colorsEnabled;
        });
    });

    return result;
}

- (void)setColorsEnabled:(BOOL)newColorsEnabled {
    dispatch_block_t block = ^{
        @autoreleasepool {
            _colorsEnabled = newColorsEnabled;

            if ([_colorProfilesArray count] == 0) {
                [self loadDefaultColorProfiles];
            }
        }
    };

    // The design of this method is taken from the KCLAbstractLogger implementation.
    // For extensive documentation please refer to the KCLAbstractLogger implementation.

    // Note: The internal implementation MUST access the colorsEnabled variable directly,
    // This method is designed explicitly for external access.
    //
    // Using "self." syntax to go through this method will cause immediate deadlock.
    // This is the intended result. Fix it by accessing the ivar directly.
    // Great strides have been take to ensure this is safe to do. Plus it's MUCH faster.

    NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");
    NSAssert(![self isOnInternalLoggerQueue], @"MUST access ivar directly, NOT via self.* syntax.");

    dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];

    dispatch_async(globalLoggingQueue, ^{
        dispatch_async(self.loggerQueue, block);
    });
}

- (void)setForegroundColor:(KCLColor *)txtColor backgroundColor:(KCLColor *)bgColor forFlag:(KCLLogFlag)mask {
    [self setForegroundColor:txtColor backgroundColor:bgColor forFlag:mask context:LOG_CONTEXT_ALL];
}

- (void)setForegroundColor:(KCLColor *)txtColor backgroundColor:(KCLColor *)bgColor forFlag:(KCLLogFlag)mask context:(NSInteger)ctxt {
    dispatch_block_t block = ^{
        @autoreleasepool {
            KCLTTYLoggerColorProfile *newColorProfile =
                [[KCLTTYLoggerColorProfile alloc] initWithForegroundColor:txtColor
                                                         backgroundColor:bgColor
                                                                    flag:mask
                                                                 context:ctxt];

            NSLogInfo(@"KCLTTYLogger: newColorProfile: %@", newColorProfile);

            NSUInteger i = 0;

            for (KCLTTYLoggerColorProfile *colorProfile in _colorProfilesArray) {
                if ((colorProfile->mask == mask) && (colorProfile->context == ctxt)) {
                    break;
                }

                i++;
            }

            if (i < [_colorProfilesArray count]) {
                _colorProfilesArray[i] = newColorProfile;
            } else {
                [_colorProfilesArray addObject:newColorProfile];
            }
        }
    };

    // The design of the setter logic below is taken from the KCLAbstractLogger implementation.
    // For documentation please refer to the KCLAbstractLogger implementation.

    if ([self isOnInternalLoggerQueue]) {
        block();
    } else {
        dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];
        NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");

        dispatch_async(globalLoggingQueue, ^{
            dispatch_async(self.loggerQueue, block);
        });
    }
}

- (void)setForegroundColor:(KCLColor *)txtColor backgroundColor:(KCLColor *)bgColor forTag:(id <NSCopying>)tag {
    NSAssert([(id < NSObject >) tag conformsToProtocol: @protocol(NSCopying)], @"Invalid tag");

    dispatch_block_t block = ^{
        @autoreleasepool {
            KCLTTYLoggerColorProfile *newColorProfile =
                [[KCLTTYLoggerColorProfile alloc] initWithForegroundColor:txtColor
                                                         backgroundColor:bgColor
                                                                    flag:(KCLLogFlag)0
                                                                 context:0];

            NSLogInfo(@"KCLTTYLogger: newColorProfile: %@", newColorProfile);

            _colorProfilesDict[tag] = newColorProfile;
        }
    };

    // The design of the setter logic below is taken from the KCLAbstractLogger implementation.
    // For documentation please refer to the KCLAbstractLogger implementation.

    if ([self isOnInternalLoggerQueue]) {
        block();
    } else {
        dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];
        NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");

        dispatch_async(globalLoggingQueue, ^{
            dispatch_async(self.loggerQueue, block);
        });
    }
}

- (void)clearColorsForFlag:(KCLLogFlag)mask {
    [self clearColorsForFlag:mask context:0];
}

- (void)clearColorsForFlag:(KCLLogFlag)mask context:(NSInteger)context {
    dispatch_block_t block = ^{
        @autoreleasepool {
            NSUInteger i = 0;

            for (KCLTTYLoggerColorProfile *colorProfile in _colorProfilesArray) {
                if ((colorProfile->mask == mask) && (colorProfile->context == context)) {
                    break;
                }

                i++;
            }

            if (i < [_colorProfilesArray count]) {
                [_colorProfilesArray removeObjectAtIndex:i];
            }
        }
    };

    // The design of the setter logic below is taken from the KCLAbstractLogger implementation.
    // For documentation please refer to the KCLAbstractLogger implementation.

    if ([self isOnInternalLoggerQueue]) {
        block();
    } else {
        dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];
        NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");

        dispatch_async(globalLoggingQueue, ^{
            dispatch_async(self.loggerQueue, block);
        });
    }
}

- (void)clearColorsForTag:(id <NSCopying>)tag {
    NSAssert([(id < NSObject >) tag conformsToProtocol: @protocol(NSCopying)], @"Invalid tag");

    dispatch_block_t block = ^{
        @autoreleasepool {
            [_colorProfilesDict removeObjectForKey:tag];
        }
    };

    // The design of the setter logic below is taken from the KCLAbstractLogger implementation.
    // For documentation please refer to the KCLAbstractLogger implementation.

    if ([self isOnInternalLoggerQueue]) {
        block();
    } else {
        dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];
        NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");

        dispatch_async(globalLoggingQueue, ^{
            dispatch_async(self.loggerQueue, block);
        });
    }
}

- (void)clearColorsForAllFlags {
    dispatch_block_t block = ^{
        @autoreleasepool {
            [_colorProfilesArray removeAllObjects];
        }
    };

    // The design of the setter logic below is taken from the KCLAbstractLogger implementation.
    // For documentation please refer to the KCLAbstractLogger implementation.

    if ([self isOnInternalLoggerQueue]) {
        block();
    } else {
        dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];
        NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");

        dispatch_async(globalLoggingQueue, ^{
            dispatch_async(self.loggerQueue, block);
        });
    }
}

- (void)clearColorsForAllTags {
    dispatch_block_t block = ^{
        @autoreleasepool {
            [_colorProfilesDict removeAllObjects];
        }
    };

    // The design of the setter logic below is taken from the KCLAbstractLogger implementation.
    // For documentation please refer to the KCLAbstractLogger implementation.

    if ([self isOnInternalLoggerQueue]) {
        block();
    } else {
        dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];
        NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");

        dispatch_async(globalLoggingQueue, ^{
            dispatch_async(self.loggerQueue, block);
        });
    }
}

- (void)clearAllColors {
    dispatch_block_t block = ^{
        @autoreleasepool {
            [_colorProfilesArray removeAllObjects];
            [_colorProfilesDict removeAllObjects];
        }
    };

    // The design of the setter logic below is taken from the KCLAbstractLogger implementation.
    // For documentation please refer to the KCLAbstractLogger implementation.

    if ([self isOnInternalLoggerQueue]) {
        block();
    } else {
        dispatch_queue_t globalLoggingQueue = [KCLLog loggingQueue];
        NSAssert(![self isOnGlobalLoggingQueue], @"Core architecture requirement failure");

        dispatch_async(globalLoggingQueue, ^{
            dispatch_async(self.loggerQueue, block);
        });
    }
}

- (void)logMessage:(KCLLogMessage *)logMessage {
    NSString *logMsg = logMessage->_message;
    BOOL isFormatted = NO;

    if (_logFormatter) {
        logMsg = [_logFormatter formatLogMessage:logMessage];
        isFormatted = logMsg != logMessage->_message;
    }

    if (logMsg) {
        // Search for a color profile associated with the log message

        KCLTTYLoggerColorProfile *colorProfile = nil;

        if (_colorsEnabled) {
            if (logMessage->_tag) {
                colorProfile = _colorProfilesDict[logMessage->_tag];
            }

            if (colorProfile == nil) {
                for (KCLTTYLoggerColorProfile *cp in _colorProfilesArray) {
                    if (logMessage->_flag & cp->mask) {
                        // Color profile set for this context?
                        if (logMessage->_context == cp->context) {
                            colorProfile = cp;

                            // Stop searching
                            break;
                        }

                        // Check if LOG_CONTEXT_ALL was specified as a default color for this flag
                        if (cp->context == LOG_CONTEXT_ALL) {
                            colorProfile = cp;

                            // We don't break to keep searching for more specific color profiles for the context
                        }
                    }
                }
            }
        }

        // Convert log message to C string.
        //
        // We use the stack instead of the heap for speed if possible.
        // But we're extra cautious to avoid a stack overflow.

        NSUInteger msgLen = [logMsg lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        const BOOL useStack = msgLen < (1024 * 4);

        char msgStack[useStack ? (msgLen + 1) : 1]; // Analyzer doesn't like zero-size array, hence the 1
        char *msg = useStack ? msgStack : (char *)malloc(msgLen + 1);

        if (msg == NULL) {
            return;
        }

        BOOL logMsgEnc = [logMsg getCString:msg maxLength:(msgLen + 1) encoding:NSUTF8StringEncoding];

        if (!logMsgEnc) {
            if (!useStack && msg != NULL) {
                free(msg);
            }

            return;
        }

        // Write the log message to STDERR

        if (isFormatted) {
            // The log message has already been formatted.
            int iovec_len = (_automaticallyAppendNewlineForCustomFormatters) ? 5 : 4;
            struct iovec v[iovec_len];

            if (colorProfile) {
                v[0].iov_base = colorProfile->fgCode;
                v[0].iov_len = colorProfile->fgCodeLen;

                v[1].iov_base = colorProfile->bgCode;
                v[1].iov_len = colorProfile->bgCodeLen;

                v[iovec_len - 1].iov_base = colorProfile->resetCode;
                v[iovec_len - 1].iov_len = colorProfile->resetCodeLen;
            } else {
                v[0].iov_base = "";
                v[0].iov_len = 0;

                v[1].iov_base = "";
                v[1].iov_len = 0;

                v[iovec_len - 1].iov_base = "";
                v[iovec_len - 1].iov_len = 0;
            }

            v[2].iov_base = (char *)msg;
            v[2].iov_len = msgLen;

            if (iovec_len == 5) {
                v[3].iov_base = "\n";
                v[3].iov_len = (msg[msgLen] == '\n') ? 0 : 1;
            }

            writev(STDERR_FILENO, v, iovec_len);
        } else {
            // The log message is unformatted, so apply standard NSLog style formatting.

            int len;
            char ts[24] = "";
            size_t tsLen = 0;

            // Calculate timestamp.
            // The technique below is faster than using NSDateFormatter.
            if (logMessage->_timestamp) {
                NSDateComponents *components = [[NSCalendar autoupdatingCurrentCalendar] components:_calendarUnitFlags fromDate:logMessage->_timestamp];

                NSTimeInterval epoch = [logMessage->_timestamp timeIntervalSinceReferenceDate];
                int milliseconds = (int)((epoch - floor(epoch)) * 1000);

                len = snprintf(ts, 24, "%04ld-%02ld-%02ld %02ld:%02ld:%02ld:%03d", // yyyy-MM-dd HH:mm:ss:SSS
                               (long)components.year,
                               (long)components.month,
                               (long)components.day,
                               (long)components.hour,
                               (long)components.minute,
                               (long)components.second, milliseconds);

                tsLen = (NSUInteger)MAX(MIN(24 - 1, len), 0);
            }

            // Calculate thread ID
            //
            // How many characters do we need for the thread id?
            // logMessage->machThreadID is of type mach_port_t, which is an unsigned int.
            //
            // 1 hex char = 4 bits
            // 8 hex chars for 32 bit, plus ending '\0' = 9

            char tid[9];
            len = snprintf(tid, 9, "%s", [logMessage->_threadID cStringUsingEncoding:NSUTF8StringEncoding]);

            size_t tidLen = (NSUInteger)MAX(MIN(9 - 1, len), 0);

            // Here is our format: "%s %s[%i:%s] %s", timestamp, appName, processID, threadID, logMsg

            struct iovec v[13];

            if (colorProfile) {
                v[0].iov_base = colorProfile->fgCode;
                v[0].iov_len = colorProfile->fgCodeLen;

                v[1].iov_base = colorProfile->bgCode;
                v[1].iov_len = colorProfile->bgCodeLen;

                v[12].iov_base = colorProfile->resetCode;
                v[12].iov_len = colorProfile->resetCodeLen;
            } else {
                v[0].iov_base = "";
                v[0].iov_len = 0;

                v[1].iov_base = "";
                v[1].iov_len = 0;

                v[12].iov_base = "";
                v[12].iov_len = 0;
            }

            v[2].iov_base = ts;
            v[2].iov_len = tsLen;

            v[3].iov_base = " ";
            v[3].iov_len = 1;

            v[4].iov_base = _app;
            v[4].iov_len = _appLen;

            v[5].iov_base = "[";
            v[5].iov_len = 1;

            v[6].iov_base = _pid;
            v[6].iov_len = _pidLen;

            v[7].iov_base = ":";
            v[7].iov_len = 1;

            v[8].iov_base = tid;
            v[8].iov_len = MIN((size_t)8, tidLen); // snprintf doesn't return what you might think

            v[9].iov_base = "] ";
            v[9].iov_len = 2;

            v[10].iov_base = (char *)msg;
            v[10].iov_len = msgLen;

            v[11].iov_base = "\n";
            v[11].iov_len = (msg[msgLen] == '\n') ? 0 : 1;

            writev(STDERR_FILENO, v, 13);
        }

        if (!useStack) {
            free(msg);
        }
    }
}

- (NSString *)loggerName {
    return @"cocoa.lumberjack.ttyLogger";
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation KCLTTYLoggerColorProfile

- (instancetype)initWithForegroundColor:(KCLColor *)fgColor backgroundColor:(KCLColor *)bgColor flag:(KCLLogFlag)aMask context:(NSInteger)ctxt {
    if ((self = [super init])) {
        mask = aMask;
        context = ctxt;

        CGFloat r, g, b;

        if (fgColor) {
            [KCLTTYLogger getRed:&r green:&g blue:&b fromColor:fgColor];

            fg_r = (uint8_t)(r * 255.0f);
            fg_g = (uint8_t)(g * 255.0f);
            fg_b = (uint8_t)(b * 255.0f);
        }

        if (bgColor) {
            [KCLTTYLogger getRed:&r green:&g blue:&b fromColor:bgColor];

            bg_r = (uint8_t)(r * 255.0f);
            bg_g = (uint8_t)(g * 255.0f);
            bg_b = (uint8_t)(b * 255.0f);
        }

        if (fgColor && isaColorTTY) {
            // Map foreground color to closest available shell color

            fgCodeIndex = [KCLTTYLogger codeIndexForColor:fgColor];
            fgCodeRaw   = codes_fg[fgCodeIndex];

            NSString *escapeSeq = @"\033[";

            NSUInteger len1 = [escapeSeq lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            NSUInteger len2 = [fgCodeRaw lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

            BOOL escapeSeqEnc = [escapeSeq getCString:(fgCode)      maxLength:(len1 + 1) encoding:NSUTF8StringEncoding];
            BOOL fgCodeRawEsc = [fgCodeRaw getCString:(fgCode + len1) maxLength:(len2 + 1) encoding:NSUTF8StringEncoding];

            if (!escapeSeqEnc || !fgCodeRawEsc) {
                return nil;
            }

            fgCodeLen = len1 + len2;
        } else if (fgColor && isaXcodeColorTTY) {
            // Convert foreground color to color code sequence

            const char *escapeSeq = XCODE_COLORS_ESCAPE_SEQ;

            int result = snprintf(fgCode, 24, "%sfg%u,%u,%u;", escapeSeq, fg_r, fg_g, fg_b);
            fgCodeLen = (NSUInteger)MAX(MIN(result, (24 - 1)), 0);
        } else {
            // No foreground color or no color support

            fgCode[0] = '\0';
            fgCodeLen = 0;
        }

        if (bgColor && isaColorTTY) {
            // Map background color to closest available shell color

            bgCodeIndex = [KCLTTYLogger codeIndexForColor:bgColor];
            bgCodeRaw   = codes_bg[bgCodeIndex];

            NSString *escapeSeq = @"\033[";

            NSUInteger len1 = [escapeSeq lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            NSUInteger len2 = [bgCodeRaw lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

            BOOL escapeSeqEnc = [escapeSeq getCString:(bgCode)      maxLength:(len1 + 1) encoding:NSUTF8StringEncoding];
            BOOL bgCodeRawEsc = [bgCodeRaw getCString:(bgCode + len1) maxLength:(len2 + 1) encoding:NSUTF8StringEncoding];

            if (!escapeSeqEnc || !bgCodeRawEsc) {
                return nil;
            }

            bgCodeLen = len1 + len2;
        } else if (bgColor && isaXcodeColorTTY) {
            // Convert background color to color code sequence

            const char *escapeSeq = XCODE_COLORS_ESCAPE_SEQ;

            int result = snprintf(bgCode, 24, "%sbg%u,%u,%u;", escapeSeq, bg_r, bg_g, bg_b);
            bgCodeLen = (NSUInteger)MAX(MIN(result, (24 - 1)), 0);
        } else {
            // No background color or no color support

            bgCode[0] = '\0';
            bgCodeLen = 0;
        }

        if (isaColorTTY) {
            resetCodeLen = (NSUInteger)MAX(snprintf(resetCode, 8, "\033[0m"), 0);
        } else if (isaXcodeColorTTY) {
            resetCodeLen = (NSUInteger)MAX(snprintf(resetCode, 8, XCODE_COLORS_RESET), 0);
        } else {
            resetCode[0] = '\0';
            resetCodeLen = 0;
        }
    }

    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:
            @"<KCLTTYLoggerColorProfile: %p mask:%i ctxt:%ld fg:%u,%u,%u bg:%u,%u,%u fgCode:%@ bgCode:%@>",
            self, (int)mask, (long)context, fg_r, fg_g, fg_b, bg_r, bg_g, bg_b, fgCodeRaw, bgCodeRaw];
}

@end
