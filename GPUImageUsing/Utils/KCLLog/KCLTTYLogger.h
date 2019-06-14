

#ifndef KCL_LEGACY_MACROS
    #define KCL_LEGACY_MACROS 0
#endif

#import "KCLLog.h"

#define LOG_CONTEXT_ALL INT_MAX

#if TARGET_OS_IPHONE
    // iOS
    #import <UIKit/UIColor.h>
    #define KCLColor UIColor
    #define KCLMakeColor(r, g, b) [UIColor colorWithRed:(r/255.0f) green:(g/255.0f) blue:(b/255.0f) alpha:1.0f]
#elif __has_include(<AppKit/NSColor.h>)
    // OS X with AppKit
    #import <AppKit/NSColor.h>
    #define KCLColor NSColor
    #define KCLMakeColor(r, g, b) [NSColor colorWithCalibratedRed:(r/255.0f) green:(g/255.0f) blue:(b/255.0f) alpha:1.0f]
#else
    // OS X CLI
    #import "CLIColor.h"
    #define KCLColor CLIColor
    #define KCLMakeColor(r, g, b) [CLIColor colorWithCalibratedRed:(r/255.0f) green:(g/255.0f) blue:(b/255.0f) alpha:1.0f]
#endif

@interface KCLTTYLogger : KCLAbstractLogger <KCLLogger>

+ (instancetype)sharedInstance;

@property (readwrite, assign) BOOL colorsEnabled;

@property (nonatomic, readwrite, assign) BOOL automaticallyAppendNewlineForCustomFormatters;

- (void)setForegroundColor:(KCLColor *)txtColor backgroundColor:(KCLColor *)bgColor forFlag:(KCLLogFlag)mask;

- (void)setForegroundColor:(KCLColor *)txtColor backgroundColor:(KCLColor *)bgColor forFlag:(KCLLogFlag)mask context:(NSInteger)ctxt;

- (void)setForegroundColor:(KCLColor *)txtColor backgroundColor:(KCLColor *)bgColor forTag:(id <NSCopying>)tag;

- (void)clearColorsForFlag:(KCLLogFlag)mask;
- (void)clearColorsForFlag:(KCLLogFlag)mask context:(NSInteger)context;
- (void)clearColorsForTag:(id <NSCopying>)tag;
- (void)clearColorsForAllFlags;
- (void)clearColorsForAllTags;
- (void)clearAllColors;

@end
