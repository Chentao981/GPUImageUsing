//
//  KCLLogger.h
//  KCLiveSDK
//
//  Created by Chentao on 2017/9/7.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>

// Disable legacy macros
#ifndef KCL_LEGACY_MACROS
#define KCL_LEGACY_MACROS 0
#endif

// Core
#import "KCLLog.h"

#import "KCLLogMacros.h"

// Capture ASL
#import "KCLASLLogCapture.h"

// Loggers
#import "KCLTTYLogger.h"
#import "KCLASLLogger.h"
#import "KCLFileLogger.h"
