//
//  KCLVideoFrameData.h
//  KCLiveSDK
//
//  Created by Chentao on 2017/12/1.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface KCLVideoFrameData : NSObject

//@property (nonatomic, strong) UIImage *frameImage;
@property (nonatomic, assign) uint32_t timeLine;

@property (nonatomic) CVImageBufferRef pixelBuffer;

@property (nonatomic, copy) NSString *decoderId;

@end
