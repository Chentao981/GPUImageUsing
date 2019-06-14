//
//  KCLVideoFrameData.m
//  KCLiveSDK
//
//  Created by Chentao on 2017/12/1.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import "KCLVideoFrameData.h"

@implementation KCLVideoFrameData

- (void)setPixelBuffer:(CVImageBufferRef)pixelBuffer {
    _pixelBuffer = CVPixelBufferRetain(pixelBuffer);
}

- (void)dealloc {
    if (_pixelBuffer) {
        CVPixelBufferRelease(_pixelBuffer);
    }
}

@end
