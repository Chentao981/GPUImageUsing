//
//  KCLH264Encoder.h
//  CameraVideoCapture
//
//  Created by Chentao on 2019/5/16.
//  Copyright © 2019 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class KCLH264Encoder;
@protocol KCLH264EncoderDelegate <NSObject>

-(void)h264Encoder:(KCLH264Encoder *)encoder encodeOutputData:(NSData *)data;

@end

@interface KCLH264Encoder : NSObject

@property(nonatomic,weak)id <KCLH264EncoderDelegate> delegate;

@property(nonatomic,assign)int frameRate;

@property(nonatomic,assign)int maxKeyFrameInterval;

@property(nonatomic,readonly)BOOL initialize;

-(void)configurationEncoderWithWidth:(int)width height:(int)height;

- (void)encode:(CMSampleBufferRef )sampleBuffer;

@end

NS_ASSUME_NONNULL_END
