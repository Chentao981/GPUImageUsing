

#import <Foundation/Foundation.h>

#ifndef KCL_LEGACY_MACROS
    #define KCL_LEGACY_MACROS 0
#endif

#import "KCLLog.h"


@interface KCLASLLogger : KCLAbstractLogger <KCLLogger>

+ (instancetype)sharedInstance;

@end
