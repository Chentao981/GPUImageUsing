//
//  KCLH264Decoder.h
//  H264Decoder
//
//  Created by Chentao on 2017/11/28.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "KCLVideoFrameData.h"
#import "KCLSafeMutableArray.h"

@class KCLH264Decoder;
@protocol KCLH264DecoderDelegate <NSObject>

@optional

- (void)h264DecoderReceiveFrameData:(KCLH264Decoder *)decoder;
//- (void)h264Decoder:(KCLH264Decoder *)decoder popFrameData:(KCLVideoFrameData *)frameData;

@end

@interface KCLH264Decoder : NSObject

@property (nonatomic, copy) NSString *decoderId;

@property (nonatomic, weak) id<KCLH264DecoderDelegate> delegate;

@property (nonatomic, strong) KCLSafeMutableArray *frameDatas;

/**
 * 缓存的最大的解码后的帧数，如果等于这个值则停止解码
 **/
@property (nonatomic, assign) NSUInteger maxFrameDataCount;

- (void)pushData:(NSData *)data timeLine:(uint32_t)timeLine;

- (void)reset;

- (void)destroy;

@end
