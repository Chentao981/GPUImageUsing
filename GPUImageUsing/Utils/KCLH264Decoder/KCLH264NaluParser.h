//
//  KCLH264NaluParser.h
//  KCLiveSDK
//
//  Created by Chentao on 2017/12/6.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KCLH264Nalu.h"

@class KCLH264NaluParser;
@protocol KCLH264NaluParserDelegate <NSObject>

@required

- (void)h264NaluParser:(KCLH264NaluParser *)parser receiveNalu:(KCLH264Nalu *)naluData;

@end

@interface KCLH264NaluParser : NSObject

@property (nonatomic, weak) id<KCLH264NaluParserDelegate> delegate;

//- (void)pushData:(NSData *)data;

- (void)pushData:(uint8_t *)data size:(NSUInteger)size;

- (void)clear;

@end
