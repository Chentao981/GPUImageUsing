

#ifndef KCL_LEGACY_MACROS
    #define KCL_LEGACY_MACROS 0
#endif

#import "KCLLog.h"


#define LOG_LEVEL_DEF KCLLogLevelDebug

#ifndef LOG_ASYNC_ENABLED
    #define LOG_ASYNC_ENABLED YES
#endif


#define LOG_MACRO(isAsynchronous, lvl, flg, ctx, atag, fnct, frmt, ...) \
        [KCLLog log : isAsynchronous                                     \
             level : lvl                                                \
              flag : flg                                                \
           context : ctx                                                \
              file : __FILE__                                           \
          function : fnct                                               \
              line : __LINE__                                           \
               tag : atag                                               \
            format : (frmt), ## __VA_ARGS__]


#define LOG_MAYBE(async, lvl, flg, ctx, tag, fnct, frmt, ...) \
        do { if(lvl & flg) LOG_MACRO(async, lvl, flg, ctx, tag, fnct, frmt, ##__VA_ARGS__); } while(0)


#define KCLLogError(frmt, ...)   LOG_MAYBE(NO,                LOG_LEVEL_DEF, KCLLogFlagError,   0, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)
#define KCLLogWarn(frmt, ...)    LOG_MAYBE(LOG_ASYNC_ENABLED, LOG_LEVEL_DEF, KCLLogFlagWarning, 0, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)
#define KCLLogInfo(frmt, ...)    LOG_MAYBE(LOG_ASYNC_ENABLED, LOG_LEVEL_DEF, KCLLogFlagInfo,    0, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)
#define KCLLogDebug(frmt, ...)   LOG_MAYBE(LOG_ASYNC_ENABLED, LOG_LEVEL_DEF, KCLLogFlagDebug,   0, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)
#define KCLLogVerbose(frmt, ...) LOG_MAYBE(LOG_ASYNC_ENABLED, LOG_LEVEL_DEF, KCLLogFlagVerbose, 0, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)

