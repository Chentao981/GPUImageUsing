//
//  KCLOpenGLImageView.h
//  H264Decoder
//
//  Created by Chentao on 2017/12/11.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface KCLOpenGLImageView : UIView

@property (nonatomic, readonly) CGSize imageSize;

- (void)renderImageBuffer:(CVImageBufferRef)imageBuffer;

@end
