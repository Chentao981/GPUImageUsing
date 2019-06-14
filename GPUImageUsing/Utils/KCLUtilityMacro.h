//
//  KCLUtilityMacro.h
//  KCLiveSDK
//
//  Created by Chentao on 2017/5/27.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#ifndef KCLUtilityMacro_h
#define KCLUtilityMacro_h

#define KCLLiveMacTempFile_Prefix @"__macosx"

#define KCLLiveFile_Suffix @".kc"
#define KCLLiveMetaFile_Suffix @".kpm"

#define KCLLiveUnarchiveMarkFile_Suffix @"uzm"

#define KCLLiveCoursewareFile_Suffix @".pdf"

#define KCLLiveCoursewareFile_Extension @"pdf"

#define KCLLiveIndexFile_Extension @"kcindex"

#define KCLPlaybackDataFile_Extension @"kpd"
#define KCLPlaybackDataMarkFile_Extension @"kpdmark"

#define KCLLiveDeviceType 4

#define KCLSpeedPingTimeOut 1000

#define KCLLiveFileService_Error_Domain @"com.kaochong.live.fileservice.error"

static const size_t byteLength = sizeof(uint8_t);
static const size_t int16Length = sizeof(int16_t);
static const size_t int32Length = sizeof(int32_t);
static const size_t uint32Length = sizeof(uint32_t);

static int const KCL_DEFAULT_VIDEO_FPS = 5; //默认频率


typedef NS_ENUM(NSUInteger, KCLTeachingViewPanDirection) {
    KCLTeachingViewPanDirectionLeft,
    KCLTeachingViewPanDirectionRight,
};

typedef NS_ENUM(NSUInteger, KCLTalkViewState) {
    KCLTalkViewStatePutuphands = 1,
    KCLTalkViewStatePutuphandsReady = 2,
    KCLTalkViewStateLinkmic = 3,
};

typedef NS_ENUM(NSUInteger, KCLRoomState) {
    KCLRoomStateLive = 1,            //直播中
    KCLRoomStatePlayBackPrepare = 2, //回放准备中
    KCLRoomStatePlayBack = 3,        //回放
};


//离线文件加载相关错误

typedef NS_ENUM(NSUInteger, KCLLiveFileServiceErrorCode) {
    KCLLiveFileServiceErrorCodeFileNotExists = 1000,
    KCLLiveFileServiceErrorCodeOpenFileFail = 1001,
    KCLLiveFileServiceErrorCodeFileInvalid = 1002,
    KCLLiveFileServiceErrorCodeUnarchiveFileFail = 1003,
    KCLLiveFileServiceErrorCodeSignalIndexNotFound = 1004,
};

#endif /* KCLUtilityMacro_h */
