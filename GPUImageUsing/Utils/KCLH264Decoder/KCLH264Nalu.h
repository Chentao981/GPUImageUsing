//
//  KCLH264Nalu.h
//  KCLiveSDK
//
//  Created by Chentao on 2017/12/26.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, KCLH264NALUType) {
    KCLH264NALUTypeIDR = 5,
    KCLH264NALUTypeSPS = 7,
    KCLH264NALUTypePPS = 8,
};

@interface KCLH264Nalu : NSObject

@property (nonatomic, assign) int startCodeLength;
@property (nonatomic, strong) NSData *naluData;
@property (nonatomic, assign) NSUInteger naluType;
@property (nonatomic, assign) int nextStartCodeLength;
@property (nonatomic, assign) BOOL bad;

@end
